# 故障场景与响应手册

## 故障 1：Pod OOMKilled / CrashLoopBackOff

**症状识别**
```
kubectl get pods -n demo-app
NAME                        READY   STATUS          RESTARTS   AGE
demo-app-7f9d8b4c-xk2p9    0/1     OOMKilled       0          30s
demo-app-7f9d8b4c-abc123    1/1     Running         3          2m
```

**诊断步骤**
```bash
# 1. 查看事件
kubectl describe pod <pod-name> -n demo-app

# 2. 查看日志（OOM 前一次）
kubectl logs <pod-name> -n demo-app --previous

# 3. 查看资源限制
kubectl top pod <pod-name> -n demo-app

# 4. Prometheus 告警触发
# → Alertmanager 告警: DemoAppDown
```

**自动响应**
- HPA 触发扩容（当前 2 pods，HPA 范围 2-10）
- Alertmanager → 飞书机器人通知

**手动响应**
```bash
# 快速回滚到上一版本
kubectl rollout undo deployment/demo-app -n demo-app

# 或定位内存泄漏，修改 limits
kubectl patch deployment demo-app -n demo-app \
  --type=merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"demo-app","resources":{"limits":{"memory":"256Mi"}}}]}}}}'
```

---

## 故障 2：Deployment 同步失败（ArgoCD OutOfSync）

**症状识别**
- ArgoCD UI 显示状态为 `OutOfSync` 或 `Sync Error`
- 告警：`ArgoCDApplicationSyncError`

**诊断步骤**
```bash
# 1. ArgoCD CLI 查看详情
argocd app get demo-app

# 2. 查看集群事件
kubectl get events -n demo-app --sort-by='.lastTimestamp'

# 3. 查看具体差异
argocd app diff demo-app
```

**常见原因**
| 原因 | 解决 |
|------|------|
| imagePullBackOff | 检查 Secret / registry 认证 |
| Invalid manifest | 修复 YAML 语法 |
| RBAC 权限不足 | 更新 ClusterRole |
| PVC pending | 检查 StorageClass |
| webhook 拒绝 | 检查 ValidatingWebhook |

**手动响应**
```bash
# 强制同步（忽略差异）
argocd app sync demo-app --force

# 或修复后自动同步
git commit → git push → ArgoCD 自动检测
```

---

## 故障 3：CPU / Memory 资源耗尽

**症状识别**
```
kubectl top nodes
NAME                     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
ops-mgmt-worker         850m         85%    3Gi             90%
```

**自动响应**
- HPA 检测 CPU > 70% → 扩容到 4 pods
- 扩容后若仍高 → 继续扩容（最大 10）
- Prometheus 告警：`DemoAppHighLatency`

**手动响应**
```bash
# 1. 查看实时资源
kubectl top pods -n demo-app --sort-by=memory

# 2. 扩容副本
kubectl scale deployment demo-app -n demo-app --replicas=6

# 3. 限制非核心 Pod（腾出资源）
kubectl cordon <node-name>

# 4. 长期方案：调整 resource limits
kubectl edit deployment demo-app -n demo-app
```

---

## 故障 4：网络不通（Ingress 503）

**症状识别**
```
curl http://demo-app.local/health
curl: (7) Failed to connect to demo-app.local
```

**诊断步骤**
```bash
# 1. 检查 Ingress Controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx <nginx-pod>

# 2. 检查 Service 端点
kubectl get endpoints demo-app-svc -n demo-app

# 3. 检查 Pod 状态
kubectl get pods -n demo-app -l app=demo-app
```

**常见原因**
- Pod 未就绪（readinessProbe 失败）
- Service selector 不匹配
- Ingress 规则配置错误

---

## 故障 5：监控告警风暴

**症状识别**
- 短时间内大量重复告警
- Alertmanager 重复发送通知

**诊断步骤**
```bash
# 1. 查看告警状态
argocd app get prometheus -n monitoring
kubectl get prometheusrule -n monitoring

# 2. 查看 Prometheus 告警规则
kubectl get prometheusrule -n demo-app -o yaml
```

**响应**
```bash
# 静默告警（30 分钟）
kubectl annotate prometheusrule demo-app-alerts -n demo-app \
  prometheusetheus.io/silenced="manual-silence:30m"

# 或 Alertmanager 抑制规则
# 编辑 alertmanager-config secret 调整 group_interval
```

---

## 故障 6：GitLab CI Pipeline 失败

**症状识别**
- GitLab CI/CD → Pipelines 页面显示 red X
- 邮件/Slack 收到 CI 失败通知

**诊断步骤**
1. 打开 GitLab → Project → CI/CD → Pipelines
2. 点击失败 job → 查看日志

**常见失败原因**
| 阶段 | 常见问题 | 解决 |
|------|----------|------|
| build | Docker in Docker 权限 | 确保 privileged runner |
| test | 网络超时 | 检查 runner 网络策略 |
| security-scan | Trivy 高危漏洞 | 必须修复或 allow_failure |
| deploy | Kubeconfig 过期 | 更新 secret |
| deploy | RBAC 权限不足 | runner SA 授权 |

**手动响应**
```bash
# 重试失败 job
gitlab-ci linter --retry-failed

# 或 GitLab UI: Pipelines → Job → Retry
```

---

## 故障 7：数据丢失（Storage）

**症状识别**
```
kubectl get pvc -n demo-app
NAME           STATUS   VOLUME   CAPACITY   ACCESS_MODES
demo-app-pvc   Lost     lost     10Gi       RWO
```

**预防措施**
- 所有配置进 Git（IaC）
- 定时 Volume Snapshot（Velero）
- Prometheus/Loki 使用持久卷

**恢复步骤**
```bash
# 1. 确认 PVC 状态
kubectl describe pvc demo-app-pvc -n demo-app

# 2. 删除并重建 PVC
kubectl delete pvc demo-app-pvc -n demo-app

# 3. Pod 自动重新挂载
kubectl delete pod -n demo-app -l app=demo-app

# 4. 从备份恢复（如有）
velero restore create --from-backup backup-name
```

---

## 故障 8：Kind 集群损坏

**症状识别**
```
wsl -d Ubuntu kind get clusters
(no output or cluster missing)
```

**恢复步骤**
```bash
# 1. 清理残留
wsl -d Ubuntu kind delete clusters --all

# 2. 一键重建
# 双击 kind-env-start.bat
# 或手动：
wsl -d Ubuntu kind create cluster --name ops-mgmt --config kind-ops-mgmt.yaml
wsl -d Ubuntu kind create cluster --name biz-prod-regiona --config kind-biz-prod.yaml
wsl -d Ubuntu kind create cluster --name biz-prod-regionb --config kind-biz-prod.yaml

# 3. 重装 ArgoCD
wsl -d Ubuntu kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. ArgoCD 自动从 Git 恢复所有应用
```

---

## 告警渠道配置

### 飞书机器人 Webhook
```yaml
# Alertmanager receiver 配置
receivers:
  - name: 'feishu-webhook'
    webhook_configs:
      - url: 'https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_HOOK'
        send_resolved: true
```

### Slack Webhook
```yaml
receivers:
  - name: 'slack'
    slack_configs:
      - channel: '#alerts'
        api_url: 'https://hooks.slack.com/services/XXX'
        send_resolved: true
```

---

## MTTD / MTTR 目标

| 故障类型 | MTTD（检测时间） | MTTR（恢复时间） |
|----------|-----------------|-----------------|
| Pod Down | < 1 分钟 | < 5 分钟 |
| 同步失败 | < 2 分钟 | < 10 分钟 |
| 资源耗尽 | < 2 分钟 | < 5 分钟 |
| 网络故障 | < 2 分钟 | < 15 分钟 |
| 数据丢失 | < 5 分钟 | < 30 分钟 |
