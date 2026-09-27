#!/bin/bash
echo "=== 连通性测试 ==="
for host in docker.m.daocloud.io dockerproxy.com registry.cn-hangzhou.aliyuncs.com docker.io registry-1.docker.io mirrors.aliyun.com; do
  printf "  %-38s " "$host"
  code=$(timeout 8 curl -s -o /dev/null -w '%{http_code}' "https://$host/v2/" 2>/dev/null)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    echo "OK (HTTP $code)"
  else
    echo "FAIL"
  fi
done
echo
echo "=== DNS ==="
timeout 5 getent hosts registry-1.docker.io 2>&1 | head -2 || echo "  DNS 解析失败"
timeout 5 getent hosts registry.cn-hangzhou.aliyuncs.com 2>&1 | head -2 || echo "  阿里云 DNS 失败"
echo
echo "=== 代理环境变量 ==="
env | grep -i proxy || echo "  无代理设置"
