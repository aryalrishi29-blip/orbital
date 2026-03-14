#!/usr/bin/env bash
# =============================================================
# Bootstrap ArgoCD on an EKS cluster
# Run once after cluster creation.
#
# Prerequisites:
#   - kubectl configured against the target cluster
#   - helm 3 installed
#
# Usage:
#   bash gitops/argocd/install-argocd.sh
# =============================================================
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v2.10.0}"
NAMESPACE="argocd"

echo "Installing ArgoCD ${ARGOCD_VERSION}..."

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -n "$NAMESPACE" \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "Waiting for ArgoCD server to be ready..."
kubectl rollout status deployment/argocd-server -n "$NAMESPACE" --timeout=120s

# Install ArgoCD Rollouts controller (for blue-green / canary)
echo "Installing ArgoCD Rollouts..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

kubectl rollout status deployment/argo-rollouts -n argo-rollouts --timeout=120s

# Get initial admin password
INITIAL_PASSWORD=$(kubectl get secret argocd-initial-admin-secret \
  -n "$NAMESPACE" \
  -o jsonpath="{.data.password}" | base64 --decode)

echo ""
echo "========================================"
echo " ArgoCD is ready!"
echo "========================================"
echo " UI:       kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo " Username: admin"
echo " Password: $INITIAL_PASSWORD"
echo ""
echo " Next: apply the Application manifests:"
echo "   kubectl apply -f gitops/apps/"
echo "========================================"
