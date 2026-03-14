# Architecture & Design Decisions

This document records the key architecture decisions made in this project
and the reasoning behind each choice.

---

## System overview

```
Developer machine
  │
  │  git push origin main
  ▼
GitHub (source of truth)
  │
  ├── PR opened → pr-checks.yml
  │     lint · format · bandit · tests · docker build check
  │
  └── push to main → ci-cd.yml
        │
        ├── Job: test
        │     Postgres service container
        │     migrations + pytest + coverage ≥ 80%
        │
        ├── Job: build-and-push
        │     docker buildx (linux/amd64)
        │     push :sha + :latest → Amazon ECR
        │     ECR vulnerability scan
        │
        └── Job: deploy  [environment: production]
              SSH → EC2
              pull image → migrate → swap container
              health check → prune

        (develop branch → staging.yml follows the same path
         but deploys to a separate EC2 on port 8001, no approval gate)
```

---

## ADR-001: Single EC2 instance vs ECS / EKS

**Decision:** Single EC2 instance with Docker.

**Rationale:** This is a portfolio project demonstrating CI/CD concepts.
ECS Fargate or EKS would be more appropriate for production workloads with
variable traffic, but they add significant complexity (task definitions,
ALB target groups, service discovery) that would obscure the CI/CD patterns
being demonstrated. A single EC2 instance with Docker is the simplest
deployment target that still demonstrates real-world containerisation.

**Upgrade path:** To move to ECS, replace the SSH deploy step with an
`aws ecs update-service --force-new-deployment` call after pushing the image.
The Dockerfile and ECR push steps are identical.

---

## ADR-002: GitHub Actions over Jenkins / GitLab CI

**Decision:** GitHub Actions.

**Rationale:** No infrastructure to manage (no Jenkins server to maintain),
native integration with GitHub PRs (status checks, coverage comments),
and the marketplace provides maintained actions for AWS authentication,
ECR login, and SSH deployment. The YAML syntax is readable and version-controlled
alongside the application code.

---

## ADR-003: Multi-stage Dockerfile

**Decision:** Two-stage build — `builder` (installs deps) → `production` (runtime only).

**Rationale:** Eliminates build tools (gcc, make, pkg-config) from the
production image. Reduces image size by ~60% and removes an entire class
of potential vulnerabilities from the attack surface. The builder stage
installs into `/install` with `pip install --prefix`, which is then
`COPY --from=builder`'d into the production stage.

---

## ADR-004: Gunicorn (sync) over async workers

**Decision:** Gunicorn with sync workers.

**Rationale:** The application has no async I/O (no WebSockets, no long-polling).
Sync workers are the simplest and most battle-tested option. Worker count
is set to 3 (suitable for a t3.micro). To switch to async, replace `sync`
with `gevent` or `uvicorn.workers.UvicornWorker` in the CMD — no other
code changes required because Django's ASGI/WSGI interface abstracts this.

---

## ADR-005: Whitenoise for static files

**Decision:** Whitenoise middleware serves static files directly from Gunicorn.

**Rationale:** Avoids the need to configure a separate Nginx instance just
for static files in development and early production. Whitenoise compresses
and caches static files efficiently. For high-traffic production, move
static files to S3 + CloudFront by changing `STATICFILES_STORAGE` — no
template or view changes required.

---

## ADR-006: Environment variables for all configuration

**Decision:** All configuration (secrets, database credentials, feature flags)
read from environment variables via `os.environ.get()`.

**Rationale:** Follows the [12-Factor App](https://12factor.net/config)
methodology. The same Docker image runs unchanged in local Docker Compose,
the GitHub Actions CI environment, staging, and production — only the
environment variables differ. This makes environment promotion (staging → prod)
a configuration change, not a code change.

---

## ADR-007: Terraform for infrastructure

**Decision:** Terraform (not AWS CDK, CloudFormation, or Pulumi).

**Rationale:** Terraform's HCL is readable by anyone familiar with YAML/JSON,
has the broadest provider ecosystem, and is the most common IaC tool in
job descriptions. The state file is committed to S3 (once the backend block
is uncommented) so infrastructure changes are tracked and auditable.

---

## Backup and recovery

| Component | Backup method | Frequency | Retention |
|-----------|--------------|-----------|-----------|
| Database | `pg_dump` → gzip → S3 Standard-IA | Nightly (02:00 UTC) | 30 days |
| Application code | Git history | Every commit | Indefinite |
| Docker images | Amazon ECR | Every deploy | 10 tagged + 7 days untagged |
| Terraform state | S3 with versioning | Every `apply` | Indefinite |

Recovery: see `scripts/restore-db.sh` for database restoration procedure.

---

## Security controls

| Control | Implementation |
|---------|----------------|
| Secrets management | GitHub Actions encrypted secrets + environment protection |
| IAM least-privilege | Separate IAM user (CI push) and IAM role (EC2 pull) with minimal permissions |
| Container security | Non-root user (`appuser`), no build tools in production image |
| Image scanning | ECR scan-on-push, results logged in pipeline |
| Transport security | HTTPS enforced via Nginx redirect, TLS 1.2+ only |
| SSH access | Key-based auth only, password auth disabled |
| HTTP security headers | X-Frame-Options, X-Content-Type-Options, HSTS via Nginx |
| Rate limiting | 60 req/min per IP via `RateLimitMiddleware` |
