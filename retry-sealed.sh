#!/bin/bash
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
echo "=== 删除卡住的 sealed-secrets Pod ==="
kubectl --context $CTX -n kube-system delete pod -l app.kubernetes.io/name=sealed-secrets --force --grace-period=0 2>&1 | tail -2
echo
echo "=== 等待 60s 观察拉取 ==="
for i in 1 2 3 4 5 6; do
  sleep 10
  ST=$(kubectl --context $CTX -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  RD=$(kubectl --context $CTX -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  echo "  [$((i*10))s] phase=$ST ready=$RD"
  [ "$ST" = "Running" ] && [ "$RD" = "true" ] && break
done
echo
kubectl --context $CTX -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets
echo
echo "=== 公钥 Secret ==="
kubectl --context $CTX get secret -n kube-system 2>&1 | grep -i sealed
