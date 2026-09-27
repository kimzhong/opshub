#!/bin/bash
export PATH=/usr/local/bin:$PATH
C=biz-prod-regiona-control-plane
echo "=== 容器 ==="
docker ps -a --filter "name=$C" --format '{{.Names}} | {{.Status}}'
echo
echo "=== kubelet ==="
docker exec "$C" systemctl is-active kubelet 2>&1
echo
echo "=== kubelet 最后错误 ==="
docker exec "$C" journalctl -u kubelet --no-pager -n 80 2>&1 | grep -Ei 'error|fail|panic' | tail -10
echo
echo "=== containerd ==="
docker exec "$C" systemctl is-active containerd 2>&1
echo "--- crictl info ---"
docker exec "$C" crictl info 2>&1 | head -4
echo "--- containerd 日志 ---"
docker exec "$C" journalctl -u containerd --no-pager -n 30 2>&1 | grep -Ei 'error|fail|panic' | tail -8
echo
echo "=== kubeadm init 日志（容器内）==="
docker exec "$C" ls -la /var/log/ 2>&1 | head -8
echo
echo "=== 节点内存 ==="
docker exec "$C" free -h 2>&1 | head -2
echo "=== 宿主负载 ==="
uptime
cat /proc/loadavg
