#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Deploying vLLM CPU + AI Gateway ==="
echo ""

# vLLM CPU Backend
echo "[1/3] Deploying vLLM CPU..."
kubectl apply -f "$PROJECT_DIR/k8s/backend/vllm-qwen.yaml"

echo ""
echo "Waiting for vLLM pods (3-5 min for model download)..."
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
echo "API: http://${GATEWAY_IP}"
echo ""
echo "Test: ./test/load-test.sh 30 10"
