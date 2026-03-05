# AI Gateway with vLLM GPU

Understanding Gateway API Inference Extension's EPP (Endpoint Picker) smart routing behavior using vLLM GPU metrics.

> [!IMPORTANT]
> **NVIDIA GPU required.** This lab requires a GPU node with `nvidia-container-toolkit` installed.

## Purpose

This lab demonstrates how EPP routes requests based on real-time vLLM metrics:
- **Queue-based routing**: Direct requests to pods with fewer queued requests
- **KV-cache routing**: Balance load based on GPU KV cache utilization
- **Prefix-cache routing**: Optimize for cache hits

> [!NOTE]
> This is for learning EPP routing behavior, not production performance testing.

## Components

| Component | Image / Version |
|-----------|-----------------|
| vLLM GPU | `vllm/vllm-openai:v0.9.0` |
| EPP | `registry.k8s.io/gateway-api-inference-extension/epp:v1.3.1` |
| Envoy Gateway | `v1.6.3` |
| AI Gateway | `v0.5.0` |
| Monitoring | `kube-prometheus-stack` |

## Requirements

- **GPU**: NVIDIA GPU with `nvidia-container-toolkit` installed
- **RAM**: 16 GiB+ recommended
- **Storage**: 20 GB
- **OS**: Ubuntu 22.04+ or similar Linux with NVIDIA drivers

> [!TIP]
> **DigitalOcean GPU Droplet** or any single-node GPU instance with k3s works well for this lab.
> The vLLM deployment requests `nvidia.com/gpu: 1` per replica (2 replicas by default).

## Quick Start

```bash
sudo apt update && sudo apt install -y curl wget git

git clone https://github.com/pyy0715/envoy-llm-gateway-lab.git
cd envoy-llm-gateway-lab

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

./scripts/01-setup-cluster.sh          # k3s + Helm + Envoy Gateway
./scripts/02-install-monitoring.sh     # kube-prometheus-stack
./scripts/03-install-ai-gateway.sh     # AI Gateway CRDs
./scripts/04-deploy-all.sh             # vLLM GPU + EPP + Gateway
```

## Test

```bash
# EPP smart routing verification (requires 2 vLLM replicas)
./test/smart-routing-test.sh
```

## API Access

```bash
GATEWAY_IP=$(kubectl get gateway ai-gateway -o jsonpath='{.status.addresses[0].value}')

# List models
curl http://$GATEWAY_IP:8888/v1/models

# Chat completion
curl -X POST http://$GATEWAY_IP:8888/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "Qwen/Qwen3-0.6B", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'
```

## Monitoring

```bash
# Get Grafana address
kubectl get svc -n monitoring kube-prometheus-stack-grafana

# Access: http://<EXTERNAL-IP>:3000 (admin/admin)
# Dashboard: "EPP Smart Routing"
```

### Key Metrics (Success Criteria 3)

```promql
vllm:gpu_cache_usage_perc                        # GPU KV-Cache utilization (per pod)
inference_pool_average_kv_cache_utilization       # EPP pool-level KV cache avg
inference_pool_average_queue_size                 # EPP pool-level queue avg
```

부하 테스트 중 위 3개 메트릭이 비제로(non-zero)로 표시되면 성공.

## EPP Smart Routing

EPP routes requests based on real-time metrics:

| Scorer | Description |
|--------|-------------|
| `queue-scorer` | Prefer pods with fewer queued requests |
| `kv-cache-utilization-scorer` | Prefer pods with lower GPU KV-cache usage |
| `prefix-cache-scorer` | Prefer pods with prefix cache hits (requires `--enable-prefix-caching`) |

### Verify Routing

```bash
# EPP logs — look for scheduling decisions
kubectl logs -l app=vllm-qwen-epp --tail=100

# Run the smart routing test to see EPP in action
./test/smart-routing-test.sh
```

## Structure

```
k8s/
├── ai-gateway/           # GatewayClass, Gateway, EnvoyProxy, BackendTrafficPolicy
│   ├── gateway.yaml
│   └── ai-gateway-route.yaml
├── backend/              # vLLM GPU deployment + headless Service
│   └── vllm-qwen.yaml
├── inference-pool/       # EPP + InferencePool
│   └── qwen/
│       ├── epp-config.yaml
│       ├── epp-deployment.yaml
│       ├── epp-rbac.yaml
│       ├── inference-objective.yaml
│       └── inference-pool.yaml
└── monitoring/           # Prometheus scrape config + Grafana dashboard
    ├── prometheus-scrape-config.yaml
    └── epp-routing-dashboard.yaml
scripts/
├── 01-setup-cluster.sh       # k3s + Helm + Envoy Gateway
├── 02-install-monitoring.sh  # kube-prometheus-stack + dashboards
├── 03-install-ai-gateway.sh  # Inference Extension CRDs + AI Gateway
├── 04-deploy-all.sh          # vLLM + EPP + Gateway resources
└── 99-cleanup.sh
test/
└── smart-routing-test.sh     # EPP smart routing verification
docs/
└── troubleshooting.md
```

## Cleanup

```bash
./scripts/99-cleanup.sh

# Uninstall k3s completely
/usr/local/bin/k3s-uninstall.sh
```

## References

- [Gateway API Inference Extension](https://github.com/kubernetes-sigs/gateway-api-inference-extension)
- [Envoy AI Gateway](https://github.com/envoyproxy/ai-gateway)
- [vLLM Documentation](https://docs.vllm.ai/)