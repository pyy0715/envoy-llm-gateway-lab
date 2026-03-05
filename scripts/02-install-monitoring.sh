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
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/prometheus-scrape-config.yaml"

# Install kube-prometheus-stack
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.additionalScrapeConfigsSecret.enabled=true \
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
echo "Deploying vLLM/Inference Extension dashboards..."
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/vllm-dashboard.yaml"
kubectl apply -f "$PROJECT_DIR/k8s/monitoring/inference-extension-dashboard.yaml"

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
echo "Dashboards:"
echo "  - vLLM Performance Statistics"
echo "  - Inference Extension - EPP Metrics"
echo ""
echo "Next: ./scripts/03-install-ai-gateway.sh"
