#!/bin/bash
set -e
V="v1.27.3"
echo "=== 下载 kubectl $V ==="
curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${V}/bin/linux/amd64/kubectl" 2>&1 || {
  echo "主源失败，尝试备用源..."
  curl -fsSLo /tmp/kubectl "https://mirrors.aliyun.com/kubernetes/new/core/stable/v1.27/release/bin/linux/amd64/kubectl" 2>&1 || {
    echo "两个源都失败"; exit 1; }
}
chmod +x /tmp/kubectl
# 备份坏链接
if [ -L /usr/local/bin/kubectl ]; then
  rm -f /usr/local/bin/kubectl
  echo "已删除坏符号链接"
fi
mv /tmp/kubectl /usr/local/bin/kubectl
echo "=== 安装完成 ==="
/usr/local/bin/kubectl version --client
