# Kind 多集群端到端 DevOps 演示环境

## 一、架构总览

```
开发者
  │
  ▼
GitLab.com (代码仓库 + CI/CD)
  │ push / merge → 触发 pipeline
  ▼
GitLab CI Runner (kind-ops-mgmt 集群内运行)
  │ build → test → scan → push image → deploy
  ▼
容器镜像 (GitLab Container Registry)
  │
  ▼
ArgoCD (GitOps, ops-mgmt)
  │ watch repo → sync manifests → apply to cluster
  ▼
Kubernetes (ops-mgmt + biz-prod-regiona + biz-prod-regionb)
  │
  ├─ Sealed Secrets (加密敏感配置)
  ├─ Prometheus + Grafana + Loki (可观测)
  ├─ Alertmanager (告警)
  ├─ Dex (OIDC / IAM)
  └─ 示例应用 demo-app (自动扩缩容)
```

---

## 二、组件清单

| 组件 | 用途 | 访问地址 |
|------|------|---------|
| GitLab.com | 代码托管 + CI | https://gitlab.com |
| ArgoCD | GitOps 面板 | http://localhost:30080 |
| Grafana | 指标可视化 | NodePort 30300 (admin/admin123) |
| Prometheus | 指标采集 | 内置于 kube-prometheus-stack |
| Alertmanager | 告警通知 | 随 prometheus-stack 部署 |
| Loki | 日志聚合 | 随 prometheus-stack 部署 |
| Sealed Secrets | 密钥管理 | kube-system namespace |
| Dex | OIDC Provider | 待部署 |
| GitLab Runner | CI 执行器 | gitlab-runner namespace |

---

## 三、发布流程

### GitOps 发布流程

1. **代码提交** → push 到 GitLab main/develop 分支
2. **CI Pipeline 触发** → GitLab Runner 在 K8s 内执行
3. **构建阶段** → Docker build → push 到 GitLab Container Registry
4. **测试阶段** → 单元测试 + 集成测试 + Trivy 安全扫描
5. **部署 Staging** (develop 分支) → ArgoCD 自动同步到 staging 集群
6. **手动确认** → GitLab CI manual job 确认 production 部署
7. **部署 Production** → 自动更新镜像 tag → ArgoCD 检测到变更并同步
8. **健康检查** → 验证 deployment / ingress / HPA 状态

### GitOps 优势

- 集群状态由 Git 驱动，任何变更都有审计记录
- ArgoCD Dashboard 直观展示同步状态
- 支持 Rollback（一键回滚到上一个 Commit）

---

## 四、安全模型

### 认证 (IAM)

- **Dex** 作为 OIDC Provider，支持 GitLab OAuth 登录 K8s
- Kubeconfig 通过 OIDC 动态获取，每次 Token 有时效

### 授权 (RBAC)

- ClusterRole: admin / edit / view（按 namespace 分配）
- ServiceAccount: 每个应用独立 SA，限制权限范围

### 密钥管理

- **Sealed Secrets**: 用公钥加密 Secret，提交到 Git 不泄露
- 私钥保存在 K8s cluster 中，只有 Sealed Secrets Controller 能解密

### 网络策略

- 默认 deny-all，每个 namespace 按需开放
- Ingress/Egress 白名单控制

### 镜像安全

- Trivy 扫描 CI 阶段阻断高危漏洞
- 私有镜像仓库 + ImagePullSecrets

---

## 五、故障场景与响应

### 场景 1：Pod Crash

```
症状: Pod OOMKilled / OOM
自动响应:
  - Kubernetes HPA 自动扩容
  - Prometheus 告警: DemoAppDown
  - Alertmanager 触发 Webhook → 通知
手动响应:
  - kubectl describe pod -n demo-app 查看事件
  - kubectl logs -n demo-app <pod> --previous 查看崩溃日志
  - ArgoCD UI 一键回滚
```

### 场景 2：CPU/内存过载

```
症状: 响应延迟 > 2s，CPU > 80%
自动响应:
  - HPA 扩容 Pod（2→4→6→8）
  - Prometheus 告警: DemoAppHighLatency
  - Alertmanager 发送 Slack/邮件告警
手动响应:
  - Grafana 查看实时 QPS / 延迟
  - kubectl top pods -n demo-app 查看资源消耗
```

### 场景 3：Deployment 同步失败

```
症状: ArgoCD 显示 OutOfSync / Sync Error
手动响应:
  - ArgoCD UI 查看差异（Diff）
  - kubectl get events -n demo-app --sort-by='.lastTimestamp'
  - kubectl apply --dry-run 验证 manifest 语法
  - 修复后 commit → ArgoCD 自动同步
```

### 场景 4：镜像拉取失败

```
症状: ImagePullBackOff
手动响应:
  - 检查 Secret (docker-registry) 是否存在
  - kubectl get secret -n demo-app
  - 更新 imagePullSecrets 或修复 registry 认证
```

---

## 六、可观测方案

### 指标 (Metrics)

- **Prometheus**: K8s 原生指标 + 自定义 app 指标
- **Grafana**: 预设仪表盘（K8s / Nginx / 业务）
- 保留周期: 15 天

### 日志 (Logs)

- **Loki**: 从各 Pod 收集 stdout/stderr
- Grafana Explore 查询日志
- 保留周期: 30 天

### 追踪 (Traces)

- 可选: Jaeger / Tempo（通过 Prometheus Operator 安装）
- OpenTelemetry SDK 埋点到 demo-app

### 告警 (Alerts)

- PrometheusRule 自定义告警规则
- Alertmanager 配置 Webhook → Slack / 邮件 / 飞书机器人
- MTTA（平均响应时间）目标: < 5 分钟

---

## 七、容灾恢复

### 集群故障恢复

```bash
# 1. 检查 Docker Desktop 运行状态
wsl -d Ubuntu docker info

# 2. 检查 Kind 集群
wsl -d Ubuntu kind get clusters
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes

# 3. 若集群损坏，重建
wsl -d Ubuntu kind delete cluster --name ops-mgmt
wsl -d Ubuntu kind create cluster --name ops-mgmt --config kind-ops-mgmt.yaml

# 4. 重跑 Helm 安装（见一键启动脚本）
```

### GitOps 恢复

```bash
# ArgoCD 自动同步，无需手动恢复
# 手动触发同步：
kubectl argoapp sync demo-app -n argocd
```

### 数据备份

- K8s 所有配置通过 Git 管理（IaC）
- Helm values 文件化存储在 Git
- Docker Desktop 数据卷备份（WSL snapshot）

---

## 八、一键启动

```batch
双击 kind-env-start.bat
```

所有组件自动按依赖顺序启动。

---

## 九、环境信息

| 项目 | 值 |
|------|-----|
| K8s 版本 | v1.27.3 |
| Docker | 28.3.3 |
| ArgoCD | http://localhost:30080 |
| Grafana | NodePort 30300 |
| Prometheus | 内置 |
| GitLab Runner | gitlab-runner namespace |
| Sealed Secrets | kube-system |
