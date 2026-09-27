#!/bin/bash
# ops-mgmt 集群组件部署
set -e
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
K=kubectl
$K config use-context $CTX >/dev/null

echo "=== 添加 Helm 仓库 ==="
$K -n $CTX --context $CTX >/dev/null 2>&1 || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>&1 | tail -1
helm repo add argo https://argoproj.github.io/argo-helm 2>&1 | tail -1
helm repo add bitnami https://charts.bitnami.com/bitnami 2>&1 | tail -1
helm repo update 2>&1 | tail -2
echo "OK"

echo
echo "=== 1/4  Sealed Secrets ==="
helm upgrade --install sealed-secrets sealed-secrets \
  --repo https://bitnami-labs.github.io/sealed-secrets \
  --namespace kube-system --create-namespace \
  --set fullnameOverride=sealed-secrets \
  --set keyrenewperiod=0 \
  --wait --timeout 300s 2>&1 | tail -5

echo
echo "=== 2/4  kube-prometheus-stack ==="
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=admin123 \
  --set grafana.service.type=NodePort \
  --set grafana.service.nodePort=30300 \
  --set prometheus.prometheusSpec.retention=24h \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
  --set alertmanager.alertmanagerSpec.storage.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
  --set alertmanager.alertmanagerSpec.replicas=2 \
  --set prometheus.prometheusSpec.replicas=2 \
  --wait --timeout 600s 2>&1 | tail -8

echo
echo "=== 3/4  Loki ==="
helm upgrade --install loki grafana/loki \
  --namespace monitoring --create-namespace \
  --set deploymentMode=SimpleScalable \
  --set loki.auth_enabled=true \
  --set loki.storageConfig.filesystem.chunksDirectory=/tmp/loki/chunks \
  --set loki.storageConfig.filesystem.rulesDirectory=/tmp/loki/rules \
  --set loki.persistence.enabled=true \
  --set loki.persistence.size=10Gi \
  --set gateway.enabled=true \
  --set gateway.replicas=1 \
  --wait --timeout 600s 2>&1 | tail -8

echo
echo "=== 4/4  ArgoCD ==="
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=NodePort \
  --set server.service.nodePort=32409 \
  --set server.ingress.enabled=false \
  --set dex.enabled=false \
  --set redis.enabled=true \
  --set controller.args.application.instanceLabelKey=argocd.argoproj.io/instance \
  --wait --timeout 600s 2>&1 | tail -8

echo
echo "=== 部署完成，Pod 状态 ==="
$K --context $CTX get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
$K --context $CTX get pods -n monitoring --no-headers | awk '{print $1,$2,$3,$4}' | head -20
$K --context $CTX get pods -n argocd --no-headers | awk '{print $1,$2,$3,$4}'
