#!/bin/bash
# 用法: create-one.sh <cluster-name>
export PATH=/usr/local/bin:$PATH
NAME="$1"
DIR=/mnt/c/Users/kim/kind-env

echo "=== 删除旧的 $NAME（如果有）==="
kind delete cluster --name "$NAME" 2>&1 | tail -1
kubectl config delete-context "kind-$NAME" 2>/dev/null
kubectl config delete-cluster "kind-$NAME" 2>/dev/null

echo "=== 创建 $NAME ==="
kind create cluster --name "$NAME" \
  --image kindest/node:v1.27.3 \
  --config "$DIR/kind-prod.yaml" \
  --wait 100s 2>&1 | tail -12

echo
echo "=== 验证 ==="
kubectl --context "kind-$NAME" get nodes 2>&1
echo
kind get clusters
