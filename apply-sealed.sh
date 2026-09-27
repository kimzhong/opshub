#!/bin/bash
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
echo "=== 应用 Sealed Secrets ==="
kubectl --context $CTX apply -f /mnt/c/Users/kim/kind-env/sealed-controller.yaml 2>&1 | tail -8
echo
echo "=== 等待就绪 ==="
kubectl --context $CTX -n kube-system rollout status deploy/sealed-secrets --timeout=200s 2>&1 | tail -2
echo
kubectl --context $CTX get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
echo
echo "=== 公钥 Secret ==="
kubectl --context $CTX get secret -n kube-system | grep sealed
