#!/bin/bash
echo "=== kubectl 文件详情 ==="
ls -la /usr/local/bin/kubectl
file /usr/local/bin/kubectl 2>/dev/null
echo
echo "=== 直接执行测试 ==="
/usr/local/bin/kubectl version --client 2>&1 | head -3
echo "exit=$?"
echo
echo "=== kind / helm 测试 ==="
/usr/local/bin/kind version 2>&1 | head -2
/usr/local/bin/helm version --short 2>&1 | head -2
echo
echo "=== 集群列表 ==="
/usr/local/bin/kind get clusters 2>&1
echo
echo "=== Docker 容器 ==="
docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>&1 | head -10
