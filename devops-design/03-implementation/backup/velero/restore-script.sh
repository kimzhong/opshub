#!/bin/bash
# Velero 验证脚本
# 每周自动验证最近一次备份可恢复
set -euo pipefail

NAMESPACE="dr-test-$(date +%s)"
BACKUP=$(velero backup get -o json 2>/dev/null | \
  jq -r '.items | sort_by(.metadata.creationTimestamp) | reverse | .[0].metadata.name')

if [ -z "$BACKUP" ] || [ "$BACKUP" = "null" ]; then
  echo "ERROR: no backup found"
  exit 1
fi

echo "=== Validating backup: $BACKUP ==="
echo "Test namespace: $NAMESPACE"

# 1. 恢复到测试 namespace
echo "[1/4] Restoring backup..."
velero restore create "dr-test-$(date +%s)" \
  --from-backup "$BACKUP" \
  --namespace-mappings "app-checkout:$NAMESPACE" \
  --wait

# 2. 等待 Pod 就绪
echo "[2/4] Waiting for pods..."
sleep 60

# 3. 验证 Pod 状态
echo "[3/4] Verifying pod status..."
PODS=$(kubectl get pods -n "$NAMESPACE" -o json 2>/dev/null)
NOT_RUNNING=$(echo "$PODS" | jq -r '.items[] | select(.status.phase != "Running") | .metadata.name')

if [ -n "$NOT_RUNNING" ]; then
  echo "FAIL: Pods not running: $NOT_RUNNING"
  kubectl delete namespace "$NAMESPACE" --wait=false
  exit 1
fi

# 4. 清理
echo "[4/4] Cleanup..."
kubectl delete namespace "$NAMESPACE" --wait=false

echo "============================================"
echo "✓ Backup $BACKUP verified successfully"
echo "============================================"
