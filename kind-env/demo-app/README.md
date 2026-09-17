# 示例应用 demo-app

演示用 Node.js + Python 微服务，用于端到端 CI/CD 演示。

## 端点

| 端点 | 用途 |
|------|------|
| GET / | 应用信息 |
| GET /health | 存活探针 (Liveness) |
| GET /ready | 就绪探针 (Readiness) |
| GET /metrics | Prometheus 指标 |

## 部署

### 前提
- kubectl 连接 kind-ops-mgmt
- Sealed Secrets 公钥已获取

### 加密敏感配置
```bash
# 获取公钥
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key=active \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/cert.pem

# 加密
kubeseal --cert=/tmp/cert.pem --format=yaml < secret.yaml > sealed-secret.yaml
```

### 手动部署
```bash
kubectl create namespace demo-app
sed 's/__IMAGE_TAG__/your-image:tag/g' k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/hpa.yaml
```

## GitLab CI 流水线

- **main 分支**：构建 → 安全扫描 → 发布 production（需手动确认）
- **develop 分支**：构建 → 测试 → 发布 staging
- 所有任务运行在 GitLab Kubernetes Runner
