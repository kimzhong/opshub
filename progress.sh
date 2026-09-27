#!/bin/bash
export PATH=/usr/local/bin:$PATH
echo "=== 创建进度 ==="
tail -25 /tmp/create-prod.log 2>/dev/null || echo "(日志还没生成)"
echo
echo "=== 集群 ==="
kind get clusters 2>&1
echo
echo "=== 容器 ==="
docker ps --format '{{.Names}}  {{.Status}}' 2>&1
