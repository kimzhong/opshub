#!/bin/bash
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
POD=$(kubectl --context $CTX get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
echo "dns pod=$POD"
echo
echo "=== 集群内测镜像仓库连通性 ==="
for R in registry-1.docker.io docker.m.daocloud.io dockerproxy.com registry.cn-hangzhou.aliyuncs.com; do
  printf "  %-38s " "$R"
  kubectl --context $CTX exec "$POD" -n kube-system -- sh -c "timeout 8 wget -q -O /dev/null https://$R/v2/ && echo OK || echo FAIL" 2>/dev/null || echo "timeout/err"
done
echo
echo "=== 当前 containerd 配置 ==="
docker exec ops-mgmt-control-plane cat /etc/containerd/config.toml 2>/dev/null | grep -A5 'mirrors' | head -10 || echo "(无 mirrors 配置)"
