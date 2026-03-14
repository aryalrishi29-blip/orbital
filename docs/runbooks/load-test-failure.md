# Runbook: Load Test Failure in CI

**Alert:** k6 SLO threshold breach in GitHub Actions `load-test.yml`
**Triggered by:** Post-deploy smoke test or scheduled load test failure

---

## What this means

A k6 load test ran after deployment and one or more SLO thresholds were breached:
- p95 latency exceeded 500ms
- p99 latency exceeded 1500ms
- Error rate exceeded 1%

This means the deployment may have introduced a regression under load.

---

## Step 1 — Read the k6 summary

In the failed GitHub Actions run, open the `Parse and summarise results` step.
It shows exactly which threshold failed and by how much:

```
p95 latency:  823ms  (SLO: < 500ms)  FAIL   ← this caused the failure
p99 latency:  1102ms (SLO: < 1500ms) PASS
Error rate:   0.12%  (SLO: < 1%)     PASS
Total reqs:   4,820
```

Download the full `k6-load-test-*.json` artifact for per-endpoint breakdown.

---

## Step 2 — Correlate with Grafana

Open the Grafana dashboard for the time window of the load test:

```bash
make grafana-ui
# http://localhost:3000 → Orbital — Platform Overview
```

Check:
- Did p95 latency spike on a specific endpoint? → see "Top 10 slowest views"
- Did DB query latency spike? → see "DB query p95 latency" panel
- Did pod memory or CPU hit limits? → see "Memory / CPU per pod"
- Were any pods restarted? → see "Pod count" panel

---

## Step 3 — Check for a bad deploy

```bash
# Was there a recent image change?
kubectl argo rollouts history rollout/orbital -n orbital

# Is the rollout currently Healthy?
kubectl argo rollouts status orbital -n orbital
```

If the rollout is still in progress (blue-green analysis running):
the `AnalysisTemplate` will automatically abort if error rate is too high.
You may just need to wait — ArgoCD Rollouts will roll back automatically.

If the rollout already promoted and the regression is confirmed:

```bash
# Roll back immediately
make k8s-rollback
```

---

## Step 4 — Common causes and fixes

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| p95 spike on `/api/articles/` | Missing DB index, N+1 query | Add `select_related`, check `EXPLAIN ANALYZE` |
| All endpoints slow | Pods hitting CPU limit | Increase `resources.limits.cpu` in `k8s/base/deployment.yaml` |
| OOMKill in pods | Memory leak or limit too low | Check `container_memory_working_set_bytes`, raise limit |
| High error rate on writes | DB connection exhaustion | Check `max_connections` on RDS, add pgBouncer |
| Health check slow | Pod overloaded | Scale HPA min replicas up |

---

## Step 5 — Re-run load test manually

After fixing:

```bash
# Smoke test (quick 1-minute check)
k6 run load-testing/k6/scripts/api-load-test.js \
  -e BASE_URL=https://api.your-domain.com \
  -e SCENARIO=smoke

# Full load test
k6 run load-testing/k6/scripts/api-load-test.js \
  -e BASE_URL=https://api.your-domain.com \
  -e SCENARIO=load
```

Or trigger via GitHub Actions → `Load Test` workflow → `Run workflow`.

---

*Last updated: 2025-01-01 | Owner: platform-team*
