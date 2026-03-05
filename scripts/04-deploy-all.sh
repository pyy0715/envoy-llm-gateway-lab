#!/bin/bash
set -e

# KUBECONFIG default for k3s
export KUBECONFIG=${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying vLLM GPU + AI Gateway ==="
echo ""

# vLLM GPU Backend
echo "[1/3] Deploying vLLM GPU..."
kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-qwen.yaml"

echo ""
echo "Waiting for vLLM pods (3-10 min for model download + GPU init)..."
kubectl wait --for=condition=Ready pods -l app=vllm-qwen --timeout=600s

# InferencePool + EPP
echo ""
echo "[2/3] Deploying InferencePool + EPP..."
kubectl apply -f "$PROJECT_DIR/k8s/inference-pool/qwen/"
kubectl wait --for=condition=Available deployment/vllm-qwen-epp --timeout=300s

# AI Gateway
echo ""
echo "[3/3] Deploying AI Gateway..."
kubectl apply -f "$PROJECT_DIR/k8s/ai-gateway/"
kubectl wait --for=condition=Programmed gateway/ai-gateway --timeout=120s

# Status
echo ""
echo "=== Status ==="
kubectl get pods -l 'app in (vllm-qwen,vllm-qwen-epp)' -o wide
echo ""
kubectl get gateway,inferencepool

GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}')
echo ""
echo "=== Done ==="
echo "API: http://${GATEWAY_IP}:8888"
echo ""
echo "Test: ./test/smart-routing-test.sh"
