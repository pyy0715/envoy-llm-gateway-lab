# Gateway API Inference Extension Lab

Gateway API Inference Extension의 스마트 라우팅을 테스트하는 환경입니다.

## 구성

| 컴포넌트 | 이미지 | 모델 |
|---------|--------|------|
| Backend (Qwen) | `llm-d-inference-sim` | Qwen3-0.6B |
| Backend (SmolLM) | `llm-d-inference-sim` | SmolLM2-1.7B |
| EPP | `epp:v1.3.1` | - |
| Envoy Gateway | - | - |

## 라우팅 로직

EPP(Endpoint Picker)가 다음 메트릭 기반으로 최적 Pod 선택:

| 메트릭 | 설명 |
|--------|------|
| KV-cache 사용률 | `vllm:gpu_cache_usage_perc` |
| Queue depth | `vllm:num_requests_waiting` |
| Prefix cache | 요청 프리픽스 매칭 |

## 빠른 시작

```bash
./scripts/01-setup-cluster.sh
./scripts/02-install-gateway-api.sh
./scripts/03-install-envoy-gateway.sh
./scripts/04-install-ai-gateway.sh
./scripts/05-deploy-all.sh --monitoring
```

## 테스트

```bash
# API 테스트
./test/test-api.sh

# 로드 테스트
./test/load-test.sh

# EPP 라우팅 검증
./test/verify-epp-routing.sh check-all
```

## 수동 테스트

```bash
# 포트 포워딩
kubectl port-forward -n default service/ai-gateway 8081:80 &

# API 호출
curl -X POST http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen3-0.6B",
    "messages": [{"role": "user", "content": "Hello!"}],
    "max_tokens": 50
  }'
```

## 모니터링

```bash
# Prometheus
kubectl port-forward svc/prometheus 9090:9090

# Grafana (admin/admin)
kubectl port-forward svc/grafana 3000:3000
```

### Prometheus 쿼리

```promql
# KV-Cache 사용률
vllm:gpu_cache_usage_perc

# 대기 중인 요청
vllm:num_requests_waiting

# 실행 중인 요청
vllm:num_requests_running
```

## 디렉토리 구조

```
k8s/
├── backend/
│   ├── vllm-qwen.yaml       # 시뮬레이터
│   └── vllm-smol.yaml       # 실제 vLLM
├── inference-pool/
│   ├── pool-qwen/           # EPP + InferencePool
│   └── pool-smol/
├── ai-gateway/
│   ├── gateway.yaml
│   └── ai-gateway-route.yaml
└── monitoring/
    ├── prometheus.yaml
    ├── grafana.yaml
    └── dashboards/
```

## 정리

```bash
./scripts/99-cleanup.sh
```

## 참고 자료

- [Gateway API Inference Extension](https://github.com/kubernetes-sigs/gateway-api-inference-extension)
- [Envoy AI Gateway](https://github.com/envoyproxy/ai-gateway)
- [vLLM Metrics](https://docs.vllm.ai/en/latest/serving/metrics.html)
