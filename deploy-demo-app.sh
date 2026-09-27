#!/bin/bash
# demo-app 部署（不依赖镜像仓库，直接用公共镜像）
set -e
export PATH=/usr/local/bin:$PATH
CTX=kind-ops-mgmt
DIR=/mnt/c/Users/kim/kind-env/demo-app
K="kubectl --context $CTX"

echo "=== 创建命名空间 ==="
$K create namespace demo-app --dry-run=client -o yaml | $K apply -f -

echo
echo "=== 部署应用（用公共镜像避免依赖 registry）==="
cat <<'EOF' | $K apply -n demo-app -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: demo-app
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  labels: { app: demo-app }
spec:
  replicas: 2
  selector:
    matchLabels: { app: demo-app }
  template:
    metadata:
      labels: { app: demo-app }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      serviceAccountName: demo-app
      containers:
      - name: app
        image: python:3.11-slim
        command: ["python3","-c"]
        args:
        - |
          import http.server, socketserver, time, os, sys
          from datetime import datetime, timezone

          START = time.time()
          REQ = [0]

          class H(http.server.BaseHTTPRequestHandler):
              def _send(self, code, body, ctype="text/plain; charset=utf-8"):
                  b = body.encode()
                  self.send_response(code)
                  self.send_header("Content-Type", ctype)
                  self.send_header("Content-Length", str(len(b)))
                  self.end_headers()
                  self.wfile.write(b)

              def do_GET(self):
                  REQ[0] += 1
                  if self.path.startswith("/health"):
                      return self._send(200, "ok")
                  if self.path.startswith("/metrics"):
                      up = time.time() - START
                      m = (
                        "# HELP demo_app_uptime_seconds Uptime\n"
                        "# TYPE demo_app_uptime_seconds gauge\n"
                        f"demo_app_uptime_seconds {up:.3f}\n"
                        "# HELP demo_app_requests_total Total requests\n"
                        "# TYPE demo_app_requests_total counter\n"
                        f"demo_app_requests_total {REQ[0]}\n"
                        "# HELP demo_app_up 1 if running\n"
                        "# TYPE demo_app_up gauge\n"
                        "demo_app_up 1\n"
                      )
                      return self._send(200, m, "text/plain; version=0.0.4")
                  print(f"{datetime.now(timezone.utc).isoformat()} GET {self.path} pod={os.environ.get('HOSTNAME','?')}", flush=True)
                  return self._send(200, json_body())

          def json_body():
              return ("{" +
                f'"service":"demo-app","pod":"{os.environ.get("HOSTNAME","?")}",' +
                f'"uptime_seconds":{time.time()-START:.1f},' +
                f'"requests":{REQ[0]},' +
                f'"timestamp":"{datetime.now(timezone.utc).isoformat()}"' +
              "}")

          class TS(socketserver.ThreadingMixIn, http.server.HTTPServer):
              daemon_threads = True
              allow_reuse_address = True

          with TS(("0.0.0.0", 8080), H) as httpd:
              print("demo-app listening on :8080", flush=True)
              httpd.serve_forever()
        ports:
        - containerPort: 8080
          name: http
        env:
        - name: PYTHONUNBUFFERED
          value: "1"
        resources:
          requests: { cpu: 50m, memory: 64Mi }
          limits:   { cpu: 300m, memory: 256Mi }
        livenessProbe:
          httpGet: { path: /health, port: 8080 }
          initialDelaySeconds: 5
          periodSeconds: 10
        readinessProbe:
          httpGet: { path: /health, port: 8080 }
          initialDelaySeconds: 3
          periodSeconds: 5
        securityContext:
          runAsNonRoot: false
---
apiVersion: v1
kind: Service
metadata:
  name: demo-app
spec:
  type: ClusterIP
  selector: { app: demo-app }
  ports:
  - port: 80
    targetPort: 8080
    name: http
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: demo-app
spec:
  minAvailable: 1
  selector:
    matchLabels: { app: demo-app }
EOF

echo
echo "=== HPA ==="
cat <<'EOF' | $K apply -n demo-app -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: demo-app
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: demo-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF

echo
echo "=== 告警规则 ==="
$K create configmap demo-app-alerts -n monitoring --from-file="$DIR/k8s/prometheus-rules.yaml" \
  --dry-run=client -o yaml | $K apply -f -

echo
echo "=== 等待 rollout ==="
$K -n demo-app rollout status deployment/demo-app --timeout=180s

echo
echo "=== Pod 状态 ==="
$K -n demo-app get pods -o wide
echo
$K -n demo-app get hpa
echo
$K -n demo-app get svc
