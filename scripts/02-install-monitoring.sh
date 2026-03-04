#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Installing kube-prometheus-stack ==="

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Add Prometheus repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create additional scrape configs for vLLM/EPP
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: kube-prometheus-stack-additional-scrape-config
  namespace: monitoring
type: Opaque
stringData:
  additional-scrape-configs.yaml: |
    - job_name: 'vllm-metrics'
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          regex: vllm-qwen
          action: keep
        - source_labels: [__meta_kubernetes_pod_ip]
          replacement: ${1}:8000
          target_label: __address__
        - source_labels: [__meta_kubernetes_pod_name]
          target_label: pod
      metrics_path: /metrics

    - job_name: 'epp-metrics'
      kubernetes_sd_configs:
        - role: pod
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_app]
          regex: vllm-qwen-epp
          action: keep
        - source_labels: [__meta_kubernetes_pod_ip]
          replacement: ${1}:9090
          target_label: __address__
        - source_labels: [__meta_kubernetes_pod_name]
          target_label: pod

    - job_name: 'envoy-proxy'
      kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: [envoy-gateway-system]
      relabel_configs:
        - source_labels: [__meta_kubernetes_pod_label_gateway_envoyproxy_io_owning_gateway_namespace]
          action: keep
        - source_labels: [__meta_kubernetes_pod_ip]
          replacement: ${1}:19001
          target_label: __address__
EOF

# Install kube-prometheus-stack
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.additionalScrapeConfigsSecret.name=kube-prometheus-stack-additional-scrape-config \
  --set prometheus.prometheusSpec.additionalScrapeConfigsSecret.key=additional-scrape-configs.yaml \
  --set grafana.adminPassword=admin \
  --set grafana.service.type=LoadBalancer \
  --set grafana.service.port=3000 \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.label=grafana_dashboard \
  --timeout 10m

echo ""
echo "Waiting for pods..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s

# Deploy custom dashboards
echo ""
echo "Deploying vLLM/EPP dashboards..."
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/vllm-dashboard.yaml"

# Restart Grafana to load dashboards
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring
kubectl wait --for=condition=Available deployment/kube-prometheus-stack-grafana -n monitoring --timeout=120s

echo ""
echo "=== Monitoring Installed ==="
echo ""
GRAFANA_IP=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$GRAFANA_IP" ]; then
    GRAFANA_IP=$(kubectl get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.spec.clusterIP}')
    echo "Grafana Access:"
    echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
else
    echo "Grafana: http://${GRAFANA_IP}"
fi
echo ""
echo "Login: admin / admin"
echo "Dashboard: vLLM Performance Statistics (auto-loaded)"
echo ""
echo "Next: ./scripts/03-install-ai-gateway.sh"
