#!/bin/bash
# 下载真正的 Linux kubectl（校验 ELF magic，防止再拿到 Windows PE）
export PATH=/usr/local/bin:$PATH
V="v1.27.3"
DST=/usr/local/bin/kubectl

SOURCES=(
  "https://mirrors.aliyun.com/kubernetes/new/core/stable/v1.27/release/bin/linux/amd64/kubectl"
  "https://dl.k8s.io/release/${V}/bin/linux/amd64/kubectl"
  "https://mirrors.huaweicloud.com/kubernetes/new/core/stable/v1.27/release/bin/linux/amd64/kubectl"
  "https://kubernetes-release.storage.googleapis.com/bin/linux/amd64/v1.27.3/kubectl"
)

is_elf() {
  # ELF magic: 7f 45 4c 46
  head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n' | grep -q '^7f454c46$'
}

for URL in "${SOURCES[@]}"; do
  HOST=$(echo "$URL" | awk -F/ '{print $3}')
  echo "--- 尝试 $HOST ---"
  rm -f /tmp/kc
  if curl -fL --connect-timeout 15 --max-time 300 -o /tmp/kc "$URL" 2>/dev/null; then
    if is_elf /tmp/kc; then
      SIZE=$(stat -c%s /tmp/kc)
      echo "  拿到 Linux ELF，${SIZE} 字节"
      chmod +x /tmp/kc
      # 先自测
      if /tmp/kc version --client >/dev/null 2>&1; then
        rm -f "$DST"
        cp /tmp/kc "$DST"
        echo "  安装成功:"
        /usr/local/bin/kubectl version --client
        file "$DST"
        exit 0
      else
        echo "  自测失败"
      fi
    else
      echo "  不是 ELF（可能是 Windows PE 或错误页），跳过"
    fi
  else
    echo "  下载失败"
  fi
  echo
done

echo "所有源都失败"
exit 1
