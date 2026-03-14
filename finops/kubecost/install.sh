#!/usr/bin/env bash
# =============================================================
# Install Kubecost for cloud cost monitoring on EKS.
#
# What Kubecost gives you:
#   - Per-namespace, per-deployment, per-pod cost breakdown
#   - Idle resource identification (overprovisioned pods)
#   - Cost allocation by team/service/environment label
#   - Savings recommendations (rightsizing, reserved instances)
#   - Budget alerts via Slack/PagerDuty
#
# Orbital uses it to prove FinOps maturity — cost per API request,
# namespace cost budgets, and waste elimination reports.
#
# Cost: Free tier covers single-cluster up to 15 nodes.
# =============================================================
set -euo pipefail

NAMESPACE="kubecost"
KUBECOST_VERSION="1.108.0"

echo "Adding Kubecost Helm repo..."
helm repo add kubecost https://kubecost.github.io/cost-analyzer/
helm repo update

echo "Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Kubecost v${KUBECOST_VERSION}..."
helm upgrade --install kubecost kubecost/cost-analyzer \
  --namespace  "$NAMESPACE" \
  --version    "$KUBECOST_VERSION" \
  --values     finops/kubecost/values.yaml \
  --wait \
  --timeout    8m

echo ""
echo "========================================"
echo " Kubecost installed!"
echo "========================================"
echo " Dashboard: kubectl port-forward svc/kubecost-cost-analyzer -n kubecost 9090:9090"
echo " URL:       http://localhost:9090"
echo ""
echo " Key views:"
echo "   Allocations → filter by namespace=orbital"
echo "   Savings      → rightsizing recommendations"
echo "   Assets       → EC2 node costs"
echo "========================================"
