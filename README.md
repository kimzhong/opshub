# Kind 多集群环境

本地 Kind K8s 多集群开发环境，支持 3 个集群 + ArgoCD GitOps。

## 目录结构

```
kind-env/
├── kind-env-start.bat       # 一键启动脚本（双击运行）
├── reg_docker_svc.ps1      # Docker Desktop 服务注册脚本（自动调用）
├── kind-ops-mgmt.yaml      # ops-mgmt 集群配置（1 control-plane + 3 infra workers）
├── kind-biz-prod.yaml      # 业务集群配置（2 区域各 1 cp + 2 workers）
└── README.md               # 本文件
```

## 一键启动

```batch
双击 kind-env-start.bat
```

或管理员 CMD：

```cmd
.\kind-env-start.bat
```

## 启动流程

1. 检查 Docker Desktop daemon 是否就绪
2. 启动/注册 `com.docker.service`（如需）
3. 启动 Docker Desktop GUI（如未运行）
4. 检查 3 个 Kind 集群是否存在，不存在则创建
5. 合并所有集群 kubeconfig，切换到 ops-mgmt

## 集群信息

| 集群名 | 节点数 | 用途 | API Server |
|--------|--------|------|------------|
| ops-mgmt | 1 cp + 3 infra workers | 运维管理（ArgoCD） | localhost:6443 |
| biz-prod-regiona | 1 cp + 2 workers | 业务集群 A | localhost:6443 |
| biz-prod-regionb | 1 cp + 2 workers | 业务集群 B | localhost:6443 |

## kubectl 上下文切换

```bash
wsl -d Ubuntu kubectl config use-context kind-ops-mgmt
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regiona
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regionb

# 查看所有上下文
wsl -d Ubuntu kubectl config get-contexts
```

## ArgoCD

- **UI**: http://localhost:30080
- **用户名**: `admin`
- **密码**: 见启动脚本输出，或执行：

```bash
wsl -d Ubuntu kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## 重建单个集群

```bash
# 删除
wsl -d Ubuntu kind delete cluster --name ops-mgmt

# 重建（使用配置）
wsl -d Ubuntu kind create cluster --name ops-mgmt --config kind-ops-mgmt.yaml
```

## 重建 ArgoCD

```bash
wsl -d Ubuntu kubectl delete namespace argocd --grace-period=0
wsl -d Ubuntu kubectl create namespace argocd
wsl -d Ubuntu kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
wsl -d Ubuntu kubectl patch svc argocd-server -n argocd --type=merge -p '{"spec":{"type":"NodePort"}}'
```

## 工具版本

- Kubernetes: v1.27.3（Kindest Node）
- kubectl: v1.32.2
- kind: v0.20.0
- helm: v3.14.0
- ArgoCD: stable（latest）
