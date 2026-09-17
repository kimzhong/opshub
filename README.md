# opshub - DevOps 平台本地实验环境

本地 Kubernetes 多集群开发环境 + DevOps 平台设计文档。

## 目录结构

```
opshub/
├── kind-env/          # 本地 Kind 多集群环境
│   ├── README.md      # 环境说明
│   ├── kind-ops-mgmt.yaml        # 运维管理集群配置
│   ├── kind-biz-prod.yaml        # 业务集群配置
│   ├── kind-env-start.bat        # 一键启动脚本
│   ├── deploy-helm.sh            # Helm 部署脚本
│   ├── values-prometheus.yaml    # kube-prometheus-stack 配置
│   ├── values-gitlab-runner.yaml # GitLab Runner 配置
│   ├── start-proxy.bat           # 代理启动器
│   ├── wsl_proxy.py             # WSL 代理层
│   ├── proxy.py                 # 简单 HTTP 代理
│   ├── reg_docker_svc.ps1       # Docker Desktop 服务注册
│   ├── ops-portal/              # 运维 Portal
│   └── demo-app/                # 示例应用
│
├── devops-design/     # DevOps 平台设计文档
│   ├── INDEX.md
│   ├── 01-research/              # 调研报告
│   ├── 02-design/                # 架构设计、安全模型、容灾方案、ADR
│   ├── 03-implementation/        # 实施手册
│   ├── 04-封版报告.md
│   └── 05-本地实施问题与解决记录.md
```

## kind-env 快速启动

```batch
双击 kind-env-start.bat
```

或管理员 CMD：

```cmd
.\kind-env-start.bat
```

启动后服务访问地址：

| 服务 | 地址 | 凭证 |
|------|------|------|
| Grafana | http://localhost:30300 | admin / admin123 |
| ArgoCD | https://localhost:30080 | admin / (见启动输出) |
| Prometheus | port-forward 到 `svc/prometheus-prometheus:9090` | — |
| Loki | port-forward 到 `svc/loki-gateway:3100` | — |

## 环境已安装组件

- **kube-prometheus-stack**（Prometheus + Alertmanager + Grafana）
- **Loki**（日志聚合）
- **Sealed Secrets**（密码管理）
- **ArgoCD**（已在 argocd namespace）

## 工具版本

- Kubernetes: v1.27.3
- kubectl: v1.32.2
- kind: v0.20.0
- helm: v3.14.0
