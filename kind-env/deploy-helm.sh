#!/bin/bash
set -e
echo "=== Adding Helm repos ==="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update 2>/dev/null || true
helm repo add gitlab https://charts.gitlab.io --force-update 2>/dev/null || true
helm repo update
echo "=== Helm repos ready ==="
