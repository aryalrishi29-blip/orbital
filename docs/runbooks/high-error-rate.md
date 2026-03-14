# Runbook: DjangoHighErrorRate

**Alert:** `DjangoHighErrorRate`
**Severity:** Critical
**SLO:** 99.5% of HTTP requests return non-5xx responses

---

## What this means

More than 0.5% of requests to the Django app are returning HTTP 5xx responses
over a 5-minute window. This is burning the error budget.

---

## Step 1 — Triage (< 2 minutes)

```bash
# Is the app running?
kubectl get pods -n orbital

# How many pods are healthy?
kubectl get deployment orbital -n orbital

# Quick error rate check
kubectl logs -n orbital -l app=orbital --tail=50 | grep '"status": 5'
```

Check Grafana → Django App Overview → **Error rate** panel for the trend.
Is it a spike or steady climb?

---

## Step 2 — Identify the failing endpoint

```bash
# Which views are erroring?
kubectl logs -n orbital -l app=orbital --tail=200 \
  | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        d = json.loads(line.strip())
        if d.get('status', 0) >= 500:
            print(d)
    except:
        pass
"
```

Or in Grafana → **Top 10 slowest views** table — filter by status 5xx.

---

## Step 3 — Check for recent deploy

```bash
# Was there a recent deployment?
kubectl rollout history rollout/orbital -n orbital

# What image is running?
kubectl get rollout orbital -n orbital -o jsonpath='{.spec.template.spec.containers[0].image}'
```

If errors started after a deploy → **go to Step 4 (rollback)**.
If no recent deploy → **go to Step 5 (runtime issues)**.

---

## Step 4 — Rollback (if caused by bad deploy)

ArgoCD Rollouts makes rollback instant:

```bash
# Option A: Abort the current rollout (reverts to previous version immediately)
kubectl argo rollouts abort orbital -n orbital

# Option B: Roll back to a specific revision
kubectl argo rollouts undo orbital -n orbital --to-revision=2

# Verify rollback completed
kubectl argo rollouts status orbital -n orbital
```

Verify error rate drops in Grafana within 2 minutes.

---

## Step 5 — Runtime issues (no recent deploy)

### Check database

```bash
# Are DB queries failing?
kubectl logs -n orbital -l app=orbital --tail=100 | grep -i "database\|psycopg\|connection"

# Test DB connectivity from inside a pod
kubectl exec -it -n orbital \
  $(kubectl get pod -n orbital -l app=orbital -o jsonpath='{.items[0].metadata.name}') \
  -- python manage.py dbshell -- -c "SELECT 1;"
```

If DB is unreachable: check RDS console → check security groups → check that
`DB_HOST` secret matches the RDS endpoint.

### Check pod resources

```bash
# Is any pod OOMKilled or CrashLooping?
kubectl describe pods -n orbital | grep -A5 "Last State\|OOMKilled\|Reason"

# Check memory usage vs limits
kubectl top pods -n orbital
```

If pods are OOMKilling: increase `resources.limits.memory` in
`k8s/base/deployment.yaml` and redeploy.

### Check upstream dependencies

```bash
# Any external service calls timing out?
kubectl logs -n orbital -l app=orbital --tail=200 | grep -i "timeout\|connection refused"
```

---

## Step 6 — Escalate

If error rate continues after 15 minutes:

1. Page the on-call engineer via PagerDuty
2. Post in `#incidents` Slack channel with:
   - Current error rate (from Grafana)
   - Steps taken so far
   - Whether rollback was attempted
3. Open a war room in `#incident-<YYYY-MM-DD>`

---

## Step 7 — Post-incident

1. File an incident report in `docs/incidents/`
2. Add a test that would have caught the regression
3. Update this runbook if anything was missing

---

*Last updated: 2025-01-01 | Owner: platform-team*
