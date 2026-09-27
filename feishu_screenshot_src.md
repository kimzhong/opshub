Kind 多集群环境使用手册（截图版）

Kind Multi-Cluster Environment — User Manual (with Screenshots Guide)

  DevOps Demo Scenario &bull; End-to-End: CI/CD &rarr; GitOps &rarr; Observability &rarr; Incident Response
  &nbsp;|&nbsp;
  Cluster Online

Architecture Overview

[Architecture Diagram — see HTML version]

ComponentNamespaceAccess URLCredentials
ArgoCDargocdhttp://localhost:30080admin / wG0YYYIbLXX31dVf
Grafanamonitoringhttp://localhost:30300admin / admin123
Prometheusmonitoringport-forward 9090--
Lokimonitoringport-forward 3100--
Alertmanagermonitoringport-forward 9093--

1. Environment Startup

1
First Start — Double-click C:\Users\kim\kind-env\kind-env-start.bat (run as admin recommended)
Wait 2-3 minutes until you see kind clusters ready.

2
Verify Cluster Status:
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n monitoring
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n argocd

## [SCREENSHOT] Open terminal, run kubectl get nodes, screenshot the 4-node output (1xCP + 3xWorker).
## [SCREENSHOT] Run kubectl get pods -n monitoring, screenshot the running pods list.

2. Service Access Guide

2.1 ArgoCD (GitOps Dashboard)

## [SCREENSHOT] Steps:
1. Browser: http://localhost:30080
2. Username: admin, Password: wG0YYYIbLXX31dVf
3. Screenshot the logged-in Applications page (shows demo-app)
4. Click demo-app -> Sync -> Screenshot the Sync status page
5. Click History -> Screenshot the revision history list

# View app list
Applications -> left sidebar

# Manual sync
Click app name -> Sync -> Synchronize

# View diff
Diff tab

# Rollback
History -> select revision -> Rollback

2.2 Grafana (Monitoring + Logs)

## [SCREENSHOT] Steps:
1. Open http://localhost:30300, login admin/admin123
2. Dashboards -> Browse -> search "Kubernetes" -> open Pod dashboard
3. Explore -> Prometheus -> type up -> Run query -> screenshot results
4. Explore -> Loki -> type {namespace="monitoring"} -> screenshot log view

# Prometheus query examples
up{job="demo-app"}                       # Pod status
rate(http_requests_total[5m])           # QPS
container_cpu_usage_seconds_total        # CPU usage
container_memory_working_set_bytes      # Memory usage
kube_pod_restart_total{namespace="demo-app"}  # Restarts

# Loki query
{namespace="demo-app"}                   # App logs
{namespace="demo-app"} |= "ERROR"      # Error logs

2.3 Prometheus + Alertmanager

## [SCREENSHOT] Run the port-forward command, visit localhost:9090, screenshot the Alerts page.

# Prometheus
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/prometheus-prometheus 9090:9090
# Browser: http://localhost:9090

# Alertmanager
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/prometheus-alertmanager 9093:9093
# Browser: http://localhost:9093

3. End-to-End CI/CD Pipeline

## [SCREENSHOT] Full pipeline screenshots (requires your GitLab UI):
1. GitLab -> CI/CD -> Pipelines -> open a successful pipeline run
2. Screenshot the full pipeline view (build -> test -> scan -> deploy stages)
3. Click a job -> screenshot the job log output
4. Deploy production stage -> screenshot the "Play" button

1
Create a GitLab project and push demo-app code to https://gitlab.com/your-username/demo-app.git

2
Configure CI/CD Variables (Settings -> CI/CD -> Variables -> Add variable):

VariableDescription
KUBECONFIG_DATAbase64-encoded ops-mgmt kubeconfig
CI_REGISTRY_USERYour GitLab username
CI_REGISTRY_PASSWORDGitLab Access Token (with read_registry scope)

# Generate KUBECONFIG_DATA
wsl -d Ubuntu kubectl --context kind-ops-mgmt config view --raw | base64 -w 0

3
Trigger Pipeline: CI/CD -> Pipelines -> Run pipeline (branch: main)

4
Pipeline stages: build -> test-unit -> security-scan -> deploy-production (requires manual trigger)

5
Verify deployment:
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n demo-app
wsl -d Ubuntu kubectl --context kind-ops-mgmt get hpa -n demo-app
wsl -d Ubuntu kubectl --context kind-ops-mgmt top pod -n demo-app

4. GitOps Demo (ArgoCD)

## [SCREENSHOT] Steps:
1. ArgoCD UI -> Applications -> screenshot full app list (Health/Sync status)
2. Click demo-app -> Sync -> screenshot the Diff view (shows Git vs cluster diff)
3. History tab -> screenshot revision history
4. Modify Git code -> git push -> wait 3 min -> screenshot ArgoCD auto-sync

# Deploy ArgoCD Application
wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -n argocd \
  -f C:\Users\kim\kind-env\demo-app\argocd\app.yaml

# View sync status
argocd app list
argocd app get demo-app
argocd app sync demo-app    # Manual trigger

# Note: Replace repo URL in app.yaml with your actual GitLab repo

GitOps Rollback Demo Flow:
1Modify deployment.yaml image version in Git -> git push
2ArgoCD auto-detects change (default 3-min poll)
3Auto-syncs to cluster (no manual action needed)
4To rollback: ArgoCD -> demo-app -> History -> select revision -> Rollback

5. Observability Setup

5.1 Add Loki Data Source

## [SCREENSHOT] Grafana -> Configuration -> Data Sources -> Add data source -> Loki -> fill URL and X-Scope-OrgID header.

Grafana -> Configuration -> Data Sources -> Add data source -> Loki

URL:     http://loki-gateway.monitoring.svc.cluster.local
Header:  X-Scope-OrgID = foo

Click Save & test

5.2 Configure Feishu Alert Notifications
Requires: Feishu group bot Webhook URL (Feishu group -> Settings -> Group bots -> Add custom bot)
# Create alert Secret
kubectl --context kind-ops-mgmt create secret generic alertmanager-config \
  -n monitoring --from-file=alertmanager.yaml=./k8s/alertmanager-config.yaml

6. Incident Response

## [SCREENSHOT] Run each troubleshooting command and screenshot terminal output (highlight ERROR/WARNING lines).

SymptomCommand
Pod not Runningkubectl describe pod &lt;name&gt; -n &lt;ns&gt;
App unreachablekubectl logs &lt;pod&gt; -n demo-app --tail=50
Pod crash-loopingkubectl logs &lt;pod&gt; -n demo-app --previous
Resource pressurekubectl top pod -n demo-app
Rebuild ArgoCDkubectl delete namespace argocd && kubectl apply -n argocd -f &lt;url&gt;
Rebuild monitoringhelm upgrade --install prometheus ... -f values-prometheus.yaml

# Full environment rebuild
wsl -d Ubuntu kind delete clusters --all
C:\Users\kim\kind-env\kind-env-start.bat

7. Quick Reference

MonitoringNS: monitoringActive
ArgoCDNS: argocdActive
GitLab RunnerNS: gitlab-runnerPending Token
LokiNS: monitoringActive
Sealed SecretsNS: kube-systemActive

# Cluster ops
wsl -d Ubuntu kind get clusters
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -A

# Context switching
wsl -d Ubuntu kubectl config use-context kind-ops-mgmt
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regiona
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regionb

# Port forwards
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \
  port-forward svc/prometheus-grafana 30300:80
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n argocd \
  port-forward svc/argocd-server 30080:443

# Resource usage
wsl -d Ubuntu helm list -A
wsl -d Ubuntu kubectl top nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt top pod -n demo-app

ParameterValue
K8s Versionv1.27.3
ArgoCD UIhttp://localhost:30080
Grafanahttp://localhost:30300
ArgoCD PasswordwG0YYYIbLXX31dVf
Grafana Passwordadmin / admin123
StorageClassstandard (rancher.io/local-path)

Feishu Docs (pushed):
User Manual (KyfgdKymPokFgzxT6Ljc3auGnpg)
Fault Scenarios (CNwudFGMnocYvRxjLngcFGaYnFh)