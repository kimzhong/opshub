#!/bin/bash
export PATH=/usr/local/bin:$PATH
DIR=/mnt/c/Users/kim/kind-env
kind delete cluster --name biz-prod-regiona 2>&1 | tail -1
echo "=== 详细创建（不截断）==="
kind create cluster --name biz-prod-regiona \
  --image kindest/node:v1.27.3 \
  --config "$DIR/kind-prod.yaml" \
  --wait 100s --retain \
  --verbosity 4 2>&1 | grep -Ei 'error|fail|panic|fatal|timeout|refused|timed out' | head -25
echo
echo "=== 容器状态 ==="
docker ps -a --filter 'label=io.x-k8s.kind.cluster=biz-prod-regiona' --format '{{.Names}} {{.Status}}'
