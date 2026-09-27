#!/bin/bash
# 重建 3 个 Kind 集群
export PATH=/usr/local/bin:$PATH
DIR=/mnt/c/Users/kim/kind-env
KIND_IMAGE="kindest/node:v1.27.3"

echo "############ 1/3  ops-mgmt (1cp + 3w) ############"
kind create cluster \
  --name ops-mgmt \
  --image "$KIND_IMAGE" \
  --config "$DIR/kind-ops-mgmt.yaml" \
  --wait 120s 2>&1 | tail -20

echo
echo "############ 2/3  biz-prod-regiona (1cp + 2w) ############"
kind create cluster \
  --name biz-prod-regiona \
  --image "$KIND_IMAGE" \
  --config "$DIR/kind-prod.yaml" \
  --wait 120s 2>&1 | tail -20

echo
echo "############ 3/3  biz-prod-regionb (1cp + 2w) ############"
kind create cluster \
  --name biz-prod-regionb \
  --image "$KIND_IMAGE" \
  --config "$DIR/kind-prod.yaml" \
  --wait 120s 2>&1 | tail -20

echo
echo "############ 集群列表 ############"
kind get clusters
echo
echo "############ kubeconfig context ############"
kubectl config get-contexts
