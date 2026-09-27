#!/bin/bash
export PATH=/usr/local/bin:$PATH
DIR=/mnt/c/Users/kim/kind-env
LOG=/tmp/create-prod.log

: > "$LOG"

{
  echo "=== 清理残留 ==="
  kind delete cluster --name biz-prod-regiona 2>&1 | tail -1
  kind delete cluster --name biz-prod-regionb 2>&1 | tail -1
  kubectl config delete-context kind-biz-prod-regiona 2>/dev/null
  kubectl config delete-context kind-biz-prod-regionb 2>/dev/null
  kubectl config delete-cluster kind-biz-prod-regiona 2>/dev/null
  kubectl config delete-cluster kind-biz-prod-regionb 2>/dev/null

  echo "=== 创建 regiona $(date +%T) ==="
  kind create cluster --name biz-prod-regiona \
    --image kindest/node:v1.27.3 \
    --config "$DIR/kind-prod.yaml" --wait 150s 2>&1 | tail -12

  echo "=== 创建 regionb $(date +%T) ==="
  kind create cluster --name biz-prod-regionb \
    --image kindest/node:v1.27.3 \
    --config "$DIR/kind-prod.yaml" --wait 150s 2>&1 | tail -12

  echo "=== 完成 $(date +%T) ==="
  kind get clusters
  kubectl config get-contexts
  echo "=== DONE ==="
} >> "$LOG" 2>&1
