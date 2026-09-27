#!/bin/bash
export PATH=/usr/local/bin:$PATH
echo "=== 集群列表 ==="
kind get clusters 2>&1
echo
echo "=== 容器 ==="
docker ps --format '{{.Names}}  {{.Status}}' 2>&1
echo
echo "=== kubeconfig contexts ==="
kubectl config get-contexts 2>&1 | head -10
echo
echo "=== 节点状态 ==="
for c in kind-ops-mgmt kind-biz-prod-regiona kind-biz-prod-regionb; do
  echo "--- $c ---"
  kubectl --context "$c" get nodes 2>&1 | head -6
done
