#!/bin/bash
# 不限时长拉取 kind 节点镜像（dockerd 会复用已下载的层）
export PATH=/usr/local/bin:$PATH
V="v1.27.3"
ORIG="kindest/node:${V}"

echo "=== 拉取 $ORIG (经 daocloud 镜像) ==="
docker pull "docker.m.daocloud.io/kindest/node:${V}"
rc=$?

if [ $rc -ne 0 ]; then
  echo "daocloud 失败 (rc=$rc)，尝试直连…"
  docker pull "$ORIG"
  rc=$?
fi

if [ $rc -eq 0 ]; then
  # 打回标准标签（如果是从镜像站拉的）
  if ! docker image inspect "$ORIG" >/dev/null 2>&1; then
    docker tag "docker.m.daocloud.io/kindest/node:${V}" "$ORIG"
  fi
  echo
  echo "=== 成功 ==="
  docker images | grep -i kindest
else
  echo "拉取失败 rc=$rc"
  exit 1
fi
