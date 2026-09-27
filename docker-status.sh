#!/bin/bash
export PATH=/usr/local/bin:$PATH
echo "=== Docker 容器 ==="
docker ps --format 'table {{.Names}}\t{{.Status}}' 2>&1 | head -10
echo
echo "=== 本地镜像 ==="
docker images --format '{{.Repository}}:{{.Tag}}  {{.Size}}' 2>&1 | head -10
echo
echo "=== Docker 磁盘 ==="
docker system df 2>&1 | head -5
