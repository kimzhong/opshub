#!/bin/bash
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
POD=$(kubectl --context $CTX get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}')

echo "=== 工具可用性 ==="
kubectl --context $CTX exec "$POD" -n kube-system -- sh -c 'which wget curl nc 2>/dev/null; echo "---"; cat /etc/resolv.conf' 2>&1 | head -10

echo
echo "=== DNS 解析测试 ==="
kubectl --context $CTX exec "$POD" -n kube-system -- sh -c 'nslookup registry-1.docker.io 2>&1 | head -6' 2>&1

echo
echo "=== 直接 ping 宿主网关 ==="
GW=$(docker inspect ops-mgmt-control-plane -f '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' 2>/dev/null)
echo "gateway=$GW"
kubectl --context $CTX exec "$POD" -n kube-system -- sh -c "timeout 5 nc -zv $GW 443 2>&1 || echo nc-fail" 2>&1 | head -3

echo
echo "=== 节点内直连测试（不是 pod）==="
docker exec ops-mgmt-control-plane sh -c 'timeout 8 curl -sS -o /dev/null -w "docker.io: %{http_code}\n" https://registry-1.docker.io/v2/ 2>&1' 2>&1
docker exec ops-mgmt-control-plane sh -c 'timeout 8 curl -sS -o /dev/null -w "daocloud: %{http_code}\n" https://docker.m.daocloud.io/v2/ 2>&1' 2>&1
