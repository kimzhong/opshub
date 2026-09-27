#!/bin/bash
# 分步部署 ops-mgmt 组件（每步单独跑，避开 280s 超时）
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
STEP="${1:-}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null 2>&1
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null 2>&1
helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null 2>&1
helm repo add bitnami-labs https://bitnami-labs.github.io/sealed-secrets --force-update >/dev/null 2>&1

case "$STEP" in
  sealed)
    echo "=== Sealed Secrets (GitHub Release YAML) ==="
    # helm repo 已 404，改用官方 release manifest
    kubectl --context $CTX apply -f \
      https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.40.0/sealed-secrets.yaml 2>&1 | tail -8
    echo "--- 等待就绪 ---"
    kubectl --context $CTX -n kube-system rollout status deploy/sealed-secrets --timeout=180s 2>&1 | tail -2
    kubectl --context $CTX get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
    ;;

  prom)
    echo "=== kube-prometheus-stack ==="
    helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
      -n monitoring --create-namespace \
      --set grafana.adminPassword=admin123 \
      --set grafana.service.type=NodePort \
      --set grafana.service.nodePort=30300 \
      --set prometheus.prometheusSpec.retention=12h \
      --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
      --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=5Gi \
      --timeout 240s 2>&1 | tail -8
    ;;

  prom-status)
    kubectl --context $CTX get pods -n monitoring
    ;;

  loki)
    echo "=== Loki ==="
    helm upgrade --install loki grafana/loki \
      -n monitoring --create-namespace \
      --set deploymentMode=SingleBinary \
      --set loki.auth_enabled=true \
      --set loki.persistence.enabled=true \
      --set loki.persistence.size=5Gi \
      --set gateway.enabled=true \
      --set gateway.replicas=1 \
      --wait --timeout 240s 2>&1 | tail -8
    ;;

  argocd)
    echo "=== ArgoCD ==="
    helm upgrade --install argocd argo/argo-cd \
      -n argocd --create-namespace \
      --set server.service.type=NodePort \
      --set server.service.nodePort=32409 \
      --set dex.enabled=false \
      --wait --timeout 240s 2>&1 | tail -8
    ;;

  status)
    echo "=== 全部组件状态 ==="
    echo "--- kube-system ---"
    kubectl --context $CTX get pods -n kube-system --no-headers 2>&1 | awk '{print $1,$2,$3}'
    echo "--- monitoring ---"
    kubectl --context $CTX get pods -n monitoring --no-headers 2>&1 | awk '{print $1,$2,$3}'
    echo "--- argocd ---"
    kubectl --context $CTX get pods -n argocd --no-headers 2>&1 | awk '{print $1,$2,$3}'
    echo
    echo "=== Helm releases ==="
    helm list -A --context $CTX 2>&1
    ;;

  *)
    echo "用法: $0 {sealed|prom|prom-status|loki|argocd|status}"
    ;;
esac
