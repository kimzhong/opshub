#!/bin/bash
export PATH=/usr/local/bin:$PATH
echo "=== ops-mgmt 节点 ==="
kubectl --context kind-ops-mgmt get nodes
echo
echo "=== 容器 ==="
docker ps --format '{{.Names}}' | grep ops-mgmt
echo
echo "=== 补齐 worker3 ==="
docker start ops-mgmt-worker3 2>&1 || echo "(worker3 容器不存在，需要重建集群)"
sleep 10
kubectl --context kind-ops-mgmt get nodes 2>&1
