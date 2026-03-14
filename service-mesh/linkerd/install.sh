#!/usr/bin/env bash
# =============================================================
# Install Linkerd service mesh on the EKS cluster.
#
# Why Linkerd over Istio for this project:
#   - 10x lower resource overhead (matters on t3.medium nodes)
#   - mTLS enabled by default with zero config
#   - CNCF graduated project — production-proven
#   - Simpler mental model for a reference architecture
#
# What this gives Orbital:
#   - Automatic mTLS between all pods (zero-trust in-cluster)
#   - Per-route golden metrics (success rate, p99, RPS) in Linkerd Viz
#   - Traffic splitting for progressive delivery
#   - Retries and timeouts at the mesh level
#
# Prerequisites:
#   - kubectl configured against EKS cluster
#   - linkerd CLI: curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
#
# Usage:
#   bash service-mesh/linkerd/install.sh
# =============================================================
set -euo pipefail

LINKERD_VERSION="stable-2.14.10"

echo "Checking Linkerd CLI..."
linkerd version --client

echo "Pre-flight checks..."
linkerd check --pre

echo "Installing Linkerd CRDs..."
linkerd install --crds | kubectl apply -f -

echo "Installing Linkerd control plane..."
linkerd install \
  --set controllerLogLevel=info \
  --set proxyLogLevel=warn,linkerd=info \
  | kubectl apply -f -

echo "Waiting for control plane..."
linkerd check

echo "Installing Linkerd Viz (metrics + dashboard)..."
linkerd viz install | kubectl apply -f -
linkerd viz check

echo "Installing Linkerd SMI extension (TrafficSplit support)..."
linkerd smi install | kubectl apply -f - || echo "SMI optional — skipping if unavailable"

echo ""
echo "========================================"
echo " Linkerd installed!"
echo "========================================"
echo " Dashboard: linkerd viz dashboard &"
echo " Check:     linkerd check"
echo " Top:       linkerd viz top deploy/orbital -n orbital"
echo ""
echo " Next: annotate the orbital namespace to enable injection:"
echo "   kubectl annotate namespace orbital linkerd.io/inject=enabled"
echo "========================================"
