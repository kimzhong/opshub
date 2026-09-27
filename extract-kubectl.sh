#!/bin/bash
# kind 节点容器内自带 kubectl，直接拷出来用（省去下载）
export PATH=/usr/local/bin:$PATH
DST=/usr/local/bin/kubectl

echo "=== 在节点容器内查找 kubectl ==="
docker exec ops-mgmt-control-plane sh -c 'ls -la /usr/bin/kubectl /usr/local/bin/kubectl 2>/dev/null; which kubectl' 2>&1
echo
echo "=== 校验是否为 ELF ==="
docker exec ops-mgmt-control-plane head -c 4 /usr/bin/kubectl 2>/dev/null | od -An -tx1
echo
echo "=== 拷出 ==="
docker cp ops-mgmt-control-plane:/usr/bin/kubectl /tmp/kc-from-container 2>&1
chmod +x /tmp/kc-from-container
ls -la /tmp/kc-from-container
echo
echo "=== 版本自测 ==="
/tmp/kc-from-container version --client 2>&1
echo
echo "=== 安装 ==="
rm -f "$DST"
cp /tmp/kc-from-container "$DST"
file "$DST" 2>/dev/null || head -c 4 "$DST" | od -An -tx1
echo
echo "=== 用它连集群 ==="
kubectl --context kind-ops-mgmt get nodes 2>&1 | head -8
