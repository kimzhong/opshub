#!/bin/bash
# 用国内镜像源预拉取 kind 节点镜像并打回原标签
export PATH=/usr/local/bin:$PATH

V="v1.27.3"
ORIG="kindest/node:${V}"
MIRRORS=(
  "docker.m.daocloud.io/kindest/node:${V}"
  "dockerproxy.com/kindest/node:${V}"
  "docker.1ms.run/kindest/node:${V}"
  "registry.cn-hangzhou.aliyuncs.com/google_containers/kube-apiserver:v1.27.3"
)

echo "=== 目标镜像: $ORIG ==="
echo

for M in "${MIRRORS[@]}"; do
  echo "--- 尝试: $M ---"
  if timeout 180 docker pull "$M" 2>&1 | tail -3; then
    if docker image inspect "$M" >/dev/null 2>&1; then
      echo "拉取成功，打标签 $ORIG"
      docker tag "$M" "$ORIG"
      echo "OK: $ORIG"
      docker images | grep kindest
      exit 0
    fi
  fi
  echo "失败，尝试下一个源"
  echo
done

echo "所有镜像源都失败"
exit 1
