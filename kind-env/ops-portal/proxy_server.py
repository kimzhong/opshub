#!/usr/bin/env python3
"""
ops-portal 代理服务 — 完整版
集成了：K8s API 代理 + Loki 查询 + Web SSH 终端 + 飞书 Webhook

启动（WSL Ubuntu）：
  cd /mnt/c/Users/kim/kind-env/ops-portal
  python3 proxy_server.py

Windows 浏览器访问：
  http://localhost:8099/  → Ops Portal
  http://localhost:8099/health  → 健康检查
  http://localhost:8099/webhook/feishu  → 飞书告警 Webhook 接收
"""

import json
import subprocess
import re
import logging
import threading
import hashlib
import hmac
import time
import base64
import struct
import fcntl
import os
import select as select_module
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, urlencode
from datetime import datetime, timedelta

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
log = logging.getLogger("ops-portal")

PROXY_PORT = 8099

# ── 全局告警状态（内存，演示用）─────────────────────────────────
alerts_state = {
    'active': [],
    'count': 0,
    'last_update': None,
}

# ── 飞书 Webhook（用户需替换）──────────────────────────────────
FEISHU_WEBHOOK_URL = ""

# ── kubectl 包装 ──────────────────────────────────────────────
def kubectl(ctx: str, *args, json_out=True) -> dict | None:
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'kubectl', '--context', ctx]
    cmd += list(args)
    if json_out:
        cmd += ['-o', 'json']
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            log.warning(f"kubectl failed: {result.stderr.strip()[:100]}")
            return None
        if not json_out:
            return {"raw": result.stdout}
        return json.loads(result.stdout)
    except Exception as e:
        log.error(f"kubectl exception: {e}")
        return None

def kubectl_raw(ctx: str, *args) -> str:
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'kubectl', '--context', ctx]
    cmd += list(args)
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return result.stdout + result.stderr
    except Exception as e:
        return str(e)

# ── K8s 集群数据 ──────────────────────────────────────────────
def get_cluster_overview(ctx: str) -> dict:
    nodes = kubectl(ctx, 'get', 'nodes') or {}
    pods   = kubectl(ctx, 'get', 'pods', '--all-namespaces') or {}

    node_list = nodes.get('items', [])
    pod_list  = pods.get('items', [])

    node_summary = []
    for n in node_list:
        name = n.get('metadata', {}).get('name', '?')
        conditions = n.get('status', {}).get('conditions', [])
        ready = any(c.get('type') == 'Ready' and c.get('status') == 'True' for c in conditions)
        labels = n.get('metadata', {}).get('labels', {})
        role = 'worker'
        if 'node-role.kubernetes.io/control-plane' in labels:
            role = 'control-plane'
        node_summary.append({
            'name': name, 'role': role, 'ready': ready,
            'version': n.get('status', {}).get('nodeInfo', {}).get('kubeletVersion', '?'),
            'cpu': n.get('status', {}).get('allocatable', {}).get('cpu', '?'),
            'memory': n.get('status', {}).get('allocatable', {}).get('memory', '?'),
        })

    ns_counts = {}
    for p in pod_list:
        ns_name = p.get('metadata', {}).get('namespace', 'default')
        phase   = p.get('status', {}).get('phase', 'Unknown')
        ns_counts.setdefault(ns_name, {'total': 0, 'running': 0})
        ns_counts[ns_name]['total'] += 1
        if phase in ('Running', 'Succeeded'):
            ns_counts[ns_name]['running'] += 1

    return {
        'cluster': ctx,
        'nodes': node_summary,
        'total_nodes': len(node_list),
        'ready_nodes': sum(1 for n in node_summary if n['ready']),
        'total_pods': len(pod_list),
        'namespace_counts': ns_counts,
    }

def get_namespace_pods(ctx: str, namespace: str) -> list:
    result = kubectl(ctx, 'get', 'pods', '-n', namespace) or {}
    pods = []
    for p in result.get('items', []):
        status = p.get('status', {})
        containers = status.get('containerStatuses', [])
        restart = sum(c.get('restartCount', 0) for c in containers)
        pods.append({
            'name': p.get('metadata', {}).get('name', ''),
            'phase': status.get('phase', 'Unknown'),
            'ready': f"{sum(c.get('ready',0) for c in containers)}/{len(containers)}",
            'restarts': restart,
            'age': p.get('metadata', {}).get('creationTimestamp', '')[:10],
            'image': (containers[0].get('image', '') if containers else '').split(':')[0],
        })
    return pods

def get_argocd_apps(ctx: str) -> list:
    result = kubectl(ctx, 'get', 'applications', '-n', 'argocd') or {}
    apps = []
    for a in result.get('items', []):
        status = a.get('status', {})
        apps.append({
            'name': a.get('metadata', {}).get('name', ''),
            'namespace': a.get('metadata', {}).get('namespace', ''),
            'health': status.get('health', {}).get('status', 'Unknown'),
            'sync': status.get('sync', {}).get('status', 'Unknown'),
            'repo': a.get('spec', {}).get('source', {}).get('repoURL', ''),
            'revision': status.get('sync', {}).get('revision', ''),
        })
    return apps

def get_pod_logs(ctx: str, namespace: str, name: str, tail: int = 50) -> dict:
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'kubectl', '--context', ctx,
           '-n', namespace, 'logs', name, f'--tail={tail}']
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return {'ok': result.returncode == 0, 'logs': result.stdout, 'error': result.stderr if result.returncode != 0 else ''}

def get_pod_describe(ctx: str, namespace: str, name: str) -> dict:
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'kubectl', '--context', ctx,
           '-n', namespace, 'describe', 'pod', name]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return {'ok': result.returncode == 0, 'output': result.stdout, 'error': result.stderr if result.returncode != 0 else ''}

def rollout_restart(ctx: str, namespace: str, resource: str, name: str) -> dict:
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'kubectl', '--context', ctx,
           '-n', namespace, 'rollout', 'restart', f'{resource}/{name}']
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return {'ok': result.returncode == 0, 'message': result.stdout.strip() or result.stderr.strip()}

def scale_deploy(ctx: str, namespace: str, name: str, replicas: int) -> dict:
    result = kubectl(ctx, 'patch', 'deployment', name, '-n', namespace,
                     '--type=merge', '-p', json.dumps({'spec': {'replicas': replicas}}))
    return {'ok': result is not None, 'replicas': replicas}

# ── ArgoCD Sync ───────────────────────────────────────────────
def argocd_sync(ctx: str, app: str) -> dict:
    # 通过 ArgoCD CLI（需安装）或 kubectl exec
    # 尝试 kubectl exec argocd-server
    cmd = ['wsl', '-d', 'Ubuntu', '--', 'bash', '-c',
           f'argocd app sync {app} --context {ctx} -n argocd 2>&1 || '
           f'kubectl --context {ctx} -n argocd exec deploy/argocd-server -- argocd app sync {app} 2>&1 || echo "ArgoCD CLI not available"']
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    return {'ok': True, 'output': result.stdout[:500], 'error': result.stderr[:200]}

# ── Prometheus Alerts ──────────────────────────────────────────
def prometheus_alerts() -> dict:
    cmd = ['curl', '-s', 'http://localhost:9090/api/v1/alerts']
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
    if result.returncode != 0:
        return {'active': [], 'pending': [], 'count': 0, 'error': 'Prometheus not reachable (need port-forward)'}
    try:
        data = json.loads(result.stdout)
        if data.get('status') == 'success':
            alerts = data.get('data', {}).get('alerts', [])
            active = [a for a in alerts if a.get('state') == 'firing']
            pending = [a for a in alerts if a.get('state') == 'pending']
            global alerts_state
            alerts_state['active'] = active
            alerts_state['count'] = len(active)
            alerts_state['last_update'] = datetime.now().isoformat()
            return {'active': active, 'pending': pending, 'count': len(active)}
    except:
        pass
    return {'active': [], 'pending': [], 'count': 0}

# ── Loki 查询 ─────────────────────────────────────────────────
def loki_query(query: str, limit: int = 100) -> dict:
    import urllib.parse
    q = urllib.parse.quote(query)
    cmd = ['curl', '-s', f'http://localhost:3100/loki/api/v1/query_range?query={q}&limit={limit}&direction=backward']
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        return {'status': 'error', 'error': result.stderr}
    try:
        data = json.loads(result.stdout)
        # 解析 Loki v2 格式
        streams = []
        result_data = data.get('data', {}).get('result', [])
        for stream in result_data:
            labels = stream.get('stream', {})
            values = stream.get('values', [])
            for ts_ns, line in values:
                streams.append({
                    'labels': labels,
                    'timestamp': int(ts_ns) // 1_000_000,
                    'line': line,
                })
        return {'status': 'success', 'streams': streams}
    except Exception as e:
        return {'status': 'error', 'error': str(e), 'raw': result.stdout[:200]}

# ── Web SSH PTY ────────────────────────────────────────────────
class SSHChannel:
    """基于 WSL kubectl exec 的交互式 PTY"""
    def __init__(self, ctx: str, namespace: str, pod: str, container: str = ''):
        self.ctx = ctx
        self.namespace = namespace
        self.pod = pod
        self.container = container
        self.proc = None
        self.buf = b''

    def open(self) -> bool:
        cmd = ['wsl', '-d', 'Ubuntu', '--']
        exec_args = ['kubectl', 'exec', '--context', self.ctx, '-n', self.namespace, 'exec', '-it', self.pod]
        if self.container:
            exec_args += ['-c', self.container]
        exec_args += ['--', '/bin/bash', '-li']
        cmd += exec_args
        log.info(f"Starting PTY: {' '.join(cmd)}")
        import pty, os, termios, tty
        self.pid, self.master_fd = pty.fork()
        if self.pid == 0:
            # child — exec kubectl
            os.execvp('wsl', ['wsl', '-d', 'Ubuntu', '--'] + exec_args)
        else:
            # parent
            old = termios.tcgetattr(self.master_fd)
            old[3] = old[3] & ~termios.ECHO
            termios.tcsetattr(self.master_fd, termios.TCSADRAIN, old)
            return True

    def write(self, data: bytes):
        if self.master_fd:
            import os
            try:
                os.write(self.master_fd, data)
            except:
                pass

    def read(self, n: int = 4096) -> bytes:
        if self.master_fd:
            import os, select as sel
            r, _, _ = sel.select([self.master_fd], [], [], 0.5)
            if r:
                try:
                    return os.read(self.master_fd, n)
                except:
                    return b''
        return b''

    def resize(self, rows: int, cols: int):
        if self.master_fd:
            import fcntl, struct, termios
            winsize = struct.pack('HHHH', rows, cols, 0, 0)
            fcntl.ioctl(self.master_fd, termios.TIOCSWINSZ, winsize)

    def close(self):
        if self.master_fd:
            import os
            try: os.close(self.master_fd)
            except: pass
        if self.pid and self.pid > 0:
            try: os.kill(self.pid, 9)
            except: pass

# 全局 PTY 会话
active_ssh: SSHChannel | None = None
ssh_lock = threading.Lock()

def ws_ssh_handler(ws, path_qs: str):
    global active_ssh
    import re
    m = re.search(r'ctx=([^&]+)&ns=([^&]+)&pod=(.+)', path_qs)
    if not m:
        ws.send(json.dumps({'type': 'error', 'data': 'invalid params'}))
        return

    ctx = m.group(1)
    ns  = m.group(2)
    pod = m.group(3)

    with ssh_lock:
        if active_ssh:
            try: active_ssh.close()
            except: pass
        active_ssh = SSHChannel(ctx, ns, pod)

    try:
        active_ssh.open()
        ws.send(json.dumps({'type': 'ready', 'data': 'PTY opened'}))

        # 读取线程
        def reader():
            while True:
                data = active_ssh.read(2048)
                if not data:
                    break
                try:
                    ws.send(json.dumps({'type': 'data', 'data': data.decode('utf-8', errors='replace')}))
                except:
                    break

        t = threading.Thread(target=reader, daemon=True)
        t.start()

        # 写入循环
        while True:
            msg = ws.receive()
            if msg is None:
                break
            try:
                m2 = json.loads(msg)
                if m2.get('type') == 'input':
                    active_ssh.write(m2['data'].encode('utf-8'))
                elif m2.get('type') == 'resize':
                    rows = int(m2.get('rows', 24))
                    cols = int(m2.get('cols', 80))
                    active_ssh.resize(rows, cols)
            except Exception as e:
                log.warning(f"ws msg error: {e}")
    except Exception as e:
        log.error(f"SSH error: {e}")
        try: ws.send(json.dumps({'type': 'error', 'data': str(e)}))
        except: pass
    finally:
        with ssh_lock:
            if active_ssh:
                active_ssh.close()
                active_ssh = None

# ── HTTP Handler ───────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):

    CORS_HEADERS = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS, PUT, DELETE',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Webhook-Secret',
    }

    def send_json(self, data, status=200):
        self.send_response(status)
        for k, v in self.CORS_HEADERS.items():
            self.send_header(k, v)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self.send_response(200)
        for k, v in self.CORS_HEADERS.items():
            self.send_header(k, v)
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path   = parsed.path
        qs     = parse_qs(parsed.query)

        # ── 首页 ──
        if path in ('/', '/index.html'):
            with open(os.path.join(os.path.dirname(__file__), 'index.html'), encoding='utf-8') as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(content.encode('utf-8'))
            return

        # ── 健康检查 ──
        if path == '/health':
            return self.send_json({'ok': True, 'service': 'ops-portal-proxy', 'port': PROXY_PORT,
                                   'alerts': alerts_state.get('count', 0)})

        # ── 告警状态（轮询端点） ──
        if path == '/api/alerts/state':
            return self.send_json(alerts_state)

        # ── 集群概览 ──
        if path == '/api/clusters':
            clusters = [get_cluster_overview('kind-ops-mgmt'),
                        get_cluster_overview('kind-biz-prod-regiona'),
                        get_cluster_overview('kind-biz-prod-regionb')]
            return self.send_json({'clusters': clusters})

        if path == '/api/cluster':
            ctx  = qs.get('context', ['kind-ops-mgmt'])[0]
            data = get_cluster_overview(ctx)
            return self.send_json(data)

        # ── Pod 列表 ──
        if path == '/api/pods':
            ctx  = qs.get('context', ['kind-ops-mgmt'])[0]
            ns   = qs.get('namespace', ['default'])[0]
            pods = get_namespace_pods(ctx, ns)
            return self.send_json({'namespace': ns, 'pods': pods})

        # ── ArgoCD Apps ──
        if path == '/api/argocd/apps':
            ctx  = qs.get('context', ['kind-ops-mgmt'])[0]
            apps = get_argocd_apps(ctx)
            return self.send_json({'apps': apps})

        # ── Prometheus Alerts ──
        if path == '/api/alerts':
            return self.send_json(prometheus_alerts())

        # ── Loki 查询 ──
        if path == '/api/loki':
            q     = qs.get('q', ['{namespace="default"}'])[0]
            limit = int(qs.get('limit', ['100'])[0])
            return self.send_json(loki_query(q, limit))

        # ── Pod 日志 ──
        if path == '/api/logs':
            ctx = qs.get('context', ['kind-ops-mgmt'])[0]
            ns  = qs.get('namespace', ['default'])[0]
            pod = qs.get('pod', [''])[0]
            tail = int(qs.get('tail', ['50'])[0])
            if not pod:
                return self.send_json({'error': 'pod required'}, 400)
            return self.send_json(get_pod_logs(ctx, ns, pod, tail))

        # ── Pod 描述 ──
        if path == '/api/describe':
            ctx = qs.get('context', ['kind-ops-mgmt'])[0]
            ns  = qs.get('namespace', ['default'])[0]
            pod = qs.get('pod', [''])[0]
            if not pod:
                return self.send_json({'error': 'pod required'}, 400)
            return self.send_json(get_pod_describe(ctx, ns, pod))

        # ── Terminal shell ──
        if path == '/api/terminal':
            # 返回可用的 shell 端点信息
            return self.send_json({
                'ws_path': '/ws/ssh',
                'params': 'ctx=<context>&ns=<namespace>&pod=<pod>',
                'usage': 'WebSocket 连接后发送 JSON: {type:"input",data:"ls\\r"} 或 {type:"resize",rows:24,cols:80}'
            })

        self.send_json({'error': 'not found', 'path': path}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path   = parsed.path
        length  = int(self.headers.get('Content-Length', 0))
        body   = self.rfile.read(length) if length else b'{}'
        try:
            data = json.loads(body)
        except:
            data = {}

        # ── 滚动重启 ──
        if path == '/api/rollout-restart':
            ctx  = data.get('context', 'kind-ops-mgmt')
            ns   = data.get('namespace', 'demo-app')
            res  = data.get('resource', 'deployment')
            name = data.get('name', 'demo-app')
            result = rollout_restart(ctx, ns, res, name)
            return self.send_json(result)

        # ── 扩容 ──
        if path == '/api/scale':
            ctx  = data.get('context', 'kind-ops-mgmt')
            ns   = data.get('namespace', 'demo-app')
            name = data.get('name', 'demo-app')
            reps = int(data.get('replicas', 3))
            result = scale_deploy(ctx, ns, name, reps)
            return self.send_json(result)

        # ── ArgoCD Sync ──
        if path == '/api/argocd/sync':
            ctx  = data.get('context', 'kind-ops-mgmt')
            app  = data.get('app', 'demo-app')
            result = argocd_sync(ctx, app)
            return self.send_json(result)

        # ── 飞书告警 Webhook ──
        if path == '/webhook/feishu':
            secret = self.headers.get('X-Webhook-Secret', '')
            length2 = int(self.headers.get('Content-Length', 0))
            body2 = self.rfile.read(length2) if length2 else b'{}'
            try:
                payload = json.loads(body2)
            except:
                payload = {}

            # 解析飞书卡片消息
            log.info(f"飞书 Webhook 收到: {str(payload)[:200]}")
            event_type = payload.get('event', {}).get('type', '')
            if event_type == 'im.message.receive_v1':
                msg = payload.get('event', {}).get('message', {})
                content = msg.get('content', '{}')
                try:
                    content_obj = json.loads(content)
                except:
                    content_obj = {}
                text = content_obj.get('text', '')
                log.info(f"飞书消息: {text[:100]}")

            # 存储告警
            global alerts_state
            alert_text = payload.get('msg_type', '') or payload.get('text', '') or str(payload)[:100]
            alerts_state['active'].append({
                'alert': alert_text,
                'time': datetime.now().isoformat(),
                'source': 'feishu_webhook'
            })
            alerts_state['count'] = len(alerts_state['active'])
            alerts_state['last_update'] = datetime.now().isoformat()

            # 转发到飞书群（如果有配置）
            if FEISHU_WEBHOOK_URL:
                import urllib.request
                try:
                    req = urllib.request.Request(
                        FEISHU_WEBHOOK_URL,
                        data=json.dumps({'msg_type': 'text', 'content': {'text': f'[Ops Portal] {alert_text}'}}).encode(),
                        headers={'Content-Type': 'application/json'}
                    )
                    urllib.request.urlopen(req, timeout=5)
                except Exception as e:
                    log.warning(f"飞书转发失败: {e}")

            return self.send_json({'ok': True, 'received': True})

        self.send_json({'error': 'not found'}, 404)


# ── WebSocket 支持 ─────────────────────────────────────────────
try:
    import asyncio
    from websockets.server import serve

    async def ws_handler(websocket, path):
        await ws_ssh_handler(_WebSocketWrapper(websocket), path)

    class _WebSocketWrapper:
        def __init__(self, ws):
            self._ws = ws
        def receive(self):
            try:
                return asyncio.get_event_loop().run_until_complete(
                    asyncio.wait_for(self._ws.recv(), timeout=0.5))
            except:
                return None
        def send(self, data):
            asyncio.get_event_loop().run_until_complete(self._ws.send(data))

    async def start_ws():
        async with serve(ws_handler, '0.0.0.0', 8098):
            await asyncio.Future()  # run forever

    def run_ws():
        asyncio.run(start_ws())

    WS_AVAILABLE = True
except ImportError:
    log.warning("websockets 库未安装，Web SSH 功能不可用。安装: pip install websockets")
    WS_AVAILABLE = False


# ── Main ──────────────────────────────────────────────────────
def main():
    global PROXY_PORT

    # WebSocket 线程
    if WS_AVAILABLE:
        t = threading.Thread(target=run_ws, daemon=True)
        t.start()
        log.info("🔌 WebSocket SSH 服务器: ws://localhost:8098")

    server = HTTPServer(('0.0.0.0', PROXY_PORT), Handler)
    log.info(f"🚀 ops-portal 代理服务启动")
    log.info(f"   HTTP API:   http://localhost:{PROXY_PORT}")
    log.info(f"   Web SSH:    ws://localhost:8098 (需要 pip install websockets)")
    log.info(f"   飞书 Webhook: POST http://localhost:{PROXY_PORT}/webhook/feishu")
    log.info(f"")
    log.info(f"⚠️  前置条件（需提前在另一个 WSL 终端运行）:")
    log.info(f"   wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \\")
    log.info(f"     port-forward svc/prometheus-prometheus 9090:9090 &")
    log.info(f"   wsl -d Ubuntu kubectl --context kind-ops-mgmt -n monitoring \\")
    log.info(f"     port-forward svc/loki-gateway 3100:80 &")
    log.info(f"")
    log.info(f"📡 API 端点:")
    log.info(f"   GET  /api/clusters         3集群概览")
    log.info(f"   GET  /api/cluster?context=X 单集群")
    log.info(f"   GET  /api/pods?namespace=X  Pod列表")
    log.info(f"   GET  /api/argocd/apps       ArgoCD")
    log.info(f"   GET  /api/alerts            告警")
    log.info(f"   GET  /api/loki?q=X          Loki")
    log.info(f"   GET  /api/logs?pod=X        日志")
    log.info(f"   POST /api/rollout-restart   重启")
    log.info(f"   POST /api/scale             扩容")
    log.info(f"   POST /api/argocd/sync       同步")
    log.info(f"   POST /webhook/feishu        飞书")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("关闭中...")
        server.shutdown()

if __name__ == '__main__':
    main()
