#!/bin/bash

set -e

echo "=== Installing Envoy Gateway ==="
echo ""

if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed."
    echo "Install: https://helm.sh/docs/intro/install/"
    exit 1
fi

ENVOY_GATEWAY_VERSION="v1.6.3"
AI_GATEWAY_VERSION="v0.5.0"
NAMESPACE="envoy-gateway-system"

echo "Envoy Gateway : $ENVOY_GATEWAY_VERSION"
echo "AI Gateway values : $AI_GATEWAY_VERSION"
echo ""

# CRDs must be installed explicitly (helm upgrade does not install new CRDs)
echo "[0/1] Installing Envoy Gateway CRDs..."
helm template eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --include-crds \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/manifests/envoy-gateway-values.yaml" \
  -f "https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/examples/inference-pool/envoy-gateway-values-addon.yaml" \
  | kubectl apply --server-side -f - 2>&1 | grep -E 'created|configured|unchanged|error' || true
echo ""

helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/manifests/envoy-gateway-values.yaml" \
  -f "https://raw.githubusercontent.com/envoyproxy/ai-gateway/${AI_GATEWAY_VERSION}/examples/inference-pool/envoy-gateway-values-addon.yaml"

echo ""
echo "Waiting for Envoy Gateway to be ready..."
kubectl wait --timeout=5m -n "$NAMESPACE" deployment/envoy-gateway --for=condition=Available

echo ""
echo "=== Envoy Gateway Status ==="
kubectl get pods -n "$NAMESPACE"

echo ""
echo "✅ Envoy Gateway installed!"
echo ""
echo "Next step: Run ./scripts/04-install-ai-gateway.sh"
