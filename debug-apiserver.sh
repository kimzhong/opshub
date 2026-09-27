#!/bin/bash
export PATH=/usr/local/bin:$PATH
C=biz-prod-regiona-control-plane
echo "=== 容器 ==="
docker ps -a --filter "name=$C" --format '{{.Names}} | {{.Status}}'
echo
echo "=== kubelet ==="
docker exec "$C" systemctl is-active kubelet 2>&1
echo
echo "=== 控制面容器状态 ==="
docker exec "$C" crictl ps -a 2>&1 | head -12
echo
echo "=== kubelet 错误日志 ==="
docker exec "$C" journalctl -u kubelet --no-pager -n 40 2>&1 | grep -Ei 'error|fail|panic|refused' | tail -15
echo
echo "=== apiserver 日志 ==="
docker exec "$C" crictl logs $(docker exec "$C" crictl ps -a --name kube-apiserver -q 2>/dev/null | head -1) 2>&1 | tail -15
echo
echo "=== 内存 ==="
docker exec "$C" free -h 2>&1 | head -3
echo
echo "=== 宿主内存 ==="
free -h | head -2
nproc
echo
echo "=== 磁盘 ==="
df -h / | tail -1
docker system df 2>&1 | head -4
