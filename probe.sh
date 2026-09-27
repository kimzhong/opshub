#!/bin/bash
echo "=== 工具探测 ==="
for t in kubectl kind helm docker minikube k3d curl jq; do
  p=$(command -v "$t" 2>/dev/null)
  echo "  $t: ${p:-NOT FOUND}"
done
echo
echo "=== 常见安装位置 ==="
for d in /usr/local/bin /usr/bin "$HOME/bin" "$HOME/.local/bin" /opt; do
  if [ -d "$d" ]; then
    echo "  [$d]"
    ls "$d" 2>/dev/null | grep -Ei 'kubectl|kind|helm|k3d' | sed 's/^/    /'
  fi
done
echo
echo "=== Docker 状态 ==="
docker info --format '{{.ServerVersion}} / {{.OperatingSystem}}' 2>&1 | head -2
echo
echo "=== 磁盘 ==="
df -h / /mnt/c 2>/dev/null | head -4
echo
echo "=== 内存 ==="
free -h 2>/dev/null | head -2
