#!/bin/bash
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
echo "=== 重新 apply ==="
kubectl --context $CTX apply -f /mnt/c/Users/kim/kind-env/sealed-controller.yaml 2>&1 | tail -3
echo
for i in $(seq 1 12); do
  sleep 10
  ST=$(kubectl --context $CTX -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  RD=$(kubectl --context $CTX -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
  RS=$(kubectl --context $CTX -n kube-system get pods -l app.kubernetes.io/name=sealed-secrets -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
  echo "  [$((i*10))s] phase=${ST:-none} ready=${RD:-} ${RS:+waiting=$RS}"
  [ "$ST" = "Running" ] && [ "$RD" = "true" ] && echo "  ✓ 就绪" && break
done
echo
kubectl --context $CTX -n kube-system get pods 2>&1 | grep sealed
echo
echo "=== 公钥 ==="
kubectl --context $CTX get secret -n kube-system 2>&1 | grep -i sealed
