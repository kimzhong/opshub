# Kind 多集群环境 - 完整使用手册

本手册涵盖环境启动、服务访问、CI/CD 演示、GitOps 演示和故障排查。

---

## 一、环境启动

双击 `C:\Users\kim\kind-env\kind-env-start.bat`（管理员权限），等待看到 `kind clusters ready`。

验证集群状态：
- `wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes`
- `wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n monitoring`
- `wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n argocd`

---

## 二、服务访问

### ArgoCD（GitOps）

- 地址：http://localhost:30080
- 用户名：admin
- 密码：wG0YYYIbLXX31dVf

左侧菜单点 Applications 查看所有已同步应用。点击应用可手动 Sync 或 Rollback。

### Grafana（监控面板）

- 地址：http://localhost:30300
- 用户名：admin
- 密码：admin123

操作路径：
- Dashboards - Browse - 搜索 Kubernetes 查看集群仪表盘
- Explore - 选择 Prometheus - 查询指标
- Explore - 选择 Loki - 查询日志

添加 Loki 数据源：Settings - Data Sources - Add Loki，URL 填 http://loki-gateway.monitoring.svc.cluster.local，添加 HTTP Header：X-Scope-OrgID = foo

### Prometheus（指标查询）

端口转发：wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090

浏览器访问：http://localhost:9090，顶部 Alerts 查看告警规则。

常用查询：
- up 查 Pod 在线状态
- container_cpu_usage_seconds_total 查 CPU
- container_memory_working_set_bytes 查内存

### Alertmanager（告警管理）

端口转发：wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-alertmanager 9093:9093

浏览器访问：http://localhost:9093

---

## 三、CI/CD 发布流程（端到端演示）

### Step 1：推送代码到 GitLab

代码在 C:\Users\kim\kind-env\demo-app\，包含 Python 服务、Dockerfile、K8s 部署配置、GitLab CI 流水线。

创建 GitLab 项目后推送代码：
- git init
- git remote add origin https://gitlab.com/你的用户名/demo-app.git
- git add . && git commit -m "Initial commit"
- git push -u origin main

### Step 2：配置 CI/CD Variables

GitLab 项目 - Settings - CI/CD - Variables，添加：

KUBECONFIG_DATA：base64 编码的 kubeconfig，生成命令：
wsl -d Ubuntu kubectl --context kind-ops-mgmt config view --raw | base64 -w 0

CI_REGISTRY_USER：GitLab 用户名
CI_REGISTRY_PASSWORD：GitLab 访问令牌（Settings - Access Tokens - 创建带 read_registry 权限的令牌）

### Step 3：注册 GitLab Runner

GitLab 项目 - Settings - CI/CD - Runners，复制 Registration Token，执行：
helm upgrade --install gitlab-runner gitlab/gitlab-runner --namespace gitlab-runner --set gitlabUrl=https://gitlab.com --set runnerRegistrationToken="你的TOKEN" --set runners.lockBuiltIn=false --set runners.privileged=true --set runners.tags="kubernetes,kind" --set rbac.create=true --set rbac.clusterWideAccess=true --wait --timeout 10m

### Step 4：触发 Pipeline

GitLab - CI/CD - Pipelines - Run pipeline - 选择 main 分支，观察流水线：build（构建镜像）-> test-unit（单元测试）-> security-scan（安全扫描）-> deploy-production（手动触发）

### Step 5：手动触发生产部署

Pipeline 到达 deploy-production 阶段时，点击 Play 按钮，Confirm，绿色表示成功。

### Step 6：验证部署

wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n demo-app
wsl -d Ubuntu kubectl --context kind-ops-mgmt get svc -n demo-app
wsl -d Ubuntu kubectl --context kind-ops-mgmt get hpa -n demo-app

---

## 四、GitOps 演示（ArgoCD 自动同步）

### 创建 Application

修改 demo-app/argocd/app.yaml 中的仓库地址，然后执行：
wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -n argocd -f C:\Users\kim\kind-env\demo-app\argocd\app.yaml

### 查看同步状态

ArgoCD UI - Applications - 点击 demo-app，可以看到 HEALTH（健康状态）、SYNC（同步状态）、MANIFEST DETAILS（实际部署的资源）。

### GitOps 发布演示

修改 k8s/deployment.yaml 中副本数，git commit && git push，ArgoCD 自动检测变更并同步到集群，无需手动操作。UI 上状态从 OutOfSync 变为 Synced。

### 回滚

ArgoCD UI - Application - History - 选择历史版本 - Rollback，1 分钟内完成。

---

## 五、配置告警通知（飞书机器人）

### Step 1：创建飞书群机器人

飞书群 - 设置 - 群机器人 - 添加机器人 - 自定义机器人，复制 Webhook URL。

### Step 2：更新 Alertmanager 配置

编辑 demo-app/k8s/alertmanager-config.yaml，将 YOUR_HOOK 替换为实际 Webhook URL。

### Step 3：应用配置

wsl -d Ubuntu kubectl --context kind-ops-mgmt create secret generic alertmanager-config -n monitoring --from-file=alertmanager.yaml=C:\Users\kim\kind-env\demo-app\k8s\alertmanager-config.yaml --dry-run=client -o yaml | wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -f -

---

## 六、故障自检

### 集群健康检查

wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n kube-system
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n argocd
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n monitoring

### 应用故障排查

kubectl describe pod -n demo-app（查看事件）
kubectl logs -n demo-app（查看日志）
kubectl logs -n demo-app --previous（Pod 重启过？看上一次日志）
kubectl top pod -n demo-app（查看资源使用）
kubectl get events -n demo-app --sort-by=.lastTimestamp（集群事件）

### 重建 ArgoCD

wsl -d Ubuntu kubectl --context kind-ops-mgmt delete namespace argocd
wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

### 完整环境重建

wsl -d Ubuntu kind delete clusters --all
然后双击 kind-env-start.bat

---

## 七、快捷命令汇总

集群状态：wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
上下文切换：wsl -d Ubuntu kubectl config use-context kind-ops-mgmt
查看所有 Pod：wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -A
Grafana 端口转发：kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-grafana 30300:80
Prometheus 端口转发：kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090

---

## 八、环境参数

K8s v1.27.3 / Docker 28.3.3 / kind v0.20.0 / helm v3.14.0 / kubectl v1.32.2

ArgoCD：http://localhost:30080（admin / wG0YYYIbLXX31dVf）
Grafana：http://localhost:30300（admin / admin123）
Prometheus：端口转发 9090
Loki：端口转发 3100
StorageClass：standard（rancher.io/local-path）
