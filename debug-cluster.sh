#!/bin/bash
export PATH=/usr/local/bin:$PATH
echo "=== kubectl 直连错误详情 ==="
kubectl --context kind-ops-mgmt get nodes 2>&1 | head -20
echo
echo "=== kubeconfig 内容 ==="
kubectl config view --context kind-ops-mgmt 2>&1 | head -20
echo
echo "=== 容器内 kubelet 状态 ==="
docker exec ops-mgmt-control-plane systemctl is-active kubelet 2>&1
docker exec ops-mgmt-control-plane crictl ps 2>&1 | head -10
echo
echo "=== 控制面日志尾部 ==="
docker exec ops-mgmt-control-plane journalctl -u kubelet --no-pager -n 15 2>&1 | tail -15
