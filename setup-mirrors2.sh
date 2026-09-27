#!/bin/bash
# 在 WSL 侧生成完整 containerd 配置，拷进所有节点
export PATH=/usr/local/bin:$PATH
TMP=/tmp/ct-config.toml

cat > "$TMP" <<'EOF'
version = 2
root = "/var/lib/containerd"

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.9"
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = ""
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
      endpoint = ["https://docker.m.daocloud.io", "https://docker.1ms.run"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry-1.docker.io"]
      endpoint = ["https://docker.m.daocloud.io"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."quay.io"]
      endpoint = ["https://quay.m.daocloud.io"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."gcr.io"]
      endpoint = ["https://gcr.m.daocloud.io"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."k8s.gcr.io"]
      endpoint = ["https://k8s.gcr.io", "https://registry.k8s.io"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."ghcr.io"]
      endpoint = ["https://ghcr.m.daocloud.io"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
      endpoint = ["https://registry.k8s.io"]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."bitnami.com"]
      endpoint = ["https://docker.m.daocloud.io"]

[plugins."io.containerd.runtime.v1.linux"]
  [plugins."io.containerd.runtime.v1.linux".cgroups]
    cgroupfs = true

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "overlayfs"

[plugins."io.containerd.monitor.v1.cri"]
  prometheus = false

[debug]
  level = "info"
EOF

echo "=== 分发到所有节点 ==="
for C in $(docker ps --filter 'label=io.x-k8s.kind.cluster' --format '{{.Names}}'); do
  docker cp "$TMP" "$C:/etc/containerd/config.toml" 2>&1 | tail -1
  docker exec "$C" systemctl restart containerd 2>&1 | tail -1
  printf "  %-38s %s\n" "$C" "$(docker exec $C systemctl is-active containerd 2>&1)"
done

echo
echo "=== 验证配置已生效 ==="
docker exec ops-mgmt-control-plane sh -c 'grep -c "endpoint" /etc/containerd/config.toml; grep -A2 "docker.io" /etc/containerd/config.toml | head -4'
