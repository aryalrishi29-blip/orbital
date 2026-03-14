#!/usr/bin/env bash
# =============================================================
# Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
# using Helm into the observability namespace.
#
# Prerequisites:
#   - helm 3 installed
#   - kubectl configured against the target cluster
#
# Usage:
#   bash observability/prometheus/install.sh
# =============================================================
set -euo pipefail

NAMESPACE="observability"
RELEASE="kube-prometheus-stack"
CHART_VERSION="58.0.0"    # pin to a specific version for reproducibility

echo "Adding prometheus-community Helm repo..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

echo "Creating namespace ${NAMESPACE}..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Installing ${RELEASE} v${CHART_VERSION}..."
helm upgrade --install "$RELEASE" prometheus-community/kube-prometheus-stack \
  --namespace  "$NAMESPACE" \
  --version    "$CHART_VERSION" \
  --values     observability/prometheus/values.yaml \
  --wait \
  --timeout    10m

echo ""
echo "========================================"
echo " Prometheus stack installed!"
echo "========================================"
echo " Prometheus:   kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090"
echo " Grafana:      kubectl port-forward svc/kube-prometheus-stack-grafana     -n observability 3000:80"
echo " Alertmanager: kubectl port-forward svc/kube-prometheus-stack-alertmanager -n observability 9093:9093"
echo ""
GRAFANA_PASS=$(kubectl get secret --namespace observability \
  kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode)
echo " Grafana admin password: ${GRAFANA_PASS}"
echo "========================================"
