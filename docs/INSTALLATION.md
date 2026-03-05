# Installation

> Based on the [vLLM Semantic Router official documentation](https://vllm-semantic-router.com/docs/installation/k8s/ai-gateway).

## Prerequisites

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [kind](https://kind.sigs.k8s.io/) (optional, for local clusters)

## Step 1: Create Kind Cluster (Optional)

Skip this step if you already have a Kubernetes cluster.

```bash
kind create cluster --name semantic-router-cluster
kubectl wait --for=condition=Ready nodes --all --timeout=300s
```

## Step 2: Deploy vLLM Semantic Router

```bash
helm install semantic-router oci://ghcr.io/vllm-project/charts/semantic-router \
  --version v0.0.0-latest \
  --namespace vllm-semantic-router-system \
  --create-namespace \
  -f https://raw.githubusercontent.com/vllm-project/semantic-router/refs/heads/main/deploy/kubernetes/ai-gateway/semantic-router-values/values.yaml

kubectl wait --for=condition=Available deployment/semantic-router \
  -n vllm-semantic-router-system --timeout=600s
```

Verify:

```bash
kubectl get pods -n vllm-semantic-router-system
```

## Step 3: Install Envoy Gateway

```bash
helm upgrade -i eg oci://docker.io/envoyproxy/gateway-helm \
  --version v0.0.0-latest \
  --namespace envoy-gateway-system \
  --create-namespace \
  -f https://raw.githubusercontent.com/envoyproxy/ai-gateway/main/manifests/envoy-gateway-values.yaml

kubectl wait --timeout=2m -n envoy-gateway-system \
  deployment/envoy-gateway --for=condition=Available
```

## Step 4: Install Envoy AI Gateway

```bash
# Controller
helm upgrade -i aieg oci://docker.io/envoyproxy/ai-gateway-helm \
  --version v0.0.0-latest \
  --namespace envoy-ai-gateway-system \
  --create-namespace

# CRDs
helm upgrade -i aieg-crd oci://docker.io/envoyproxy/ai-gateway-crds-helm \
  --version v0.0.0-latest \
  --namespace envoy-ai-gateway-system

kubectl wait --timeout=300s -n envoy-ai-gateway-system \
  deployment/ai-gateway-controller --for=condition=Available
```

## Step 5: Deploy Demo LLM

```bash
kubectl apply -f https://raw.githubusercontent.com/vllm-project/semantic-router/refs/heads/main/deploy/kubernetes/ai-gateway/aigw-resources/base-model.yaml
```

## Step 6: Create Gateway API Resources

```bash
kubectl apply -f https://raw.githubusercontent.com/vllm-project/semantic-router/refs/heads/main/deploy/kubernetes/ai-gateway/aigw-resources/gwapi-resources.yaml
```

## Verify

### Port Forwarding

```bash
export ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=semantic-router \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward -n envoy-gateway-system svc/$ENVOY_SERVICE 8080:80
```

### Send a Test Request

```bash
curl -i -X POST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "MoM",
    "messages": [
      {"role": "user", "content": "What is the derivative of f(x) = x^3?"}
    ]
  }'
```

## Cleanup

```bash
# Remove Gateway API resources and Demo LLM
kubectl delete -f https://raw.githubusercontent.com/vllm-project/semantic-router/refs/heads/main/deploy/kubernetes/ai-gateway/aigw-resources/gwapi-resources.yaml
kubectl delete -f https://raw.githubusercontent.com/vllm-project/semantic-router/refs/heads/main/deploy/kubernetes/ai-gateway/aigw-resources/base-model.yaml

# Remove Helm releases
helm uninstall semantic-router -n vllm-semantic-router-system
helm uninstall aieg -n envoy-ai-gateway-system
helm uninstall aieg-crd -n envoy-ai-gateway-system
helm uninstall eg -n envoy-gateway-system

# Delete kind cluster (if used)
kind delete cluster --name semantic-router-cluster
```

## Troubleshooting

### Gateway not accessible

```bash
kubectl get gateway semantic-router -n default
kubectl get svc -n envoy-gateway-system
```

### AI Gateway controller not ready

```bash
kubectl logs -n envoy-ai-gateway-system deployment/ai-gateway-controller
kubectl get deployment -n envoy-ai-gateway-system
```

### Semantic router not responding

```bash
kubectl get pods -n vllm-semantic-router-system
kubectl logs -n vllm-semantic-router-system deployment/semantic-router
```
