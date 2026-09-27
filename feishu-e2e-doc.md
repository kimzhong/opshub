## 环境概览

本环境为 Kind 多集群本地开发演示平台，完整覆盖从代码提交到生产发布的端到端 DevOps 流程。

---

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
  └─ 示例应用 demo-app (自动扩缩容)
```

---

## 二、组件清单与访问地址

| 组件 | 用途 | 访问地址 | 凭证 |
|------|------|---------|------|
| GitLab.com | 代码托管 + CI | https://gitlab.com | GitLab 账号 |
| ArgoCD | GitOps 面板 | http://localhost:30080 | admin / `wG0YYYIbLXX31dVf` |
| Grafana | 指标可视化 | http://localhost:30300 | admin / admin123 |
| Prometheus | 指标采集 | Cluster 内置 | - |
| Loki | 日志聚合 | Cluster 内置 | - |
| Alertmanager | 告警通知 | Cluster 内置 | - |
| Sealed Secrets | 密钥管理 | kube-system | - |
| GitLab Runner | CI 执行器 | gitlab-runner namespace | 需注册 |

---

## 三、集群信息

| 集群名 | 节点数 | 用途 | API Server |
|--------|--------|------|------------|
| ops-mgmt | 1 cp + 3 infra workers | 运维管理（ArgoCD/监控/GitLab Runner） | localhost:6443 |
| biz-prod-regiona | 1 cp + 2 workers | 业务集群 A | localhost:6443 |
| biz-prod-regionb | 1 cp + 2 workers | 业务集群 B | localhost:6443 |

kubectl 上下文切换：

```bash
wsl -d Ubuntu kubectl config use-context kind-ops-mgmt
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regiona
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regionb
```

---

## 四、发布流程（GitOps + CI/CD）

### 完整流水线

1. **代码提交** → push 到 GitLab main/develop 分支
2. **CI Pipeline 触发** → GitLab Runner 在 K8s 内执行
3. **构建阶段** → Docker build → push 到 GitLab Container Registry
4. **测试阶段** → 单元测试 + 集成测试 + Trivy 安全扫描
5. **部署 Staging** (develop 分支) → ArgoCD 自动同步
6. **手动确认** → GitLab CI manual job 确认 production 部署
7. **部署 Production** → 自动更新镜像 tag → ArgoCD 检测到变更并同步
8. **健康检查** → 验证 deployment / HPA 状态

### GitOps 优势

- 集群状态由 Git 驱动，任何变更都有审计记录
- ArgoCD Dashboard 直观展示同步状态
- 支持一键 Rollback 回滚到上一个 Commit

---

## 五、安全模型

### 认证 (IAM)

- **Dex** 作为 OIDC Provider，支持 GitLab OAuth 登录 K8s（待部署）
- Kubeconfig 通过 OIDC 动态获取，每次 Token 有时效

### 授权 (RBAC)

- ClusterRole: admin / edit / view（按 namespace 分配）
- ServiceAccount: 每个应用独立 SA，限制权限范围

### 密钥管理

- **Sealed Secrets**: 用公钥加密 Secret，提交到 Git 不泄露
- 私钥保存在 K8s cluster 中，只有 Sealed Secrets Controller 能解密

### 镜像安全

- Trivy 扫描 CI 阶段阻断高危漏洞
- 私有镜像仓库 + ImagePullSecrets

---

## 六、故障场景与响应

### 故障 1：Pod OOMKilled / CrashLoopBackOff

**诊断**
```bash
kubectl describe pod <pod-name> -n demo-app
kubectl logs <pod-name> -n demo-app --previous
```

**自动响应**: HPA 扩容 + Prometheus 告警 + Alertmanager 通知

**手动响应**: ArgoCD UI 一键回滚

### 故障 2：ArgoCD OutOfSync

**诊断**
```bash
argocd app get demo-app
kubectl get events -n demo-app --sort-by='.lastTimestamp'
```

**手动响应**: 修复后 git push，ArgoCD 自动同步

### 故障 3：资源耗尽

**诊断**
```bash
kubectl top pods -n demo-app
```

**自动响应**: HPA 检测 CPU > 70% → 自动扩容

### 故障 4：Kind 集群损坏

**恢复**: 双击 `kind-env-start.bat` 一键重建

---

## 七、可观测方案

### 指标 (Metrics)
- **Prometheus**: K8s 原生指标 + 自定义 app 指标，保留 15 天
- **Grafana**: 预设仪表盘（K8s / Nginx / 业务）

### 日志 (Logs)
- **Loki**: 从各 Pod 收集 stdout/stderr，保留 30 天
- Grafana Explore 查询日志

### 告警 (Alerts)
- PrometheusRule 自定义告警规则（Pod Down / 高延迟 / 高错误率）
- Alertmanager 配置 Webhook → 飞书机器人 / Slack
- MTTA 目标: < 5 分钟

---

## 八、一键启动

```batch
双击 kind-env-start.bat
```

或管理员 CMD：

```cmd
.\kind-env-start.bat
```

---

## 九、后续步骤（用户操作）

<callout emoji="⚠️" background-color="light-yellow" border-color="yellow">
GitLab Runner 需要注册 Token 才能使用。
</callout>

**注册步骤：**

1. 打开 https://gitlab.com → 创建项目或已有项目
2. 进入 **Settings → CI/CD → Runners**
3. 复制 **Registration token**
4. 执行注册命令（Runner 已在集群中安装）：

```bash
wsl -d Ubuntu kubectl -n gitlab-runner exec -it deploy/gitlab-runner -- \
  gitlab-runner register \
  --non-interactive \
  --url https://gitlab.com \
  --token YOUR_TOKEN_HERE \
  --description kind-ops-mgmt \
  --tag-list kubernetes,kind \
  --locked=false \
  --run-untagged=true \
  --executor kubernetes
```

---

## 十、环境状态

| 组件 | 状态 |
|------|------|
| 3 个 Kind 集群 | ✅ 在线 |
| ArgoCD | ✅ 运行中 (http://localhost:30080) |
| kube-prometheus-stack | 🔄 部署中 |
| Loki | 🔄 部署中 |
| GitLab Runner | ⏳ 等待用户注册 Token |
| Sealed Secrets | ⏳ 待安装 |
| Dex (OIDC) | ⏳ 待部署 |
| 示例应用 demo-app | 📁 配置已就绪 |
