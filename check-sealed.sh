#!/bin/bash
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
echo "=== kube-system deploy ==="
kubectl --context $CTX get deploy -n kube-system 2>&1
echo
echo "=== kube-system pods ==="
kubectl --context $CTX get pods -n kube-system 2>&1
echo
echo "=== secrets ==="
kubectl --context $CTX get secret -n kube-system 2>&1 | grep -i sealed
echo
echo "=== controller 日志 ==="
POD=$(kubectl --context $CTX get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets -o name 2>/dev/null | head -1)
echo "pod=$POD"
[ -n "$POD" ] && kubectl --context $CTX -n kube-system logs "$POD" --tail=15 2>&1
