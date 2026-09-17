#!/bin/bash
# 自动化部署总入口
# 一次性部署：监控栈 + IAM + Harbor + Chaos + Velero + ArgoCD Apps
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo " OpsHub 全栈部署"
echo "========================================"

# 1. kind 集群
echo "[1/8] 创建多集群..."
bash "$SCRIPT_DIR/../kind/create-clusters.ps1" || true
bash "$SCRIPT_DIR/../kind/create-clusters.sh" || {
  echo "  PowerShell 不可用，使用 bash 替代"
  exit 1
}

# 2. ArgoCD
echo "[2/8] 部署 ArgoCD..."
kubectl config use-context ops-mgmt
kubectl apply -f "$ROOT_DIR/argocd/install-argocd.yaml" -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# 3. 注册业务集群到 ArgoCD
echo "[3/8] 注册业务集群..."
argocd cluster add biz-prod-regiona --name biz-prod-regiona
argocd cluster add biz-prod-regionb --name biz-prod-regionb

# 4. 部署 IAM
echo "[4/8] 部署 Keycloak + Dex..."
kubectl apply -f "$ROOT_DIR/iam/keycloak/namespace.yaml"
helm install keycloak bitnami/keycloak \
  --namespace keycloak \
  --values "$ROOT_DIR/iam/keycloak/values.yaml"
helm install dex dex/dex \
  --namespace dex \
  --values "$ROOT_DIR/iam/dex/values.yaml"

# 5. 部署监控栈
echo "[5/8] 部署监控栈..."
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values "$ROOT_DIR/observability/prometheus/kube-prometheus-stack-values.yaml"
helm install loki grafana/loki \
  --namespace monitoring \
  --values "$ROOT_DIR/observability/loki/values.yaml"
helm install tempo grafana/tempo \
  --namespace monitoring \
  --values "$ROOT_DIR/observability/tempo/values.yaml"
helm install mimir grafana/mimir-distributed \
  --namespace monitoring \
  --values "$ROOT_DIR/observability/mimir/values.yaml"
kubectl apply -f "$ROOT_DIR/observability/otel-collector/config.yaml" -n monitoring
kubectl apply -f "$ROOT_DIR/observability/prometheus/slo-rules.yaml" -n monitoring

# 6. 部署 Harbor
echo "[6/8] 部署 Harbor..."
helm install harbor harbor/harbor \
  --namespace harbor \
  --values "$ROOT_DIR/registry/harbor/values.yaml"

# 7. 部署 Chaos Mesh + Velero
echo "[7/8] 部署 Chaos Mesh + Velero..."
helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh --create-namespace \
  --values "$ROOT_DIR/chaos/chaos-mesh/values.yaml"
helm install velero vmware-tanzu/velero \
  --namespace velero --create-namespace \
  --values "$ROOT_DIR/backup/velero/values.yaml"
kubectl apply -f "$ROOT_DIR/backup/velero/schedules.yaml" -n velero

# 8. 部署 Kyverno
echo "[8/8] 部署 Kyverno..."
helm install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace
kubectl apply -f "$ROOT_DIR/registry/kyverno/"

# 9. ArgoCD App of Apps
echo "[9/9] 部署 App of Apps..."
kubectl apply -f "$ROOT_DIR/argocd/projects/"
kubectl apply -f "$ROOT_DIR/argocd/apps/"

echo ""
echo "========================================"
echo " [OK] OpsHub 全栈部署完成"
echo "========================================"
echo ""
echo "访问入口："
echo "  ArgoCD:    https://localhost:30443 (admin / see-secret)"
echo "  Grafana:   http://localhost:30080 (admin / changeme)"
echo "  Prometheus: http://localhost:30080/prometheus (via Grafana)"
echo "  Keycloak:  https://sso.ops.internal (admin / see-secret)"
echo "  Harbor:    https://harbor.ops.internal"
echo "  Chaos:     http://chaos.ops.internal"
echo ""
echo "验证："
echo "  kubectl get applications -n argocd"
echo "  kubectl get pods -A"
