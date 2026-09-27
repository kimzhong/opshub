#!/bin/bash
export PATH=/usr/local/bin:$PATH
DIR=/mnt/c/Users/kim/kind-env

echo "=== 1. 删掉所有 kind 集群 ==="
for c in biz-prod-regiona biz-prod-regionb; do
  kind delete cluster --name "$c" 2>&1 | tail -1
done

echo
echo "=== 2. 清理残留容器/卷 ==="
docker ps -aq --filter 'label=io.x-k8s.kind.cluster' | xargs -r docker rm -f 2>&1 | tail -2
docker volume ls -q | xargs -r docker volume rm -f 2>&1 | tail -2
docker network ls --filter 'label=io.x-k8s.kind.cluster' -q | xargs -r docker network rm 2>&1 | tail -2

echo
echo "=== 3. 重启 Docker（重置 containerd 状态）==="
# WSL 内自建的 dockerd（非 Docker Desktop）
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart docker 2>&1 | tail -1 || echo "systemctl 重启失败，尝试直接杀进程"
fi
sleep 8
docker ps 2>&1 | head -3

echo
echo "=== 4. 清理 containerd 残留 ==="
sudo -n rm -rf /var/lib/containerd/io.containerd.metadata.v1.bolt/* 2>/dev/null || \
  rm -rf /var/lib/containerd/io.containerd.metadata.v1.bolt/* 2>/dev/null || true
docker system prune -f 2>&1 | tail -2

echo
echo "=== 5. 资源确认 ==="
docker info 2>&1 | grep -Ei 'containerd|storage driver|server version' | head -4
docker ps -a --format '{{.Names}}' | head -6
free -h | head -2
df -h / | tail -1
