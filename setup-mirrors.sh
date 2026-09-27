#!/bin/bash
# 给所有 kind 节点的 containerd 配置 Docker Hub 镜像加速
export PATH=/usr/local/bin:$PATH

MIRRORS='
mirrors = {
  "docker.io" = {
    endpoint = [
      "https://docker.m.daocloud.io",
      "https://docker.1ms.run",
      "https://docker.xuanyuan.me"
    ]
  }
  "registry-1.docker.io" = {
    endpoint = [
      "https://docker.m.daocloud.io"
    ]
  }
  "quay.io" = {
    endpoint = [
      "https://quay.m.daocloud.io"
    ]
  }
  "gcr.io" = {
    endpoint = [
      "https://gcr.m.daocloud.io"
    ]
  }
  "k8s.gcr.io" = {
    endpoint = [
      "https://k8s.gcr.io"
    ]
  }
  "ghcr.io" = {
    endpoint = [
      "https://ghcr.m.daocloud.io"
    ]
  }
}
'

for C in $(docker ps --filter 'label=io.x-k8s.kind.cluster' --format '{{.Names}}'); do
  echo "--- $C ---"
  docker exec "$C" sh -c "cp /etc/containerd/config.toml /etc/containerd/config.toml.bak 2>/dev/null; true"

  # 用 python 做精确插入（config.toml 是 TOML，容器里没有 toml 工具）
  docker exec -i "$C" python3 - "$MIRRORS" <<'PYEOF' 2>&1 | tail -2
import sys, re
mirrors = sys.argv[1]
p = "/etc/containerd/config.toml"
src = open(p).read()
# 移除已有的 mirrors 段
src = re.sub(r'\n\[plugins\."io\.containerd\.grpc\.v1\.cri".registry\.mirrors\][^\[]*', '\n', src)
# 插到 [plugins."io.containerd.grpc.v1.cri"] 之后
marker = '[plugins."io.containerd.grpc.v1.cri"]'
if marker in src:
    src = src.replace(marker, marker + '\n  ' + mirrors.strip(), 1)
else:
    src += '\n' + marker + '\n  ' + mirrors.strip() + '\n'
open(p, "w").write(src)
print("config.toml updated")
PYEOF

  docker exec "$C" systemctl restart containerd 2>&1 | tail -1
done

echo
echo "=== 验证配置 ==="
docker exec ops-mgmt-control-plane sh -c 'grep -A3 "docker.io" /etc/containerd/config.toml | head -8'
echo
echo "=== containerd 状态 ==="
for C in ops-mgmt-control-plane biz-prod-regiona-control-plane biz-prod-regionb-control-plane; do
  printf "  %-40s %s\n" "$C" "$(docker exec $C systemctl is-active containerd 2>&1)"
done
