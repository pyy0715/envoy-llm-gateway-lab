#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Envoy AI Gateway Lab - Cluster Setup ==="
echo ""

# Check dependencies
if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed."
    echo "Install: https://kind.sigs.k8s.io/docs/user/quick-start/"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed."
    echo "Install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

if ! docker info &> /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

CLUSTER_NAME="ai-gateway-lab"

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '$CLUSTER_NAME' already exists."
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    else
        echo "Keeping existing cluster. Exiting."
        exit 0
    fi
fi

echo "Creating kind cluster '$CLUSTER_NAME'..."
kind create cluster --name "$CLUSTER_NAME" --config "$PROJECT_DIR/kind-config.yaml"

echo ""
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# cloud-provider-kind: enables LoadBalancer support in kind
echo ""
echo "Installing cloud-provider-kind (LoadBalancer support)..."
if ! command -v cloud-provider-kind &> /dev/null; then
    brew install cloud-provider-kind 2>/dev/null || \
    go install sigs.k8s.io/cloud-provider-kind@latest 2>/dev/null || \
    echo "⚠️  cloud-provider-kind 설치 실패. 수동 설치: https://github.com/kubernetes-sigs/cloud-provider-kind"
fi
nohup cloud-provider-kind > /tmp/cloud-provider-kind.log 2>&1 &
echo "cloud-provider-kind PID: $! (log: /tmp/cloud-provider-kind.log)"

echo ""
echo "=== Cluster Info ==="
kubectl cluster-info
echo ""
kubectl get nodes
echo ""
echo "✅ Cluster setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/02-install-gateway-api.sh"
echo "  2. Run: ./scripts/03-install-envoy-gateway.sh"
echo "  3. Run: ./scripts/04-install-ai-gateway.sh"
echo "  4. Run: ./scripts/05-deploy-all.sh"
