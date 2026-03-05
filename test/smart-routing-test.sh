#!/bin/bash
# EPP Smart Routing Verification Test
# Verifies that EPP routes requests based on queue depth / KV cache utilization
set -e

GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
if [ -z "$GATEWAY_IP" ]; then
    echo "Error: Gateway IP not found"
    exit 1
fi
BASE_URL="http://${GATEWAY_IP}:8888"
MODEL=${1:-"Qwen/Qwen3-0.6B"}

PODS=$(kubectl get pods -l app=vllm-qwen -o jsonpath='{.items[*].metadata.name}')
POD_COUNT=$(echo $PODS | wc -w | tr -d ' ')

echo "=== EPP Smart Routing Test ==="
echo "Gateway:  $BASE_URL"
echo "Pods:     $POD_COUNT ($PODS)"
echo "Model:    $MODEL"
echo ""

if [ "$POD_COUNT" -lt 2 ]; then
    echo "WARNING: Only $POD_COUNT pod(s) found. Smart routing requires >= 2 pods."
    echo "EPP will still be tested but load balancing cannot be demonstrated."
    echo ""
fi

# Helper: get per-pod queue metrics (single fetch per pod)
pod_metrics() {
    for pod in $PODS; do
        METRICS=$(kubectl exec $pod -- python3 -c "
import urllib.request, sys
try:
    r = urllib.request.urlopen('http://localhost:8000/metrics', timeout=5)
    sys.stdout.write(r.read().decode())
except Exception:
    pass
" 2>/dev/null || true)
        RUNNING=$(echo "$METRICS" | grep "^vllm:num_requests_running{" | awk '{print $2}' | head -1)
        WAITING=$(echo "$METRICS" | grep "^vllm:num_requests_waiting{" | awk '{print $2}' | head -1)
        KV=$(echo "$METRICS" | grep "^vllm:gpu_cache_usage_perc{" | awk '{print $2}' | head -1)
        printf "  %-50s running=%-3s waiting=%-3s kv_cache=%s\n" "$pod" "${RUNNING:-?}" "${WAITING:-?}" "${KV:-?}"
    done
}

echo "--- [1] Baseline Pod Metrics ---"
pod_metrics
echo ""

echo "--- [2] Phase 1: Saturate with SLOW requests (max_tokens=2048) ---"
echo "Sending 20 slow concurrent requests to build up queue depth on GPU..."
echo ""

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Long prompt to maximize KV cache usage + large max_tokens to keep requests in-flight
LONG_PROMPT="Please write a detailed explanation of how neural networks work, including backpropagation, gradient descent, activation functions, and the history of deep learning. Cover the mathematics behind each concept, provide examples of real-world applications, and discuss the evolution from perceptrons to modern transformer architectures. Be as thorough as possible."

for i in $(seq 1 20); do
    (
        curl -sf -o "$TMPDIR/slow_$i.json" \
            -X POST "${BASE_URL}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"${LONG_PROMPT}\"}], \"max_tokens\": 2048}" \
            --max-time 600 > /dev/null 2>&1 || true
        echo -n "."
    ) &
done

# While slow requests are running, sample pod metrics every 3s for 15s
echo "Sampling pod metrics while requests are in flight:"
echo ""
for sample in 1 2 3 4 5; do
    sleep 3
    echo "[t+$((sample * 3))s]"
    pod_metrics
    echo ""
done

wait
echo ""
echo "Slow requests done."
echo ""

echo "--- [3] Phase 2: Normal requests — observe routing distribution ---"
echo "Sending 20 requests and capturing EPP routing decisions..."
echo ""

for i in $(seq 1 20); do
    (
        curl -sf -o "$TMPDIR/req_$i.json" \
            -X POST "${BASE_URL}/v1/chat/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}], \"max_tokens\": 10}" \
            --max-time 60 > /dev/null 2>&1 || true
    ) &
    if (( i % 5 == 0 )); then wait; echo -n "."; fi
done
wait
echo ""
echo ""

echo "--- [4] Post-Test Pod Metrics ---"
pod_metrics
echo ""

echo "--- [5] EPP Routing Log (recent) ---"
# EPP logs show which pod was selected for each request
kubectl logs -l app=vllm-qwen-epp --tail=50 2>/dev/null \
    | grep -iE "(schedul|select|pick|route|endpoint|pod|addr)" \
    | tail -30 \
    || echo "No EPP routing logs found"
echo ""

echo "--- [6] Routing Distribution from EPP logs ---"
# Count how many times each pod IP/name appears in EPP routing decisions
echo "Pod endpoints:"
for pod in $PODS; do
    POD_IP=$(kubectl get pod $pod -o jsonpath='{.status.podIP}' 2>/dev/null || echo "unknown")
    echo "  $pod → $POD_IP"
done
echo ""
echo "EPP log routing counts (last 200 lines):"
EPP_LOG=$(kubectl logs -l app=vllm-qwen-epp --tail=200 2>/dev/null || echo "")
for pod in $PODS; do
    POD_IP=$(kubectl get pod $pod -o jsonpath='{.status.podIP}' 2>/dev/null || echo "unknown")
    COUNT=$(echo "$EPP_LOG" | grep -c "$POD_IP" 2>/dev/null || echo "0")
    printf "  %-50s ip=%-15s mentions=%s\n" "$pod" "$POD_IP" "$COUNT"
done
echo ""

echo "--- [7] EPP Decision Summary ---"
echo "What to look for:"
echo "  - During Phase 1 (slow requests): one pod's running/waiting count should increase"
echo "  - Phase 2 requests should prefer the LESS loaded pod"
echo "  - EPP logs should show 'scheduled'/'selected' with pod endpoint"
echo ""
echo "If pod counts in EPP log are uneven → EPP is routing based on load"
echo "If running/waiting were nonzero during sampling → KV cache building was attempted"
echo ""
