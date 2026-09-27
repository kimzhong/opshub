#!/bin/bash
export PATH=/usr/local/bin:$PATH
DIR=/mnt/c/Users/kim/kind-env

echo "=== 清理 regiona / regionb ==="
kind delete cluster --name biz-prod-regiona 2>&1 | tail -2
kind delete cluster --name biz-prod-regionb 2>&1 | tail -2
kubectl config delete-context kind-biz-prod-regiona 2>/dev/null
kubectl config delete-context kind-biz-prod-regionb 2>/dev/null
kubectl config delete-cluster kind-biz-prod-regiona 2>/dev/null
kubectl config delete-cluster kind-biz-prod-regionb 2>/dev/null

echo
echo "=== 重建 biz-prod-regiona ==="
kind create cluster --name biz-prod-regiona \
  --image kindest/node:v1.27.3 \
  --config "$DIR/kind-prod.yaml" --wait 120s 2>&1 | tail -8

echo
echo "=== 重建 biz-prod-regionb ==="
kind create cluster --name biz-prod-regionb \
  --image kindest/node:v1.27.3 \
  --config "$DIR/kind-prod.yaml" --wait 120s 2>&1 | tail -8

echo
echo "=== 结果 ==="
kind get clusters
kubectl config get-contexts
