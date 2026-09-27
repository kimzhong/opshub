# -*- coding: utf-8 -*-
"""
生成带架构图和截图指引的 Kind 多集群环境使用手册 HTML
"""
import subprocess, json, re

# ── 1. 从集群拉取真实数据 ──────────────────────────────────────────────────
def kubectx(ctx, ns=None, extra=""):
    cmd = f"kubectl --context {ctx}"
    if ns: cmd += f" -n {ns}"
    if extra: cmd += f" {extra}"
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.stdout.strip(), r.stderr.strip()

# 节点
nodes_out, _ = kubectx("kind-ops-mgmt", extra="-o wide")
nodes = [l for l in nodes_out.splitlines() if l and "NAME" not in l]

# Pod 统计
def count_pods(ctx, ns):
    out, _ = kubectx(ctx, ns, extra="--no-headers")
    lines = [l for l in out.splitlines() if l.strip()]
    ready = sum(1 for l in lines if re.search(r'\d+/\d+\s+Running', l))
    return len(lines), ready

components = {}
for ns, label in [("monitoring","监控栈"), ("argocd","ArgoCD"), ("gitlab-runner","GitLab Runner")]:
    total, ready = count_pods("kind-ops-mgmt", ns)
    components[label] = {"ns": ns, "total": total, "ready": ready}

# ArgoCD App
argocd_apps, _ = kubectx("kind-ops-mgmt", "argocd", extra="get application -o name")
app_list = [l.replace("application.argoproj.io/","") for l in argocd_apps.splitlines() if l]

# ── 2. 构建 HTML ─────────────────────────────────────────────────────────────
html = """<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kind 多集群环境使用手册（带截图版）</title>
<style>
  :root{--bg:#0f1117;--card:#1a1d27;--border:#2d3143;--text:#e2e8f0;--muted:#8892a4;--accent:#60a5fa;--green:#4ade80;--yellow:#fbbf24;--red:#f87171;--purple:#a78bfa}
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;line-height:1.7;font-size:15px}
  .wrap{max-width:1100px;margin:0 auto;padding:2rem 1.5rem}

  /* ── 导航侧栏 ── */
  nav{position:sticky;top:0;z-index:100;background:var(--bg);border-bottom:1px solid var(--border);padding:.6rem 0;margin-bottom:2rem}
  nav .wrap{display:flex;gap:1.5rem;align-items:center;flex-wrap:wrap}
  nav a{color:var(--muted);text-decoration:none;font-size:.9rem;transition:color .2s}
  nav a:hover{color:var(--accent)}
  nav .logo{font-weight:700;color:var(--accent);font-size:1.1rem}

  h1{font-size:1.9rem;font-weight:800;background:linear-gradient(135deg,#60a5fa,#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent;margin-bottom:.3rem}
  h2{font-size:1.35rem;font-weight:700;color:var(--accent);margin:2.5rem 0 1rem;border-left:4px solid var(--accent);padding-left:.75rem}
  h3{font-size:1.1rem;font-weight:600;color:var(--yellow);margin:1.5rem 0 .6rem}
  p{margin-bottom:.8rem;color:var(--text)}
  a{color:var(--accent);text-decoration:none}
  a:hover{text-decoration:underline}

  /* ── 组件卡片 ── */
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:1rem;margin:1rem 0}
  .card{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.2rem;transition:border-color .2s}
  .card:hover{border-color:var(--accent)}
  .card-title{display:flex;align-items:center;gap:.5rem;font-size:1.05rem;font-weight:700;margin-bottom:.5rem}
  .card-title .dot{width:10px;height:10px;border-radius:50%;background:var(--green)}
  .card-title .dot.warn{background:var(--yellow)}
  .card-title .dot.err{background:var(--red)}
  .card-meta{font-size:.85rem;color:var(--muted)}
  .card-meta span{margin-right:1rem}
  .badge{display:inline-block;background:var(--accent);color:#000;font-size:.75rem;font-weight:700;border-radius:20px;padding:.1rem .6rem;margin-top:.4rem}
  .badge.green{background:var(--green);color:#000}
  .badge.yellow{background:var(--yellow);color:#000}

  /* ── 步骤框 ── */
  .step{border:1px solid var(--border);border-radius:10px;padding:1rem 1.2rem;margin:1rem 0;background:var(--card);position:relative}
  .step-num{position:absolute;top:-12px;left:16px;background:var(--accent);color:#000;font-weight:800;font-size:.8rem;border-radius:20px;padding:.1rem .7rem}
  .step p:last-child{margin-bottom:0}

  /* ── 代码块 ── */
  pre{background:#000;border:1px solid var(--border);border-radius:8px;padding:1rem;overflow-x:auto;font-size:.88rem;line-height:1.6;margin:.8rem 0;color:#e2e8f0}
  code{font-family:'Cascadia Code','Fira Code',monospace;font-size:.88em;background:#000;padding:.15rem .4rem;border-radius:4px;color:#a5d6ff}
  pre code{background:none;padding:0;color:inherit}
  .cmd{color:#4ade80}
  .comment{color:#6b7280;font-style:italic}

  /* ── 架构图 ── */
  .arch{background:var(--card);border:1px solid var(--border);border-radius:12px;padding:1.5rem;margin:1.5rem 0;text-align:center;overflow-x:auto}
  .arch svg{width:100%;max-width:900px}

  /* ── 截图指引框 ── */
  .shot{background:#1c1f2e;border:2px dashed var(--purple);border-radius:10px;padding:1rem 1.2rem;margin:1rem 0;position:relative}
  .shot::before{content:"📸 截图指引";position:absolute;top:-11px;left:14px;background:#1c1f2e;color:var(--purple);font-weight:700;font-size:.8rem;padding:0 .5rem}
  .shot p{margin:.3rem 0}

  /* ── 表格 ── */
  table{width:100%;border-collapse:collapse;margin:1rem 0;font-size:.9rem}
  th{background:var(--card);color:var(--accent);padding:.7rem 1rem;text-align:left;border-bottom:2px solid var(--border);font-weight:700}
  td{padding:.6rem 1rem;border-bottom:1px solid var(--border)}
  tr:hover td{background:#1a1d27}

  /* ── 告警框 ── */
  .warn{background:#2a2000;border:1px solid var(--yellow);border-radius:8px;padding:.8rem 1rem;margin:.8rem 0;color:var(--yellow)}
  .tip{background:#0a1e0a;border:1px solid var(--green);border-radius:8px;padding:.8rem 1rem;margin:.8rem 0;color:var(--green)}

  /* ── 状态指示 ── */
  .status{display:inline-flex;align-items:center;gap:.4rem;font-size:.85rem}
  .status .s-dot{width:8px;height:8px;border-radius:50%;display:inline-block}
  .s-ok{background:var(--green)}.s-warn{background:var(--yellow)}.s-err{background:var(--red)}

  hr{border:none;border-top:1px solid var(--border);margin:2rem 0}

  /* ── 动画 ── */
  @keyframes fadeUp{from{opacity:0;transform:translateY(20px)}to{opacity:1;transform:translateY(0)}}
  .card,.step,.shot{animation:fadeUp .4s ease both}
  .card:nth-child(2){animation-delay:.05s}.card:nth-child(3){animation-delay:.1s}.card:nth-child(4){animation-delay:.15s}
  .card:nth-child(5){animation-delay:.2s}.card:nth-child(6){animation-delay:.25s}
</style>
</head>
<body>
<nav><div class="wrap"><span class="logo">☸ Kind 多集群</span>
<a href="#start">环境启动</a><a href="#access">服务访问</a><a href="#cicd">CI/CD</a>
<a href="#gitops">GitOps</a><a href="#observe">可观测</a><a href="#fault">故障处理</a>
<a href="#cheatsheet">速查</a>
</div></nav>

<div class="wrap">

<!-- ══════════════════════════════════════════════════════════════ -->
<h1 id="top">Kind 多集群环境 — 使用手册</h1>
<p style="color:var(--muted);font-size:.95rem">面向 DevOps 演示场景，端到端覆盖：环境启动 → CI/CD → GitOps → 可观测 → 故障响应 &nbsp;|&nbsp;
<span class="status"><span class="s-dot s-ok"></span>集群在线</span></p>
<hr>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="arch">🏗️ 架构总览</h2>
<div class="arch">
<svg viewBox="0 0 900 520" xmlns="http://www.w3.org/2000/svg">
  <!-- 背景 -->
  <rect width="900" height="520" fill="#1a1d27" rx="12"/>
  <text x="450" y="30" text-anchor="middle" fill="#60a5fa" font-size="16" font-weight="bold" font-family="Segoe UI">Kind 多集群架构图</text>

  <!-- 开发机 -->
  <rect x="20" y="60" width="110" height="50" rx="8" fill="#2d3143" stroke="#60a5fa" stroke-width="2"/>
  <text x="75" y="90" text-anchor="middle" fill="#e2e8f0" font-size="13" font-family="Segoe UI">💻 开发机</text>

  <!-- GitLab -->
  <rect x="170" y="60" width="120" height="50" rx="8" fill="#2d3143" stroke="#fbbf24" stroke-width="2"/>
  <text x="230" y="90" text-anchor="middle" fill="#fbbf24" font-size="13" font-family="Segoe UI">🌐 gitlab.com</text>

  <!-- 箭头 dev→gitlab -->
  <line x1="130" y1="85" x2="165" y2="85" stroke="#60a5fa" stroke-width="2" marker-end="url(#arrow)"/>
  <text x="148" y="78" text-anchor="middle" fill="#8892a4" font-size="10">git push</text>

  <!-- Runner box -->
  <rect x="330" y="55" width="140" height="60" rx="8" fill="#2d3143" stroke="#a78bfa" stroke-width="2"/>
  <text x="400" y="80" text-anchor="middle" fill="#a78bfa" font-size="12" font-family="Segoe UI">🏃 GitLab Runner</text>
  <text x="400" y="97" text-anchor="middle" fill="#8892a4" font-size="10">kind-k8s cluster</text>
  <line x1="290" y1="85" x2="325" y2="85" stroke="#a78bfa" stroke-width="2" marker-end="url(#arrow)"/>
  <text x="308" y="78" text-anchor="middle" fill="#8892a4" font-size="10">CI job</text>

  <!-- ops-mgmt cluster -->
  <rect x="20" y="145" width="260" height="330" rx="12" fill="#0d1017" stroke="#60a5fa" stroke-width="2"/>
  <text x="150" y="170" text-anchor="middle" fill="#60a5fa" font-size="13" font-weight="bold" font-family="Segoe UI">⚙️ ops-mgmt (管理集群)</text>
  <text x="150" y="186" text-anchor="middle" fill="#8892a4" font-size="10">K8s v1.27.3 · 1×CP + 3×Worker</text>

  <!-- ArgoCD -->
  <rect x="35" y="200" width="100" height="45" rx="6" fill="#2d3143" stroke="#4ade80" stroke-width="1.5"/>
  <text x="85" y="227" text-anchor="middle" fill="#4ade80" font-size="11">ArgoCD</text>

  <!-- Prometheus stack -->
  <rect x="145" y="200" width="120" height="45" rx="6" fill="#2d3143" stroke="#fbbf24" stroke-width="1.5"/>
  <text x="205" y="220" text-anchor="middle" fill="#fbbf24" font-size="11">Prometheus</text>
  <text x="205" y="234" text-anchor="middle" fill="#8892a4" font-size="9">Grafana · Loki</text>

  <!-- Sealed Secrets -->
  <rect x="35" y="255" width="230" height="40" rx="6" fill="#2d3143" stroke="#f87171" stroke-width="1.5"/>
  <text x="150" y="280" text-anchor="middle" fill="#f87171" font-size="11">🔐 Sealed Secrets</text>

  <!-- GitLab Runner in cluster -->
  <rect x="35" y="305" width="230" height="40" rx="6" fill="#2d3143" stroke="#a78bfa" stroke-width="1.5"/>
  <text x="150" y="330" text-anchor="middle" fill="#a78bfa" font-size="11">🏃 GitLab Runner (registered)</text>

  <!-- Loki -->
  <rect x="35" y="355" width="230" height="40" rx="6" fill="#2d3143" stroke="#60a5fa" stroke-width="1.5"/>
  <text x="150" y="380" text-anchor="middle" fill="#60a5fa" font-size="11">📋 Loki 日志聚合</text>

  <!-- Alertmanager -->
  <rect x="35" y="405" width="230" height="40" rx="6" fill="#2d3143" stroke="#fbbf24" stroke-width="1.5"/>
  <text x="150" y="430" text-anchor="middle" fill="#fbbf24" font-size="11">🔔 Alertmanager</text>

  <!-- biz-prod-a -->
  <rect x="300" y="145" width="200" height="140" rx="12" fill="#0d1017" stroke="#4ade80" stroke-width="2"/>
  <text x="400" y="170" text-anchor="middle" fill="#4ade80" font-size="13" font-weight="bold" font-family="Segoe UI">🌍 biz-prod-regiona</text>
  <text x="400" y="186" text-anchor="middle" fill="#8892a4" font-size="10">K8s v1.27.3 · 1×CP + 2×Worker</text>
  <rect x="315" y="200" width="170" height="35" rx="6" fill="#2d3143" stroke="#4ade80" stroke-width="1"/>
  <text x="400" y="222" text-anchor="middle" fill="#4ade80" font-size="11">☸ Worker Pods</text>
  <text x="400" y="250" text-anchor="middle" fill="#8892a4" font-size="10">生产级应用负载</text>
  <text x="400" y="266" text-anchor="middle" fill="#8892a4" font-size="10">HPA 自动扩缩容</text>

  <!-- biz-prod-b -->
  <rect x="520" y="145" width="200" height="140" rx="12" fill="#0d1017" stroke="#4ade80" stroke-width="2"/>
  <text x="620" y="170" text-anchor="middle" fill="#4ade80" font-size="13" font-weight="bold" font-family="Segoe UI">🌍 biz-prod-regionb</text>
  <text x="620" y="186" text-anchor="middle" fill="#8892a4" font-size="10">K8s v1.27.3 · 1×CP + 2×Worker</text>
  <rect x="535" y="200" width="170" height="35" rx="6" fill="#2d3143" stroke="#4ade80" stroke-width="1"/>
  <text x="620" y="222" text-anchor="middle" fill="#4ade80" font-size="11">☸ Worker Pods</text>
  <text x="620" y="250" text-anchor="middle" fill="#8892a4" font-size="10">生产级应用负载</text>
  <text x="620" y="266" text-anchor="middle" fill="#8892a4" font-size="10">跨 Region 灾备</text>

  <!-- ArgoCD sync arrows -->
  <line x1="135" y1="222" x2="300" y2="200" stroke="#4ade80" stroke-width="1.5" stroke-dasharray="5,3" marker-end="url(#arrow2)"/>
  <line x1="135" y1="222" x2="520" y2="200" stroke="#4ade80" stroke-width="1.5" stroke-dasharray="5,3" marker-end="url(#arrow2)"/>
  <text x="220" y="205" text-anchor="middle" fill="#4ade80" font-size="10">GitOps Sync</text>

  <!-- 飞书 -->
  <rect x="740" y="60" width="140" height="50" rx="8" fill="#2d3143" stroke="#60a5fa" stroke-width="2"/>
  <text x="810" y="90" text-anchor="middle" fill="#60a5fa" font-size="13" font-family="Segoe UI">📮 飞书文档</text>

  <!-- 告警→飞书 -->
  <line x1="150" y1="425" x2="810" y2="85" stroke="#fbbf24" stroke-width="1.5" stroke-dasharray="5,3"/>
  <text x="480" y="250" text-anchor="middle" fill="#fbbf24" font-size="10">告警通知</text>

  <!-- Runner→Biz -->
  <line x1="400" y1="115" x2="400" y2="145" stroke="#a78bfa" stroke-width="1.5"/>
  <line x1="200" y1="75" x2="400" y2="75" stroke="#a78bfa" stroke-width="1.5"/>
  <line x1="400" y1="75" x2="400" y2="115" stroke="#a78bfa" stroke-width="1.5"/>

  <!-- Legends -->
  <text x="750" y="170" text-anchor="middle" fill="#8892a4" font-size="11" font-weight="bold">图例</text>
  <line x1="750" y1="190" x2="780" y2="190" stroke="#4ade80" stroke-width="2"/><text x="790" y="194" fill="#4ade80" font-size="10">GitOps 同步</text>
  <line x1="750" y1="210" x2="780" y2="210" stroke="#60a5fa" stroke-width="2" stroke-dasharray="4,2"/><text x="790" y="214" fill="#60a5fa" font-size="10">CI/CD 流水线</text>
  <line x1="750" y1="230" x2="780" y2="230" stroke="#fbbf24" stroke-width="2" stroke-dasharray="4,2"/><text x="790" y="234" fill="#fbbf24" font-size="10">监控/告警</text>

  <!-- Defs -->
  <defs>
    <marker id="arrow" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#60a5fa"/></marker>
    <marker id="arrow2" markerWidth="10" markerHeight="10" refX="9" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#4ade80"/></marker>
  </defs>
</svg>
</div>

<table>
<tr><th>组件</th><th>Namespace</th><th>访问地址</th><th>凭证</th></tr>
<tr><td>ArgoCD</td><td>argocd</td><td><a href="http://localhost:30080">http://localhost:30080</a></td><td>admin / wG0YYYIbLXX31dVf</td></tr>
<tr><td>Grafana</td><td>monitoring</td><td><a href="http://localhost:30300">http://localhost:30300</a></td><td>admin / admin123</td></tr>
<tr><td>Prometheus</td><td>monitoring</td><td>端口转发 9090</td><td>—</td></tr>
<tr><td>Loki</td><td>monitoring</td><td>端口转发 3100</td><td>—</td></tr>
<tr><td>Alertmanager</td><td>monitoring</td><td>端口转发 9093</td><td>—</td></tr>
</table>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="start">🚀 一、环境启动</h2>

<div class="step"><div class="step-num">1</div>
<p><strong>首次启动</strong> — 双击运行 <code>C:\\Users\\kim\\kind-env\\kind-env-start.bat</code>（建议管理员权限）</p>
<p>等待 2~3 分钟，看到 <span class="cmd">kind clusters ready</span> 后即可使用。</p>
</div>

<div class="step"><div class="step-num">2</div>
<p><strong>验证集群状态</strong> — 打开 WSL 终端，执行：</p>
<pre><code class="cmd">wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n monitoring
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n argocd</code></pre>
</div>

<!-- 截图指引 -->
<div class="shot">
<p>📸 截图：打开终端，运行 <code>kubectl get nodes</code>，截取包含 4 个节点（1×CP + 3×Worker）的输出。</p>
</div>

<div class="tip">💡 提示：如果 Docker Desktop 已关闭，重新运行 <code>kind-env-start.bat</code> 即可一键拉起所有集群。</div>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="access">🔐 二、服务访问指南</h2>

<h3>2.1 ArgoCD（GitOps 面板）</h3>
<div class="shot">
<p>📸 截图步骤：</p>
<p>1. 浏览器打开 <a href="http://localhost:30080">http://localhost:30080</a></p>
<p>2. Username 填 <code>admin</code>，Password 填 <code>wG0YYYIbLXX31dVf</code></p>
<p>3. 截取登录后的 Applications 页面（能看到 demo-app 应用）</p>
<p>4. 点击 demo-app → 截取 Sync 状态页面</p>
</div>
<p>登录后操作：</p>
<pre><code class="cmd"># 查看应用列表
Applications → 左侧菜单

# 手动同步
点击应用名 → Sync → Synchronize

# 查看差异
Diff 标签页

# 回滚
History → 选择历史版本 → Rollback</code></pre>

<h3>2.2 Grafana（监控 + 日志）</h3>
<div class="shot">
<p>📸 截图步骤：</p>
<p>1. 打开 <a href="http://localhost:30300">http://localhost:30300</a>，admin/admin123 登录</p>
<p>2. Dashboards → Browse → 搜索 "Kubernetes" → 打开 Pod 仪表盘</p>
<p>3. Explore → Prometheus → 输入 <code>up</code> → Run query → 截取指标结果</p>
<p>4. Explore → Loki → 输入 <code>{namespace="monitoring"}</code> → 截取日志视图</p>
</div>
<pre><code class="cmd"># Prometheus 查询示例
up{job="demo-app"}                    # Pod 在线状态
rate(http_requests_total[5m])        # QPS
container_cpu_usage_seconds_total     # CPU 使用率
container_memory_working_set_bytes   # 内存使用

# Loki 查询
{namespace="demo-app"}                # 应用日志
{namespace="demo-app"} |= "ERROR"    # 错误日志</code></pre>

<h3>2.3 Prometheus + Alertmanager</h3>
<div class="shot">
<p>📸 截图：<code>kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090</code> 后访问 localhost:9090，截取 Alerts 页面。</p>
</div>
<pre><code class="cmd"># Prometheus
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090

# Alertmanager
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-alertmanager 9093:9093</code></pre>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="cicd">🔄 三、CI/CD 端到端流程</h2>

<div class="shot">
<p>📸 截图指引 — 完整流水线截图需要你在 GitLab 界面操作：</p>
<p>1. GitLab → CI/CD → Pipelines → 打开一个成功运行的 pipeline</p>
<p>2. 截取 pipeline 全景（包含 build → test → scan → deploy 阶段）</p>
<p>3. 点击某个 job → 截取 job 日志输出</p>
<p>4. Deploy production 阶段 → 截取 "Play" 按钮界面</p>
</div>

<div class="step"><div class="step-num">1</div>
<p>创建 GitLab 项目 → 将 <code>demo-app</code> 目录代码推送到 <code>https://gitlab.com/你的用户名/demo-app.git</code></p>
</div>
<div class="step"><div class="step-num">2</div>
<p>配置 CI/CD Variables（Settings → CI/CD → Variables）：</p>
<table>
<tr><th>Variable</th><th>说明</th></tr>
<tr><td><code>KUBECONFIG_DATA</code></td><td>ops-mgmt kubeconfig 的 base64 编码</td></tr>
<tr><td><code>CI_REGISTRY_USER</code></td><td>GitLab 用户名</td></tr>
<tr><td><code>CI_REGISTRY_PASSWORD</code></td><td>GitLab Access Token（含 read_registry 权限）</td></tr>
</table>
<pre><code class="cmd"># 生成 KUBECONFIG_DATA
wsl -d Ubuntu kubectl --context kind-ops-mgmt config view --raw | base64 -w 0</code></pre>
</div>
<div class="step"><div class="step-num">3</div>
<p>触发 Pipeline：CI/CD → Pipelines → Run pipeline（main 分支）</p>
</div>
<div class="step"><div class="step-num">4</div>
<p>Pipeline 阶段：<code>build</code> → <code>test-unit</code> → <code>security-scan</code> → <code>deploy-production</code>（需手动 ▶ Play）</p>
</div>
<div class="step"><div class="step-num">5</div>
<p>验证部署：</p>
<pre><code class="cmd">wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -n demo-app
wsl -d Ubuntu kubectl --context kind-ops-mgmt get hpa -n demo-app
wsl -d Ubuntu kubectl --context kind-ops-mgmt top pod -n demo-app</code></pre>
</div>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="gitops">🎯 四、GitOps 演示（ArgoCD）</h2>

<div class="shot">
<p>📸 截图步骤：</p>
<p>1. ArgoCD UI → Applications → 截取完整应用列表（包含 Health/Sync 状态）</p>
<p>2. 点击 demo-app → Sync 页面 → 截取 Diff 视图（显示 Git 与集群差异）</p>
<p>3. History 页面 → 截取版本历史列表</p>
<p>4. 修改 Git 代码后 → Git push → 等待 3 分钟 → 截取 ArgoCD 自动同步后的状态</p>
</div>
<pre><code class="cmd"># 部署 ArgoCD Application
wsl -d Ubuntu kubectl --context kind-ops-mgmt apply -n argocd \\
  -f C:\\Users\\kim\\kind-env\\demo-app\\argocd\\app.yaml

# 查看同步状态
argocd app list
argocd app get demo-app
argocd app sync demo-app    # 手动触发同步</code></pre>

<p><strong>GitOps 回滚演示流程：</strong></p>
<div class="step"><div class="step-num">1</div>修改 Git 中的 <code>deployment.yaml</code> 镜像版本 → git push</div>
<div class="step"><div class="step-num">2</div>等待 ArgoCD 自动检测（默认 3 分钟轮询）</div>
<div class="step"><div class="step-num">3</div>ArgoCD 自动同步到集群（无需手动操作）</div>
<div class="step"><div class="step-num">4</div>如需回滚：ArgoCD → demo-app → History → 选择版本 → Rollback</div>
</div>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="observe">📊 五、可观测配置</h2>

<h3>5.1 添加 Loki 数据源</h3>
<div class="shot">
<p>📸 截图：Grafana → ⚙️ → Data Sources → Add data source → Loki → 填写 URL 和 X-Scope-OrgID header。</p>
</div>
<pre><code class="cmd">Grafana → ⚙️ Configuration → Data Sources → Add data source → Loki

URL:      http://loki-gateway.monitoring.svc.cluster.local
Headers:  X-Scope-OrgID = foo

点击 Save & test</code></pre>

<h3>5.2 配置飞书告警通知</h3>
<div class="warn">⚠️ 需要提供：飞书群机器人 Webhook URL（飞书群 → 设置 → 群机器人 → 添加自定义机器人）</div>
<pre><code class="cmd"># 创建告警 Secret
kubectl --context kind-ops-mgmt create secret generic alertmanager-config \\
  -n monitoring --from-file=alertmanager.yaml=./k8s/alertmanager-config.yaml</code></pre>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="fault">🚨 六、故障自检流程</h2>

<div class="shot">
<p>📸 截图：运行各排查命令后，截取终端输出（高亮 ERROR/WARNING 行）。</p>
</div>

<table>
<tr><th>症状</th><th>排查命令</th></tr>
<tr><td>Pod 不Running</td><td><code>kubectl describe pod &lt;name&gt; -n &lt;ns&gt;</code></td></tr>
<tr><td>应用无法访问</td><td><code>kubectl logs &lt;pod&gt; -n demo-app --tail=50</code></td></tr>
<tr><td>Pod 反复重启</td><td><code>kubectl logs &lt;pod&gt; -n demo-app --previous</code></td></tr>
<tr><td>资源不足</td><td><code>kubectl top pod -n demo-app</code></td></tr>
<tr><td>重建 ArgoCD</td><td><code>kubectl delete namespace argocd && kubectl apply -n argocd -f &lt;url&gt;</code></td></tr>
<tr><td>重建监控</td><td><code>helm upgrade --install prometheus ... -f values-prometheus.yaml</code></td></tr>
</table>

<pre><code class="cmd"># 完整重建
wsl -d Ubuntu kind delete clusters --all
C:\\Users\\kim\\kind-env\\kind-env-start.bat</code></pre>

<!-- ══════════════════════════════════════════════════════════════ -->
<h2 id="cheatsheet">⚡ 七、速查命令</h2>

<div class="grid">
"""

# 生成组件状态卡片
status_colors = {"全部就绪": ("ok", "green"), "部分就绪": ("warn", "yellow"), "全部异常": ("err", "yellow"), "0 Pods": ("err", "red")}
for label, info in components.items():
    if info["total"] == 0:
        sc, color = "err", "全部异常"
    elif info["ready"] == info["total"]:
        sc, color = "ok", "全部就绪"
    else:
        sc, color = "warn", "部分就绪"
    html += f"""<div class="card">
  <div class="card-title"><span class="dot {sc}"></span>{label}</div>
  <div class="card-meta"><span>NS: {info["ns"]}</span><span>Ready: {info["ready"]}/{info["total"]}</span></div>
  <span class="badge {color}">{color}</span>
</div>
"""

html += f"""
</div>

<pre><code class="cmd"># ── 集群操作 ──
wsl -d Ubuntu kind get clusters
wsl -d Ubuntu kubectl --context kind-ops-mgmt get nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt get pods -A

# ── 上下文切换 ──
wsl -d Ubuntu kubectl config use-context kind-ops-mgmt
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regiona
wsl -d Ubuntu kubectl config use-context kind-biz-prod-regionb

# ── 端口转发 ──
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-grafana 30300:80
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring port-forward svc/prometheus-prometheus 9090:9090
wsl -d Ubuntu kubectl --context kind-ops-mgmt -n argocd port-forward svc/argocd-server 30080:443

# ── 查看资源 ──
wsl -d Ubuntu helm list -A
wsl -d Ubuntu kubectl top nodes
wsl -d Ubuntu kubectl --context kind-ops-mgmt top pod -n demo-app</code></pre>

html += """
<table>
<tr><th>参数</th><th>值</th></tr>
<tr><td>K8s 版本</td><td>v1.27.3</td></tr>
<tr><td>ArgoCD UI</td><td>http://localhost:30080</td></tr>
<tr><td>Grafana</td><td>http://localhost:30300</td></tr>
<tr><td>ArgoCD 密码</td><td>wG0YYYIbLXX31dVf</td></tr>
<tr><td>Grafana 密码</td><td>admin / admin123</td></tr>
<tr><td>StorageClass</td><td>standard (rancher.io/local-path)</td></tr>
</table>

<div class="tip" style="margin-top:2rem">
💡 飞书文档已推送至：<br>
• <a href="https://my.feishu.cn/docx/KyfgdKymPokFgzxT6Ljc3auGnpg">使用手册</a>（KyfgdKymPokFgzxT6Ljc3auGnpg）<br>
• <a href="https://my.feishu.cn/docx/CNwudFGMnocYvRxjLngcFGaYnFh">故障场景与响应</a>（CNwudFGMnocYvRxjLngcFGaYnFh）
</div>

</div><!-- wrap -->
</body>
</html>"""

out_path = r"C:\Users\kim\kind-env\使用手册截图版.html"
with open(out_path, "w", encoding="utf-8") as f:
    f.write(html)
print(f"Written {len(html)} chars → {out_path}")
