#!/bin/bash
export PATH=/usr/local/bin:$PATH

echo "=== 1. 统一 context 名为 kind-<name> ==="
# kind 创建时如果 config 里有 name: 字段，会覆盖 --name，导致 context 不带 kind- 前缀
# 这里手动重命名，让代码里的 kind-ops-mgmt 等名字生效
declare -A MAP=(
  ["ops-mgmt"]="kind-ops-mgmt"
  ["biz-prod-regiona"]="kind-biz-prod-regiona"
  ["biz-prod-regionb"]="kind-biz-prod-regionb"
)

for old in "${!MAP[@]}"; do
  new="${MAP[$old]}"
  # 跳过本来就对的名字
  if [ "$old" = "$new" ]; then continue; fi
  if kubectl config get-contexts -o name | grep -qx "$old"; then
    kubectl config rename-context "$old" "$new" 2>&1 && echo "  $old → $new"
  fi
done

echo
echo "=== 2. 修复 cluster/user 内部引用 ==="
for new in kind-ops-mgmt kind-biz-prod-regiona kind-biz-prod-regionb; do
  kubectl config set-context "$new" --cluster="$new" --user="$new" 2>/dev/null
done

echo
echo "=== 3. 当前 contexts ==="
kubectl config get-contexts
echo
echo "=== 4. 验证各集群节点 ==="
for c in kind-ops-mgmt kind-biz-prod-regiona kind-biz-prod-regionb; do
  echo "--- $c ---"
  kubectl --context "$c" get nodes --no-headers 2>&1 | awk '{print "   ", $1, $2}'
done
