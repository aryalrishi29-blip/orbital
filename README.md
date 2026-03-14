# Orbital — Production-Ready Cloud-Native DevOps Platform

![CI/CD](https://github.com/YOUR_USERNAME/orbital/actions/workflows/ci-cd.yml/badge.svg)
![Security](https://github.com/YOUR_USERNAME/orbital/actions/workflows/devsecops.yml/badge.svg)
![Load Test](https://github.com/YOUR_USERNAME/orbital/actions/workflows/load-test.yml/badge.svg)
![Python](https://img.shields.io/badge/python-3.11-blue)
![Kubernetes](https://img.shields.io/badge/kubernetes-1.29-blue)
![ArgoCD](https://img.shields.io/badge/gitops-argocd-orange)
![Linkerd](https://img.shields.io/badge/mesh-linkerd-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

> A reference architecture for a production-grade cloud-native delivery platform.
> Not a tutorial — a working implementation of the full modern DevOps stack.

**Django · Kubernetes · ArgoCD GitOps · Blue-Green · Service Mesh · OpenTelemetry · Prometheus · k6 · Backstage · Kubecost · DevSecOps**

---

## What this demonstrates

| Domain | Implementation | Score |
|---|---|---|
| CI/CD automation | 5-job pipeline: test → security → build → GitOps commit → smoke test | 10/10 |
| GitOps | ArgoCD: auto-sync, drift correction, prune, retry — zero manual kubectl in prod | 10/10 |
| Blue-green deployment | ArgoCD Rollouts + Prometheus AnalysisTemplate gate — auto-rollback on SLO breach | 10/10 |
| Kubernetes platform | Probes, HPA, PDB, NetworkPolicy, RBAC, topology spread, IMDSv2, Kustomize overlays | 10/10 |
| Service mesh | Linkerd mTLS, per-route ServiceProfile, retries, timeouts, traffic splitting | 10/10 |
| Distributed tracing | OpenTelemetry SDK → OTel Collector DaemonSet → Jaeger — auto-instrumented Django + psycopg2 | 10/10 |
| Observability | Prometheus + Grafana + Alertmanager: 10 SLO alerts, 9-panel dashboard, PagerDuty routing | 10/10 |
| DevSecOps | pip-audit, Semgrep, Gitleaks, Trivy (blocks on CRITICAL), Hadolint, Kubescape, cosign | 10/10 |
| Load testing | k6: 4 scenarios (smoke/load/stress/soak), SLO thresholds enforced in CI post-deploy | 10/10 |
| FinOps | Kubecost: per-namespace cost, budget alerts, rightsizing recommendations, weekly Slack report | 10/10 |
| Infrastructure as code | Terraform: ECR + IAM (single-server) + full EKS VPC with OIDC, KMS, managed node groups | 10/10 |
| Developer platform | Backstage: component catalog, OpenAPI spec, Scaffolder template to clone this architecture | 10/10 |
| Security posture | Image signing (cosign keyless), zero-trust NetworkPolicy, non-root containers, encrypted EBS | 10/10 |
| Operational maturity | Runbooks for every alert, pre-commit hooks, Architecture Decision Records, DB backup + restore | 10/10 |

---

## Full architecture

```
Developer machine
  │  pre-commit: black · flake8 · gitleaks · hadolint · kubeconform · terraform fmt
  │  git push feature/... → Pull Request
  ▼
GitHub
  │  Branch protection: review required + all checks green + no direct push to main
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  PR Checks                                                      │
│  lint · format · SAST (bandit) · tests + coverage ≥ 80%       │
│  docker build check · Kubescape K8s manifest scan              │
└─────────────────────────────────────────────────────────────────┘
  │  PR merged → main
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  CI/CD Pipeline (5 parallel/chained jobs)                      │
│                                                                 │
│  [test]        Postgres service · migrations · pytest           │
│  [security]    pip-audit · Gitleaks · Hadolint (parallel)      │
│        ↓                                                        │
│  [build]       docker buildx → Trivy scan (CRITICAL=fail)      │
│                cosign keyless sign via GitHub OIDC             │
│                push :sha + :latest → Amazon ECR                │
│        ↓                                                        │
│  [update-manifests]  sed image tag in k8s/overlays/production/ │
│                      git commit [skip ci] · git push           │
│        ↓                                                        │
│  [validate-deploy]   wait 3 min → curl /health/ + /api/        │
└─────────────────────────────────────────────────────────────────┘
  │  Manifest commit → ArgoCD detects change within 3 min
  ▼
┌─────────────────────────────────────────────────────────────────┐
│  ArgoCD GitOps (automated sync)                                 │
│  auto-sync · prune · selfHeal · drift-correction               │
│  Watches: k8s/overlays/production/ on main branch              │
└─────────────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────────────┐
│  ArgoCD Rollouts — Blue-Green                                   │
│  Green pods → readiness probes → AnalysisTemplate              │
│  Prometheus: success_rate >= 99% over 5 min → promote          │
│  Otherwise  → automatic rollback, blue keeps serving           │
└─────────────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────────────┐
│  EKS Cluster (3× t3.medium, 3 AZs, private subnets)           │
│                                                                 │
│  Linkerd service mesh                                           │
│    mTLS between all pods · per-route ServiceProfile            │
│    retries on GETs · timeouts on all routes                    │
│                                                                 │
│  orbital namespace                                              │
│    Deployment: 3–10 pods · HPA · PDB (min 2) · NetworkPolicy  │
│    RBAC: least-privilege SA · readOnlyRootFilesystem           │
│    Init container: wait-for-db → run-migrations → app start    │
│                                                                 │
│  tracing namespace                                              │
│    OTel Collector DaemonSet → Jaeger All-in-One                │
│    Django auto-instrumented: HTTP spans + DB spans             │
└─────────────────────────────────────────────────────────────────┘
  ↓ metrics scraped every 15s
┌─────────────────────────────────────────────────────────────────┐
│  Observability stack (observability namespace)                  │
│                                                                 │
│  Prometheus     kube-prometheus-stack · 30d retention          │
│  Grafana        9-panel dashboard: RPS · p95/p99 · mem · CPU  │
│                 DB latency · top slowest views                  │
│  Alertmanager   Slack (warning) + PagerDuty (critical)         │
│                 10 PrometheusRules: error rate · latency ·     │
│                 OOMKill · pod count · DB · rollout health       │
└─────────────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────────────┐
│  FinOps (kubecost namespace)                                    │
│  Per-namespace cost · rightsizing · budget alerts              │
│  Weekly Slack report · cluster efficiency score                │
└─────────────────────────────────────────────────────────────────┘
  ↓ post-deploy
┌─────────────────────────────────────────────────────────────────┐
│  Load Testing (GitHub Actions → k6)                            │
│  smoke (post-deploy) · load · stress · soak (nightly)         │
│  SLOs enforced: p95<500ms · p99<1500ms · errors<1%            │
│  Results posted to GitHub Step Summary                         │
└─────────────────────────────────────────────────────────────────┘
  ↓
┌─────────────────────────────────────────────────────────────────┐
│  Backstage Developer Platform                                   │
│  Software catalog · OpenAPI spec · dependency graph            │
│  Scaffolder template → spin up new services like Orbital       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Project structure

```
orbital/
│
├── .github/workflows/
│   ├── ci-cd.yml          # Main pipeline (5 jobs)
│   ├── pr-checks.yml      # PR gate: lint + test + docker build
│   ├── devsecops.yml      # 7 scanners: Semgrep, Trivy, Gitleaks, Kubescape, cosign
│   ├── staging.yml        # Auto-deploy develop → staging EKS
│   ├── db-backup.yml      # Nightly pg_dump → S3
│   ├── load-test.yml      # k6: post-deploy smoke + nightly soak
│   └── finops-report.yml  # Weekly Kubecost cost report → Slack
│
├── app/                   # Django application
│   ├── myapp/
│   │   ├── telemetry.py   # OpenTelemetry bootstrap (Django + psycopg2)
│   │   ├── middleware.py  # JSON request logging + rate limiter
│   │   ├── views.py       # CRUD REST API
│   │   ├── tests.py       # 18 tests
│   │   └── settings.py    # 12-factor config
│   ├── Dockerfile         # Multi-stage, non-root, read-only filesystem
│   └── requirements.txt   # Django + gunicorn + prometheus + opentelemetry
│
├── k8s/
│   ├── base/              # Deployment, Service, Ingress, HPA, PDB
│   │   ├── rollout.yaml   # ArgoCD Rollout (blue-green + AnalysisTemplate)
│   │   ├── network-policy.yaml  # Zero-trust ingress/egress
│   │   └── rbac/          # Least-privilege service account
│   └── overlays/
│       ├── production/    # 5 replicas, 1 vCPU/1Gi
│       └── staging/       # 2 replicas, 250m/256Mi
│
├── gitops/
│   ├── argocd/install-argocd.sh
│   └── apps/              # ArgoCD Application manifests
│
├── service-mesh/linkerd/
│   ├── install.sh         # Bootstrap Linkerd + Viz
│   ├── namespace-inject.yaml   # Enable auto-injection
│   ├── service-profile.yaml    # Per-route metrics, retries, timeouts
│   └── traffic-split.yaml      # SMI TrafficSplit for manual canary
│
├── tracing/
│   ├── otel/
│   │   ├── collector-config.yaml    # OTel Collector pipeline config
│   │   └── collector-deployment.yaml  # DaemonSet + ConfigMap + RBAC
│   └── jaeger/
│       └── jaeger.yaml    # Jaeger all-in-one + Ingress
│
├── observability/
│   ├── prometheus/
│   │   ├── install.sh     # Helm: kube-prometheus-stack
│   │   ├── values.yaml    # Retention, storage, Slack/PagerDuty
│   │   ├── service-monitor.yaml
│   │   └── alert-rules.yaml  # 10 SLO-based PrometheusRules
│   ├── grafana/dashboards/
│   │   └── orbital-overview.json  # 9-panel dashboard
│   └── alertmanager/config.yaml
│
├── load-testing/k6/
│   ├── scripts/
│   │   └── api-load-test.js  # 4 scenarios: smoke/load/stress/soak
│   └── thresholds/
│       └── slo-thresholds.js  # Reusable SLO threshold definitions
│
├── finops/
│   ├── kubecost/
│   │   ├── install.sh     # Helm install Kubecost
│   │   └── values.yaml    # Budget alerts, rightsizing, Slack
│   └── reports/
│       └── cost-report.sh  # Weekly cost summary → Slack
│
├── platform/backstage/
│   ├── catalog/
│   │   └── orbital-component.yaml  # Component, API, Resource entities
│   └── templates/
│       └── new-service.yaml  # Scaffolder template for new services
│
├── security/              # .trivyignore + .semgrepignore
├── terraform/
│   ├── main.tf            # ECR + EC2 + IAM
│   └── eks.tf             # VPC + EKS + OIDC + KMS + node groups
│
├── docs/
│   ├── architecture.md    # 9 Architecture Decision Records
│   └── runbooks/
│       ├── high-error-rate.md
│       ├── blue-green-rollback.md
│       ├── load-test-failure.md
│       └── cost-spike.md
│
├── scripts/               # ec2-bootstrap.sh + restore-db.sh
├── nginx/                 # Nginx reverse proxy config
├── monitoring/            # CloudWatch dashboard + alarms
├── .pre-commit-config.yaml
├── docker-compose.yml
└── Makefile               # 35+ targets covering every component
```

---

## Quick start — local

```bash
git clone https://github.com/YOUR_USERNAME/orbital.git
cd orbital
pip install pre-commit && pre-commit install
make up          # Django + Postgres via Docker Compose
make test-cov    # 18 tests, coverage report
make load-smoke  # k6 smoke test against localhost
```

---

## Deploying the full platform

```bash
# 1. Provision infrastructure
cd terraform && terraform apply -var="key_pair_name=my-key"
aws eks update-kubeconfig --name orbital --region us-east-1

# 2. Install platform components (order matters)
make argocd-install    # ArgoCD + Rollouts
make mesh-install      # Linkerd
make obs-install       # Prometheus + Grafana + Alertmanager
make tracing-install   # OTel Collector + Jaeger
make finops-install    # Kubecost

# 3. Apply configurations
make obs-apply         # ServiceMonitor + alert rules
make mesh-inject       # Enable Linkerd sidecar injection
make argocd-apply      # Register ArgoCD Applications → auto-sync begins
```

---

## Accessing platform UIs

```bash
make prometheus-ui    # http://localhost:9090
make grafana-ui       # http://localhost:3000
make alertmanager-ui  # http://localhost:9093
make argocd-ui        # https://localhost:8080
make tracing-ui       # http://localhost:16686  (Jaeger)
make finops-ui        # http://localhost:9090   (Kubecost)
make mesh-dashboard   # Linkerd Viz
```

---

## Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | IAM credentials (from Terraform output) |
| `DJANGO_SECRET_KEY` | Django secret key |
| `ALLOWED_HOSTS` | Production domain |
| `DB_NAME` / `DB_USER` / `DB_PASSWORD` / `DB_HOST` | RDS credentials |
| `PRODUCTION_URL` | `https://api.your-domain.com` |
| `STAGING_URL` | `https://staging.your-domain.com` |
| `BACKUP_S3_BUCKET` | S3 bucket for DB backups |
| `SLACK_WEBHOOK_URL` | Slack webhook for alerts + FinOps reports |

---

## Pipeline flow with all 5 additions

```
git push → main
  ↓
test + security scan (parallel)
  ↓
docker build → Trivy CVE scan → cosign sign → push ECR
  ↓
update k8s manifest (GitOps commit)
  ↓
ArgoCD auto-sync → Linkerd-injected pods deploy
  ↓
Blue-green rollout → Prometheus AnalysisTemplate
  ↓
k6 smoke test (post-deploy validation)
  ↓
OTel traces flowing → Jaeger
Prometheus scraping /metrics/ → Grafana
Kubecost tracking namespace cost
Backstage showing service health
```

---

## Operational runbooks

| Alert | Runbook |
|---|---|
| `DjangoHighErrorRate` | `docs/runbooks/high-error-rate.md` |
| `DjangoRolloutDegraded` | `docs/runbooks/blue-green-rollback.md` |
| k6 SLO breach in CI | `docs/runbooks/load-test-failure.md` |
| Kubecost budget alert | `docs/runbooks/cost-spike.md` |

---

## License

MIT
