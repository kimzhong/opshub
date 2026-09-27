#!/bin/bash
# 配置国内 Helm 镜像源（chart 托管在 GitHub，直连会断）
export PATH=/usr/local/bin:$PATH

# 阿里云 helm charts 镜像
for R in "prometheus-community|https://prometheus-community.github.io/helm-charts" \
         "argo|https://argoproj.github.io/argo-helm" \
         "grafana|https://grafana.github.io/helm-charts" \
         "bitnami-labs|https://bitnami-labs.github.io/sealed-secrets"; do
  NAME="${R%%|*}"; URL="${R##*|}"
  helm repo add "$NAME" "$URL" --force-update >/dev/null 2>&1
done

echo "=== 已配置仓库 ==="
helm repo list 2>&1

echo
echo "=== 尝试预拉取 chart（多次重试）==="
DEST=/tmp/charts
mkdir -p "$DEST"

pull_chart() {
  local repo="$1" chart="$2" out="$3"
  for i in 1 2 3; do
    echo "  [$i/3] helm pull $repo/$chart"
    if helm pull "$repo/$chart" -d "$DEST" --version "$4" 2>/dev/null; then
      [ -f "$DEST/$out" ] && { echo "    ✓ $out"; return 0; }
    fi
    rm -f "$DEST/$out"
    sleep 3
  done
  return 1
}

pull_chart prometheus-community kube-prometheus-stack kube-prometheus-stack.tgz 91.7.0
pull_chart argo argo-cd argo-cd.tgz 9.3.1
pull_chart grafana loki loki.tgz 6.44.0

echo
echo "=== 本地 chart ==="
ls -la "$DEST"
