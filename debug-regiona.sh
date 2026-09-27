#!/bin/bash
export PATH=/usr/local/bin:$PATH
C=biz-prod-regiona-control-plane
echo "=== kubelet 状态 ==="
docker exec "$C" systemctl is-active kubelet 2>&1
echo
echo "=== kubelet 关键错误 ==="
docker exec "$C" journalctl -u kubelet --no-pager -n 60 2>&1 | grep -Ei 'error|fail|panic' | tail -12
echo
echo "=== containerd 状态 ==="
docker exec "$C" systemctl is-active containerd 2>&1
docker exec "$C" crictl info 2>&1 | head -5
echo
echo "=== containerd 日志 ==="
docker exec "$C" journalctl -u containerd --no-pager -n 25 2>&1 | tail -12
echo
echo "=== 磁盘（宿主）==="
df -h / /var/lib/docker 2>/dev/null | tail -3
echo
echo "=== inode ==="
df -i / | tail -1
