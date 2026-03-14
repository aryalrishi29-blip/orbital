# Runbook: Cost Spike Alert

**Alert:** Kubecost budget threshold breached
**Triggered by:** Slack notification from Kubecost budget alert

---

## Step 1 — Open Kubecost

```bash
kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090
# http://localhost:9090
```

Navigate to: **Allocations** → filter by `namespace=orbital` → set window to `Last 7 days`.

---

## Step 2 — Identify the spike

Common causes:

| Finding | Action |
|---------|--------|
| New deployment with higher resource requests | Review `k8s/base/deployment.yaml` requests — are they justified? |
| HPA scaled to max replicas (10) | Check if traffic spike was real or a bug causing excessive load |
| Idle cost increased | Check if HPA is scaling down correctly after traffic drops |
| New namespace appeared | Check for rogue test deployments — `kubectl get ns` |
| RDS bill increased | Check slow queries, check if RDS is autoscaling storage |

---

## Step 3 — Rightsizing recommendations

```bash
# View Kubecost rightsizing recommendations
curl http://localhost:9090/model/savings/requestSizingV2 \
  | python3 -m json.tool | head -50
```

Kubecost will suggest specific CPU/memory adjustments.
Apply them to `k8s/base/deployment.yaml` and the production overlay.

---

## Step 4 — Prevent recurrence

- Set `resources.requests` based on actual 95th percentile usage, not gut feel
- Enable the HPA scale-down stabilization window (already configured to 5 min)
- Use Spot instances for non-critical workloads via node group labels
- Review the weekly FinOps report every Monday

---

*Last updated: 2025-01-01 | Owner: platform-team*
