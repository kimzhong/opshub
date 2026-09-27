#!/bin/bash
# 加长等待 + 失败保留现场，便于诊断
export PATH=/usr/local/bin:$PATH
NAME="$1"
DIR=/mnt/c/Users/kim/kind-env

echo "=== 清理 $NAME ==="
kind delete cluster --name "$NAME" 2>&1 | tail -1
docker ps -aq --filter "label=io.x-k8s.kind.cluster=$NAME" | xargs -r docker rm -fv 2>/dev/null
sleep 2

echo "=== 创建 $NAME (wait=180s, retain) ==="
kind create cluster --name "$NAME" \
  --image kindest/node:v1.27.3 \
  --config "$DIR/kind-prod.yaml" \
  --wait 180s --retain 2>&1 | tail -18

echo
echo "=== 立即验证 ==="
kubectl --context "kind-$NAME" get nodes 2>&1 | head -6
echo
echo "=== 集群列表 ==="
kind get clusters
