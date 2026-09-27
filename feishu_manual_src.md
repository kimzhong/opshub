# Kind 多集群环境 — 使用手册

> 本手册面向 DevOps 演示场景，涵盖日常操作、CI/CD 发布、可观测使用和故障处理。

---

## 一、环境启动

### 1.1 首次启动

1. 双击 `C:\Users\kim\kind-env\kind-env-start.bat`（管理员权限）
2. 等待 2~3 分钟，看到 `kind clusters ready` 后即可
3. 所有组件自动按顺序启动

### 1.2 日常启动

如果 Docker Desktop 已关闭，重新运行 `kind-env-start.bat` 即可。

### 1.3 验证集群状态

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n monitoring
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n argocd
```

---

## 二、服务访问指南

### 2.1 ArgoCD（GitOps 面板）

**访问地址**：`http://localhost:30080`

**登录凭证**：
- 用户名：`admin`
- 密码：`wG0YYYIbLXX31dVf`

**操作步骤**：

1. 浏览器打开 http://localhost:30080
2. 点击 **Sign in**
3. Username 输入 `admin`
4. Password 输入上面的密码
5. 点击 **Sign in**

**查看已同步的应用**：
- 左侧菜单 → **Applications**
- 可以看到所有 GitOps 管理的应用及其状态（Synced / OutOfSync）

**手动同步应用**：
- 点击应用名称 → **Sync** → **Synchronize**
- 查看差异：点击 **Diff** 标签页

**回滚**：
- 点击应用 → **History** → 选择历史版本 → **Rollback**

---

### 2.2 Grafana（监控面板）

**访问地址**：`http://localhost:30300`

**登录凭证**：
- 用户名：`admin`
- 密码：`admin123`

**查看 K8s 集群仪表盘**：
1. 左侧菜单 → **Dashboards** → **Browse**
2. 搜索 `Kubernetes`
3. 打开 `Kubernetes / Compute Resources / Namespace (Pods)`
4. 选择 namespace `demo-app` 查看应用资源

**查看 Prometheus 指标**：
1. 左侧菜单 → **Explore**
2. 数据源选择 **Prometheus**
3. 输入查询，例如：`up{job="demo-app"}`
4. 点击 **Run query**

**查看 Loki 日志**：
1. 左侧菜单 → **Explore**
2. 数据源选择 **Loki**
3. 输入查询，例如：`{namespace="demo-app"}`
4. 点击 **Run query**

**添加 Loki 数据源（首次）**：
1. ⚙️ → **Data Sources** → **Add data source**
2. 选择 **Loki**
3. URL 输入：`http://loki-gateway.monitoring.svc.cluster.local`
4. 点击 **Custom HTTP Headers** → **Add header**：
   - Header: `X-Scope-OrgID`
   - Value: `foo`
5. 点击 **Save & test**

---

### 2.3 Prometheus（指标查询）

**访问方式**：端口转发后本地访问

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090
```

浏览器访问：http://localhost:9090

**查看告警规则**：
1. 顶部菜单 → **Alerts**
2. 可以看到所有 PrometheusRule 定义的告警及其状态

**常用查询示例**：
```
# Pod 是否在线
up{job="demo-app"}

# CPU 使用率
rate(container_cpu_usage_seconds_total{namespace="demo-app"}[5m])

# 内存使用
container_memory_working_set_bytes{namespace="demo-app"}

# Pod 重启次数
kube_pod_restart_total{namespace="demo-app"}
```

---

### 2.4 Alertmanager（告警管理）

**访问方式**：端口转发

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-alertmanager 9093:9093
```

浏览器访问：http://localhost:9093

查看当前告警状态和已触发的告警。

---

## 三、CI/CD 发布流程（端到端演示）

### 3.1 准备示例应用代码

代码已在 `C:\Users\kim\kind-env\demo-app\`，包含：
- `app.py` — Python 健康检查服务
- `Dockerfile` — 容器构建
- `k8s/deployment.yaml` — K8s 部署配置
- `k8s/hpa.yaml` — 自动扩缩容
- `k8s/prometheus-rules.yaml` — Prometheus 告警规则
- `.gitlab-ci.yml` — GitLab CI 流水线

### 3.2 创建 GitLab 项目

1. 打开 https://gitlab.com → 登录 → 点击 **New repository**
2. Repository name 输入 `demo-app`
3. 选择 **Private**
4. 点击 **Create repository**

### 3.3 推送代码到 GitLab

```bash
# 在 demo-app 目录下执行
cd C:\Users\kim\kind-env\demo-app

git init
git add .
git commit -m "Initial commit"
git remote add origin https://gitlab.com/你的用户名/demo-app.git
git push -u origin main
```

### 3.4 配置 GitLab CI/CD Variables

1. GitLab 项目 → **Settings** → **CI/CD** → **Variables** → **Add variable**
2. 添加以下变量：

| Variable | Value | 说明 |
|----------|-------|------|
| `KUBECONFIG_DATA` | base64 编码的 kubeconfig | kubectl 访问集群的凭证 |
| `CI_REGISTRY_USER` | 你的 GitLab 用户名 | 镜像仓库登录 |
| `CI_REGISTRY_PASSWORD` | 你的 GitLab 访问令牌 | 镜像仓库密码 |

**生成 KUBECONFIG_DATA**：
```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt config view --raw | base64 -w 0
```
复制输出，粘贴为 `KUBECONFIG_DATA` 变量的值。

**生成 GitLab 访问令牌**：
1. GitLab → 右上角头像 → **Preferences** → **Access Tokens**
2. 名称输入 `ci-token`，勾选 `read_registry` `write_repository`
3. 点击 **Create personal access token**
4. 复制 Token，填入 `CI_REGISTRY_PASSWORD`

### 3.5 注册 GitLab Runner

1. GitLab 项目 → **Settings** → **CI/CD** → **Runners**
2. 展开 **Specific runners**，复制 **Registration token**
3. 执行注册命令：

```bash
helm upgrade --install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --set gitlabUrl=https://gitlab.com \
  --set runnerRegistrationToken="你的TOKEN" \
  --set runners.lockBuiltIn=false \
  --set runners.privileged=true \
  --set runners.tags="kubernetes,kind" \
  --set rbac.create=true \
  --set rbac.clusterWideAccess=true \
  --wait --timeout 10m
```

4. GitLab Runner 页面刷新，确认 Runner 已显示

### 3.6 触发 CI Pipeline

1. GitLab 项目 → **CI/CD** → **Pipelines** → **Run pipeline**
2. 选择分支 `main`，点击 **Run pipeline**
3. 观察流水线执行：
   - `build` — 构建 Docker 镜像
   - `test-unit` — 单元测试
   - `security-scan` — Trivy 安全扫描
   - `deploy-production` — 部署到 K8s（manual，需要手动触发）

### 3.7 手动触发生产部署

Pipeline 到达 `deploy-production` 阶段时：
1. 点击 `deploy-production` job 右侧的 **▶ Play**
2. 点击 **Play again** 确认
3. 等待部署完成

### 3.8 验证部署

```bash
# 查看 Pod 状态
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n demo-app

# 查看 Service
wsl -d Ubuntu kubectl --context kind-ops-mgmt get svc -n demo-app

# 验证 HPA
wsl -d Ubuntu kubectl --context kind-ops-mgmt get hpa -n demo-app
```

---

## 四、GitOps 演示（ArgoCD 自动同步）

### 4.1 创建 ArgoCD Application

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -n argocd -f C:\Users\kim\kind-env\demo-app\argocd\app.yaml
```

> 注意：先将 `app.yaml` 中的 `https://gitlab.com/YOUR_USERNAME/demo-app.git` 替换为实际仓库地址。

### 4.2 查看同步状态

1. 打开 http://localhost:30080
2. 登录 ArgoCD
3. 左侧 → **Applications** → 点击 `demo-app`
4. 可以看到：
   - **HEALTH**：应用健康状态
   - **SYNC**：同步状态（Synced / OutOfSync）
   - **MANIFEST DETAILS**：实际部署的 K8s 资源

### 4.3 GitOps 发布演示

1. 修改 `k8s/deployment.yaml` 中的镜像版本
2. `git add . && git commit && git push`
3. ArgoCD 自动检测到变更（默认 3 分钟轮询）
4. 自动同步到集群，无需手动操作

### 4.4 回滚演示

1. ArgoCD UI → Application → **History**
2. 选择历史版本 → **Rollback**
3. 集群自动回滚到指定版本

---

## 五、可观测使用

### 5.1 查看应用指标

1. Grafana → **Explore** → Prometheus
2. 查询：`rate(http_requests_total[5m])`
3. 设置时间范围为最近 15 分钟
4. 查看 QPS、延迟、错误率趋势

### 5.2 查看日志

1. Grafana → **Explore** → Loki
2. 查询：`{namespace="demo-app", app="demo-app"}`
3. 添加过滤器：`|= "ERROR"` 查找错误日志

### 5.3 配置告警通知（飞书机器人）

1. 飞书群 → 设置 → 群机器人 → 添加机器人 → **自定义机器人**
2. 复制 Webhook URL
3. 创建/编辑 `demo-app/k8s/alertmanager-config.yaml`，填入 Webhook URL
4. 应用配置：

```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt create secret generic alertmanager-config \
  -n monitoring --from-file=alertmanager.yaml=C:\Users\kim\kind-env\demo-app\k8s\alertmanager-config.yaml \
  --dry-run=client -o yaml | wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -f -
```

---

## 六、故障自检流程

### 6.1 集群健康检查

```bash
# 检查所有节点
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes

# 检查核心 Pod（应该在 Running）
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n kube-system

# 检查 ArgoCD
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n argocd

# 检查监控
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n monitoring
```

### 6.2 应用故障排查

```bash
# 查看 Pod 事件
wsl -d Ubuntu kubectl --context kind-ops-mgmt describe pod <pod-name> -n demo-app

# 查看日志
wsl -d Ubuntu kubectl --context kind-ops-mgmt logs <pod-name> -n demo-app --tail=100

# 如果 Pod 重启过，看上一次日志
wsl -d Ubuntu kubectl --context kind-ops-mgmt logs <pod-name> -n demo-app --previous --tail=100

# 查看资源使用
wsl -d Ubuntu kubectl --context kind-ops-mgmt top pod -n demo-app
```

### 6.3 重建组件

**重建 ArgoCD**：
```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt delete namespace argocd
wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

**重建 Prometheus**：
```bash
wsl -d Ubuntu kubectl --context kind-ops-mgmt delete prometheus prometheus -n monitoring
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring -f C:\Users\kim\kind-env\values-prometheus.yaml
```

### 6.4 完整环境重建

```bash
# 删除所有集群
wsl -d Ubuntu kind delete clusters --all

# 一键重建
C:\Users\kim\kind-env\kind-env-start.bat
```

---

## 七、快捷命令汇总

```bash
# 集群操作
wsl -d Ubuntu kind get clusters
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -A

# 上下文切换
wsl -d Ubuntu kubectl config use-context kind-ops-mgmt
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regiona
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regionb

# 查看所有 Helm Release
wsl -d Ubuntu helm list -A

# 查看资源使用
wsl -d Ubuntu kubectl top nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt top pod -n demo-app

# 端口转发（Grafana / Prometheus / ArgoCD）
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-grafana 30300:80
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n argocd port-forward svc/argocd-server 30080:443
```

---

## 八、环境参数速查

| 参数 | 值 |
|------|-----|
| K8s 版本 | v1.27.3 |
| Docker | 28.3.3 |
| kind | v0.20.0 |
| helm | v3.14.0 |
| kubectl | v1.32.2 |
| ArgoCD | http://localhost:30080 |
| Grafana | http://localhost:30300 |
| Prometheus | 端口转发 9090 |
| Loki | 端口转发 3100 |
| Alertmanager | 端口转发 9093 |
| StorageClass | standard (rancher.io/local-path) |
| 示例应用 namespace | demo-app |
| 监控 namespace | monitoring |
| Runner namespace | gitlab-runner |
