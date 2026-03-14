# Runbook: Blue-Green Deployment & Rollback

**Alert:** `DjangoRolloutDegraded`
**Tool:** ArgoCD Rollouts (`kubectl argo rollouts`)

---

## Understanding the blue-green lifecycle

```
CI pushes new image tag → ArgoCD detects manifest change
        ↓
Green ReplicaSet created (previewReplicaCount=3)
        ↓
Green pods pass readiness probes (/health/)
        ↓
AnalysisTemplate runs (10× over 5 min, checks Prometheus)
        ↓
   ┌────────────┐         ┌──────────────────────┐
   │ >= 99% OK  │ ──────► │ Traffic switches      │
   └────────────┘         │ Blue scaled down 5min │
                          └──────────────────────┘
   ┌────────────┐
   │ < 99% OK   │ ──────► Automatic rollback
   └────────────┘         Green deleted, Blue stays active
```

---

## Check rollout status

```bash
# Full rollout status
kubectl argo rollouts status orbital -n orbital

# Get rollout details (phase, conditions, analysis)
kubectl argo rollouts get rollout orbital -n orbital

# Watch live (updates every 1s)
kubectl argo rollouts get rollout orbital -n orbital --watch
```

---

## Scenarios and actions

### Rollout stuck in Progressing

```bash
# See why it's stuck
kubectl argo rollouts describe rollout orbital -n orbital | grep -A10 "Conditions"

# Check if green pods are starting
kubectl get pods -n orbital -l app=orbital

# Check events
kubectl get events -n orbital --sort-by='.lastTimestamp' | tail -20
```

Common causes:
- Image pull failure → check ECR permissions, image tag exists
- Init container failing → `kubectl logs <pod> -c run-migrations -n orbital`
- Readiness probe failing → `kubectl describe pod <pod> -n orbital`

### Analysis failing (error rate check)

```bash
# See analysis run details
kubectl get analysisrun -n orbital
kubectl describe analysisrun -n orbital <name>

# Manually check the Prometheus query
curl -G 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(django_http_requests_total{namespace="orbital",status!~"5.."}[2m])) / sum(rate(django_http_requests_total{namespace="orbital"}[2m]))'
```

If the error rate is genuinely high → let the automatic rollback complete.
If it's a false positive (Prometheus down, no traffic yet) → manually promote:

```bash
kubectl argo rollouts promote orbital -n orbital
```

### Manual rollback (immediate)

```bash
# Abort rolls back to the previous active (blue) version instantly
kubectl argo rollouts abort orbital -n orbital

# Verify
kubectl argo rollouts status orbital -n orbital
# Should show: Healthy
```

### Roll back to a specific previous version

```bash
# List revision history
kubectl argo rollouts history rollout orbital -n orbital

# Roll back to revision 3
kubectl argo rollouts undo orbital -n orbital --to-revision=3
```

---

## Preview service (testing green before promotion)

```bash
# Port-forward to the preview (green) service to test manually
kubectl port-forward svc/orbital-preview -n orbital 8001:80

# Test against green only
curl http://localhost:8001/health/
curl http://localhost:8001/api/articles/
```

---

## Emergency: bypass ArgoCD and patch directly

Only in a severe incident where ArgoCD is unavailable:

```bash
# Scale up the previous ReplicaSet directly
kubectl scale replicaset -n orbital \
  $(kubectl get rs -n orbital -l app=orbital --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-2].metadata.name}') \
  --replicas=3

# Scale down the broken one
kubectl scale replicaset -n orbital \
  $(kubectl get rs -n orbital -l app=orbital --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1].metadata.name}') \
  --replicas=0
```

After the incident, sync ArgoCD to restore GitOps-controlled state:
```bash
argocd app sync orbital-production --force
```

---

*Last updated: 2025-01-01 | Owner: platform-team*
