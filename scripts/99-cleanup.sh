#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Cleanup ==="
echo ""

read -p "Delete all resources? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Delete Kubernetes resources
echo "Deleting Kubernetes resources..."
kubectl delete -f "$PROJECT_DIR/k8s/ai-gateway/" --ignore-not-found
kubectl delete -f "$PROJECT_DIR/k8s/inference-pool/qwen/" --ignore-not-found
kubectl delete -f "$PROJECT_DIR/k8s/backend/vllm-qwen.yaml" --ignore-not-found
kubectl delete -f "$PROJECT_DIR/k8s/monitoring/vllm-dashboard.yaml" --ignore-not-found

# Uninstall Helm releases
echo "Uninstalling Helm releases..."
helm uninstall aieg -n envoy-ai-gateway-system --ignore-not-found 2>/dev/null || true
helm uninstall aieg-crd -n envoy-ai-gateway-system --ignore-not-found 2>/dev/null || true
helm uninstall kube-prometheus-stack -n monitoring --ignore-not-found 2>/dev/null || true
helm uninstall eg -n envoy-gateway-system --ignore-not-found 2>/dev/null || true

# Delete namespaces
kubectl delete namespace envoy-ai-gateway-system --ignore-not-found 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found 2>/dev/null || true
kubectl delete namespace envoy-gateway-system --ignore-not-found 2>/dev/null || true

# Delete CRDs
kubectl delete crd inferencepools.inference.networking.k8s.io --ignore-not-found 2>/dev/null || true
kubectl delete crd inferenceobjectives.inference.networking.x-k8s.io --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Cleanup Complete ==="
echo ""
echo "To uninstall k3s completely:"
echo "  /usr/local/bin/k3s-uninstall.sh"
