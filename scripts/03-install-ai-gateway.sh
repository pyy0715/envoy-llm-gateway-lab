#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Installing AI Gateway CRDs ==="

INFERENCE_EXTENSION_VERSION="v1.3.1"
AI_GATEWAY_VERSION="v0.5.0"
NAMESPACE="envoy-ai-gateway-system"

echo "Inference Extension: $INFERENCE_EXTENSION_VERSION"
echo "AI Gateway: $AI_GATEWAY_VERSION"
echo ""

# InferencePool CRDs
echo "[1/2] InferencePool CRDs..."
kubectl apply --server-side --force-conflicts \
  -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/${INFERENCE_EXTENSION_VERSION}/manifests.yaml"
kubectl wait --for=condition=Established crd/inferencepools.inference.networking.k8s.io --timeout=60s
kubectl wait --for=condition=Established crd/inferenceobjectives.inference.networking.x-k8s.io --timeout=60s

# AI Gateway CRDs + Controller
echo ""
echo "[2/2] AI Gateway..."
helm upgrade --install aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace

helm upgrade --install aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version "$AI_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace

kubectl wait --timeout=5m -n "$NAMESPACE" deployment/ai-gateway-controller --for=condition=Available

echo ""
echo "=== AI Gateway Installed ==="
echo ""
echo "Next: ./scripts/04-deploy-all.sh"
