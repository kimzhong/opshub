# OpsHub kind 多集群

本目录包含 OpsHub 平台的多集群编排脚本，用于本地模拟生产环境的多集群拓扑。

## 集群拓扑

| 集群 | 模拟角色 | Pod CIDR | 节点数 | 用途 |
|---|---|---|---|---|
| `ops-mgmt` | 平台管理集群（私有 IDC）| 10.100.0.0/16 | 1 cp + 3 worker | ArgoCD / Keycloak / 监控 / 备份 / 混沌 |
| `biz-prod-regiona` | 业务生产集群 A（公有云 region A）| 10.101.0.0/16 | 1 cp + 2 worker | 业务应用主 |
| `biz-prod-regionb` | 业务生产集群 B（公有云 region B）| 10.102.0.0/16 | 1 cp + 2 worker | 业务应用备 |

**关键约束**：每个集群的 Pod CIDR 必须不同，模拟真实生产中"各集群独立规划"。

## 前置条件

- **Docker Desktop** 或 Docker Engine 20.10+
- **kind v0.23+**：`brew install kind` / `choco install kind`
- **kubectl v1.30+**
- **内存建议**：≥ 16GB 可用内存
- **磁盘建议**：≥ 50GB 可用空间

## 快速开始

```powershell
# 一键创建
.\create-clusters.ps1

# 查看状态
kubectl get nodes --context ops-mgmt
kubectl get nodes --context biz-prod-regiona
kubectl get nodes --context biz-prod-regionb

# 切换默认 context
kubectl config use-context ops-mgmt

# 一键清理
.\delete-clusters.ps1
```

## 端口映射

| 集群 | 宿主机端口 | 容器端口 | 用途 |
|---|---|---|---|
| `ops-mgmt` | 30080 | 30080 | ArgoCD / Grafana HTTP |
| `ops-mgmt` | 30443 | 30443 | ArgoCD / Grafana HTTPS |
| `biz-prod-regiona` | 30081 | 30081 | 应用 HTTP |
| `biz-prod-regiona` | 30444 | 30444 | 应用 HTTPS |
| `biz-prod-regionb` | 30082 | 30082 | 应用 HTTP |
| `biz-prod-regionb` | 30445 | 30445 | 应用 HTTPS |

## 多集群管理

### ArgoCD 注册 spoke 集群

```bash
# 在 ops-mgmt 上
ARGOCD_SERVER=localhost:30443
argocd login $ARGOCD_SERVER

# 注册业务集群
argocd cluster add biz-prod-regiona --name biz-prod-regiona
argocd cluster add biz-prod-regionb --name biz-prod-regionb

# 验证
argocd cluster list
```

### kubectl 跨集群操作

```bash
# 单集群
kubectl --context ops-mgmt get pods -A
kubectl --context biz-prod-regiona get pods -A

# 所有集群（推荐用 kubie 或 fubectl 简化）
for ctx in ops-mgmt biz-prod-regiona biz-prod-regionb; do
  echo "=== $ctx ==="
  kubectl --context $ctx get nodes
done
```

## 资源消耗

| 集群 | 内存 | CPU |
|---|---|---|
| ops-mgmt (1cp+3w) | ~6 GB | ~4 cores |
| biz-prod-regiona (1cp+2w) | ~3 GB | ~2 cores |
| biz-prod-regionb (1cp+2w) | ~3 GB | ~2 cores |
| **合计** | **~12 GB** | **~8 cores** |

## 常见问题

### Q: kind 创建失败 "ERROR: failed to create cluster"

通常是端口冲突或资源不足。检查：
- 8000+ 端口是否被占用
- Docker Desktop 内存限制（设置 16GB+）
- kind 版本是否 ≥ 0.23

### Q: Pod 一直 Pending

通常是资源不足：
```bash
kubectl describe node | grep -A 5 "Allocated resources"
```

### Q: 跨集群网络不通

kind 集群间默认是隔离的（不同 Docker network）。需要：
- 业务场景：Submariner 隧道（在 ops-mgmt 部署）
- 简单场景：用 `kubectl --context` 切换即可

### Q: 如何模拟 region 故障？

```powershell
# 模拟 region A 完全故障
kind delete cluster --name biz-prod-regiona

# 此时应用应能切到 region B（演示 ArgoCD + 健康检查）
```
