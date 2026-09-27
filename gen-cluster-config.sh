#!/bin/bash
# 集群配置生成器 —— 3 个 Kind 集群
set -e
DIR=/mnt/c/Users/kim/kind-env

# ── ops-mgmt: 1 control-plane + 3 worker ──
cat > "$DIR/ops-mgmt.yaml" <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ops-mgmt
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true,topology.kubernetes.io/zone=cn-shenzhen-a"
    extraPortMappings:
      - containerPort: 30080
        hostPort: 30080
        protocol: TCP
      - containerPort: 30300
        hostPort: 30300
        protocol: TCP
      - containerPort: 32409
        hostPort: 32409
        protocol: TCP
  - role: worker
    extraPortMappings:
      - containerPort: 30090
        hostPort: 30090
        protocol: TCP
  - role: worker
  - role: worker
EOF

# ── biz-prod-regiona: 1 control-plane + 2 worker ──
cat > "$DIR/regiona.yaml" <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: biz-prod-regiona
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "topology.kubernetes.io/region=cn-south,topology.kubernetes.io/zone=cn-shenzhen-a"
  - role: worker
  - role: worker
EOF

# ── biz-prod-regionb: 1 control-plane + 2 worker ──
cat > "$DIR/regionb.yaml" <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: biz-prod-regionb
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "topology.kubernetes.io/region=cn-south,topology.kubernetes.io/zone=cn-shenzhen-b"
  - role: worker
  - role: worker
EOF

echo "已生成 3 个集群配置:"
ls -la "$DIR"/*.yaml
