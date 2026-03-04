# AI Gateway with vLLM CPU

Understanding Gateway API Inference Extension's EPP (Endpoint Picker) smart routing behavior using vLLM CPU metrics.

> [!IMPORTANT]
> **x86_64 required.** vLLM pre-built CPU images only support x86_64. ARM64 (Mac M1/M2, AWS Graviton) is not supported.

## Purpose

This lab demonstrates how EPP routes requests based on real-time vLLM metrics:
- **Queue-based routing**: Direct requests to pods with fewer queued requests
- **KV-cache routing**: Balance load based on cache utilization
- **Prefix-cache routing**: Optimize for cache hits

> [!NOTE]
> This is for learning EPP routing behavior, not production performance testing.

## Components

| Component | Image |
|-----------|-------|
| vLLM CPU | `public.ecr.aws/q9t5s3a7/vllm-cpu-release-repo:v0.9.0.1` |
| EPP | `registry.k8s.io/gateway-api-inference-extension/epp:v1.3.1` |
| Envoy Gateway | `v1.6.3` |
| Monitoring | `kube-prometheus-stack` |

## Requirements

- **Architecture**: x86_64 with AVX512 support
- **RAM**: 8 GiB (2 replicas) or 4 GiB (1 replica)
- **Storage**: 10 GB
- **OS**: Ubuntu 22.04+ or Amazon Linux 2023

> [!IMPORTANT]
> vLLM CPU pre-built images require AVX512. **AWS c6i/m6i** (Intel Ice Lake) or **GCP n2-standard** (Intel Cascade Lake+) required.
>
> DigitalOcean and other providers may not expose AVX512 to VMs, causing `Illegal instruction` error.

> [!TIP]
> Recommended: **AWS c6i.large** (2 vCPU, 4 GiB) ~$0.085/hr, or **c6i.xlarge** (4 vCPU, 8 GiB) ~$0.17/hr

## Quick Start

```bash
sudo apt update && sudo apt install -y curl wget git

git clone https://github.com/pyy0715/envoy-llm-gateway-lab.git
cd envoy-llm-gateway-lab
chmod +x scripts/*.sh test/*.sh

./scripts/01-setup-cluster.sh          # k3s + Helm + Envoy Gateway
./scripts/02-install-monitoring.sh     # kube-prometheus-stack
./scripts/03-install-ai-gateway.sh     # AI Gateway CRDs
./scripts/04-deploy-all.sh             # vLLM + EPP + Gateway
```

## Test

```bash
# API test
./test/test-api.sh

# Load test with EPP routing
./test/load-test.sh 30 10  # 30 requests, 10 concurrent
```

## API Access

```bash
GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}')

# List models
curl http://$GATEWAY_IP/v1/models

# Chat completion
curl -X POST http://$GATEWAY_IP/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen3-0.6B", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'
```

## Monitoring

```bash
# Get Grafana address
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# Access: http://<EXTERNAL-IP>:80 (admin/admin)
```

### Key Metrics

```promql
vllm:gpu_cache_usage_perc   # KV-Cache utilization
vllm:num_requests_waiting   # Queued requests
vllm:num_requests_running   # Running requests
```

## EPP Smart Routing

EPP routes requests based on real-time metrics:

| Scorer | Description |
|--------|-------------|
| `queue-scorer` | Prefer pods with fewer queued requests |
| `kv-cache-utilization-scorer` | Prefer pods with lower KV-cache usage |
| `prefix-cache-scorer` | Prefer pods with prefix cache hits |

### Verify Routing

```bash
# EPP logs
kubectl logs -l app.kubernetes.io/name=epp --tail=100

# Pod metrics
for pod in $(kubectl get pods -l app=vllm-qwen -o jsonpath='{.items[*].metadata.name}'); do
  echo "--- $pod ---"
  kubectl exec $pod -- curl -s localhost:8000/metrics | grep "^vllm:"
done
```

## Structure

```
k8s/
├── ai-gateway/           # Gateway, HTTPRoute
├── backend/              # vLLM deployment
├── inference-pool/       # EPP + InferencePool
└── monitoring/           # Grafana dashboards
scripts/
├── 01-setup-cluster.sh
├── 02-install-monitoring.sh
├── 03-install-ai-gateway.sh
├── 04-deploy-all.sh
└── 99-cleanup.sh
test/
├── test-api.sh
└── load-test.sh
```

## Cleanup

```bash
./scripts/99-cleanup.sh

# Uninstall k3s
/usr/local/bin/k3s-uninstall.sh
```

## References

- [Gateway API Inference Extension](https://github.com/kubernetes-sigs/gateway-api-inference-extension)
- [Envoy AI Gateway](https://github.com/envoyproxy/ai-gateway)
- [vLLM Documentation](https://docs.vllm.ai/)
