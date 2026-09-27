#!/bin/bash
# 持久化 inotify 配置 + 清理 + 重建两个生产集群
export PATH=/usr/local/bin:$PATH
DIR=/mnt/c/Users/kim/kind-env

echo "=== 1. 持久化 sysctl ==="
sudo -n sh -c "grep -q 'max_user_instances' /etc/sysctl.conf 2>/dev/null || echo 'fs.inotify.max_user_instances=8192' >> /etc/sysctl.conf" 2>/dev/null \
  && echo "  已写入 /etc/sysctl.conf" || echo "  跳过（无 sudo 权限，会话内已生效）"

echo
echo "=== 2. 清理失败的 regiona ==="
kind delete cluster --name biz-prod-regiona 2>&1 | tail -1
docker ps -aq --filter "label=io.x-k8s.kind.cluster=biz-prod-regiona" | xargs -r docker rm -fv 2>/dev/null
sleep 3
echo "  剩余容器: $(docker ps -q | wc -l)"

echo
echo "=== 3. 验证限制已生效 ==="
cat /proc/sys/fs/inotify/max_user_instances

echo
echo "=== 4. 创建 biz-prod-regiona ==="
kind create cluster --name biz-prod-regiona \
  --image kindest/node:v1.27.3 \
  --config "$DIR/kind-prod.yaml" --wait 120s 2>&1 | tail -10

echo
echo "=== 5. 验证 ==="
kubectl --context kind-biz-prod-regiona get nodes 2>&1
