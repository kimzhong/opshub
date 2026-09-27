/**
 * k8s.js — kubectl / Helm / Prometheus / Loki 封装
 *
 * 所有对集群的访问都经由 WSL 中的 kubectl 命令，
 * 这样不需要在 Windows 侧持有 kubeconfig，也避开 WSL2 网络隔离问题。
 */
import { execFile } from 'node:child_process';
import { CONFIG } from './config.js';

/* ────────────────────────────────────────────────
   低层执行器
──────────────────────────────────────────────── */

/**
 * 在 WSL 中执行一条命令，返回 { code, stdout, stderr }
 * @param {string[]} args 例如 ['kubectl','get','nodes']
 */
export function wslExec(args, { timeout = CONFIG.cmdTimeout } = {}) {
  return new Promise((resolve) => {
    execFile(
      'wsl',
      ['-d', CONFIG.wslDistro, '--', ...args],
      { timeout, maxBuffer: 32 * 1024 * 1024, encoding: 'utf8' },
      (err, stdout, stderr) => {
        resolve({
          code: err ? (err.code ?? 1) : 0,
          stdout: stdout || '',
          stderr: stderr || (err ? err.message : ''),
        });
      }
    );
  });
}

/* ────────────────────────────────────────────────
   kubectl
──────────────────────────────────────────────── */

/** 执行 kubectl 并解析 JSON 输出，失败返回 null */
export async function kubectlJson(context, ...args) {
  const full = ['kubectl', '--context', context, ...args, '-o', 'json'];
  const { code, stdout, stderr } = await wslExec(full);
  if (code !== 0) {
    console.warn(`[kubectl] ${context} ${args.join(' ')} → ${stderr.trim().slice(0, 160)}`);
    return null;
  }
  try {
    return JSON.parse(stdout);
  } catch {
    return null;
  }
}

/** 执行 kubectl 并返回原始文本（用于 logs / describe / exec） */
export async function kubectlText(context, ...args) {
  const { code, stdout, stderr } = await wslExec([
    'kubectl', '--context', context, ...args,
  ]);
  return { ok: code === 0, output: stdout || stderr || '' };
}

/* ────────────────────────────────────────────────
   集群概览
──────────────────────────────────────────────── */

/**
 * 获取单个集群概览：节点列表 + Pod 总数 + 按命名空间统计
 */
export async function getClusterOverview(context) {
  const [nodesRaw, podsRaw] = await Promise.all([
    kubectlJson(context, 'get', 'nodes'),
    kubectlJson(context, 'get', 'pods', '-A'),
  ]);

  const nodes = (nodesRaw?.items || []).map((n) => {
    const labels = n.metadata?.labels || {};
    const conditions = n.status?.conditions || [];
    return {
      name: n.metadata?.name || '?',
      role: labels['node-role.kubernetes.io/control-plane'] ? 'control-plane' : 'worker',
      ready: conditions.some((c) => c.type === 'Ready' && c.status === 'True'),
      version: n.status?.nodeInfo?.kubeletVersion || '?',
      osImage: n.status?.nodeInfo?.osImage || '?',
      cpu: n.status?.allocatable?.cpu || '?',
      memory: n.status?.allocatable?.memory || '?',
      pods: n.status?.allocatable?.pods || '?',
      uptime: n.metadata?.creationTimestamp?.slice(0, 19) || '',
    };
  });

  const nsStats = {};
  for (const p of podsRaw?.items || []) {
    const ns = p.metadata?.namespace || 'default';
    const phase = p.status?.phase || 'Unknown';
    nsStats[ns] ??= { total: 0, running: 0, pending: 0, failed: 0 };
    nsStats[ns].total += 1;
    if (phase === 'Running') nsStats[ns].running += 1;
    else if (phase === 'Pending') nsStats[ns].pending += 1;
    else if (phase === 'Failed') nsStats[ns].failed += 1;
  }

  return {
    context,
    nodes,
    totalNodes: nodes.length,
    readyNodes: nodes.filter((n) => n.ready).length,
    totalPods: Object.values(nsStats).reduce((s, v) => s + v.total, 0),
    namespaces: Object.keys(nsStats).sort(),
    namespaceStats: nsStats,
  };
}

/** 并发获取所有集群概览 */
export async function getAllClusters(list) {
  return Promise.all(list.map((c) => getClusterOverview(c.context)));
}

/* ────────────────────────────────────────────────
   Pod
──────────────────────────────────────────────── */

/** 列出指定命名空间的 Pod */
export async function listPods(context, namespace) {
  const raw = await kubectlJson(context, 'get', 'pods', '-n', namespace);
  return (raw?.items || []).map((p) => {
    const status = p.status || {};
    const cs = status.containerStatuses || [];
    const readyCount = cs.filter((c) => c.ready).length;
    return {
      name: p.metadata?.name || '',
      phase: status.phase || 'Unknown',
      ready: `${readyCount}/${cs.length || 0}`,
      restarts: cs.reduce((s, c) => s + (c.restartCount || 0), 0),
      age: p.metadata?.creationTimestamp?.slice(0, 16).replace('T', ' ') || '',
      node: p.spec?.nodeName || '',
      image: (cs[0]?.image || '').split(':')[0],
      imageTag: (cs[0]?.image || '').split(':')[1] || '',
      qosClass: p.status?.qosClass || '',
    };
  }).sort((a, b) => a.name.localeCompare(b.name));
}

/** Pod 日志 */
export function podLogs(context, namespace, pod, tail = 50) {
  return kubectlText(context, 'logs', pod, '-n', namespace, `--tail=${tail}`);
}

/** Pod describe（事件 + 状态详情） */
export function podDescribe(context, namespace, pod) {
  return kubectlText(context, 'describe', 'pod', pod, '-n', namespace);
}

/* ────────────────────────────────────────────────
   Deployment / HPA 操作
──────────────────────────────────────────────── */

/** 滚动重启 */
export async function rolloutRestart(context, namespace, resource, name) {
  const r = await kubectlText(
    context, 'rollout', 'restart', `${resource}/${name}`, '-n', namespace
  );
  return { ok: r.ok, message: r.output.trim() };
}

/** 等待 rollout 完成（最多 wait 秒） */
export async function rolloutStatus(context, namespace, resource, name, wait = 30) {
  const r = await kubectlText(
    context, 'rollout', 'status', `${resource}/${name}`,
    '-n', namespace, `--timeout=${wait}s`
  );
  return { ok: r.ok, message: r.output.trim() };
}

/** 扩缩容 */
export async function scaleDeployment(context, namespace, name, replicas) {
  const r = await kubectlText(
    context, 'scale', `deployment/${name}`, '-n', namespace, `--replicas=${replicas}`
  );
  return { ok: r.ok, message: r.output.trim(), replicas };
}

/** 列出 HPA */
export async function listHpa(context, namespace) {
  const raw = await kubectlJson(context, 'get', 'hpa', '-n', namespace);
  return (raw?.items || []).map((h) => ({
    name: h.metadata?.name || '',
    minReplicas: h.spec?.minReplicas ?? 1,
    maxReplicas: h.spec?.maxReplicas ?? 10,
    currentReplicas: h.status?.currentReplicas ?? 0,
    desiredReplicas: h.status?.desiredReplicas ?? 0,
    targetCPU: h.spec?.targetCPUUtilizationPercentage ?? null,
  }));
}

/* ────────────────────────────────────────────────
   Service / Ingress
──────────────────────────────────────────────── */

export async function listServices(context, namespace) {
  const raw = await kubectlJson(context, 'get', 'svc', '-n', namespace);
  return (raw?.items || []).map((s) => {
    const spec = s.spec || {};
    return {
      name: s.metadata?.name || '',
      type: spec.type || 'ClusterIP',
      clusterIP: spec.clusterIP || '',
      externalIP: spec.externalIPs?.[0] || '',
      ports: (spec.ports || []).map((p) => ({
        port: p.port,
        targetPort: String(p.targetPort ?? ''),
        nodePort: p.nodePort ?? null,
        protocol: p.protocol || 'TCP',
      })),
      age: s.metadata?.creationTimestamp?.slice(0, 10) || '',
    };
  });
}

/* ────────────────────────────────────────────────
   ArgoCD
──────────────────────────────────────────────── */

/** 读取 ArgoCD Application CRD 列表 */
export async function listArgoApps(context) {
  const raw = await kubectlJson(context, 'get', 'applications', '-n', 'argocd');
  return (raw?.items || []).map((a) => {
    const st = a.status || {};
    return {
      name: a.metadata?.name || '',
      namespace: a.metadata?.namespace || 'argocd',
      health: st.health?.status || 'Unknown',
      sync: st.sync?.status || 'Unknown',
      repo: a.spec?.source?.repoURL || '',
      path: a.spec?.source?.path || '',
      targetRevision: a.spec?.source?.targetRevision || '',
      revision: st.sync?.revision?.slice(0, 8) || '',
      autoSync: !!a.spec?.syncPolicy?.automated,
      selfHeal: !!a.spec?.syncPolicy?.automated?.selfHeal,
      prune: !!a.spec?.syncPolicy?.automated?.prune,
      lastSyncAt: st.reconciledAt?.slice(0, 19).replace('T', ' ') || '',
    };
  });
}

/** 触发 ArgoCD 同步（优先走本地 argocd CLI，回退到 argocd-server exec） */
export async function syncArgoApp(context, app) {
  const script = `
    argocd app sync ${app} 2>/dev/null && exit 0
    kubectl --context ${context} -n argocd exec deploy/argocd-server -- \
      argocd app sync ${app} --grpc-web 2>&1
  `.trim();
  const { code, stdout, stderr } = await wslExec(['bash', '-lc', script], { timeout: 60000 });
  return {
    ok: code === 0,
    output: (stdout || '').trim().slice(0, 1200),
    error: (stderr || '').trim().slice(0, 400),
  };
}

/* ────────────────────────────────────────────────
   Helm
──────────────────────────────────────────────── */

export async function listHelmReleases() {
  const { code, stdout } = await wslExec(['helm', 'list', '-A', '-o', 'json']);
  if (code !== 0) return [];
  try {
    return JSON.parse(stdout);
  } catch {
    return [];
  }
}

/* ────────────────────────────────────────────────
   Prometheus（原生 fetch，无需 kubectl）
──────────────────────────────────────────────── */

/** 拉取告警 */
export async function fetchAlerts() {
  try {
    const ctrl = AbortSignal.timeout(8000);
    const res = await fetch(`${CONFIG.endpoints.prometheus}/api/v1/alerts`, { signal: ctrl });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    if (data.status !== 'success') throw new Error('bad payload');

    const alerts = data.data?.alerts || [];
    const normalize = (a) => ({
      state: a.state,
      labels: a.labels || {},
      annotations: a.annotations || {},
      activeAt: a.activeAt,
      value: a.value,
    });
    const firing = alerts.filter((a) => a.state === 'firing').map(normalize);
    const pending = alerts.filter((a) => a.state === 'pending').map(normalize);

    return {
      ok: true,
      count: firing.length,
      firing,
      pending,
      source: CONFIG.endpoints.prometheus,
    };
  } catch (e) {
    return {
      ok: false,
      count: 0,
      firing: [],
      pending: [],
      error: e.message,
      hint: '需要 port-forward: kubectl -n monitoring port-forward svc/prometheus-prometheus 9090:9090',
    };
  }
}

/** 立即执行 PromQL 查询 */
export async function promQuery(expr) {
  try {
    const ctrl = AbortSignal.timeout(8000);
    const url = `${CONFIG.endpoints.prometheus}/api/v1/query?query=${encodeURIComponent(expr)}`;
    const res = await fetch(url, { signal: ctrl });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    return { ok: true, data: data.data };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

/* ────────────────────────────────────────────────
   Loki
──────────────────────────────────────────────── */

/** LogQL 区间查询（最近 ns 秒） */
export async function lokiQuery(logql, { limit = 100, seconds = 3600 } = {}) {
  const end = Date.now() * 1e6;
  const start = (Date.now() - seconds * 1000) * 1e6;
  const url =
    `${CONFIG.endpoints.loki}/loki/api/v1/query_range` +
    `?query=${encodeURIComponent(logql)}` +
    `&limit=${limit}&direction=backward&start=${start}&end=${end}`;

  try {
    const ctrl = AbortSignal.timeout(10000);
    const res = await fetch(url, {
      signal: ctrl,
      headers: { 'X-Scope-OrgID': 'foo' },   // Loki 开启了 multi-tenancy
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    const lines = [];
    for (const stream of data.data?.result || []) {
      const labels = stream.stream || {};
      for (const [tsNs, line] of stream.values || []) {
        lines.push({
          ns: Number(tsNs),
          time: new Date(Number(tsNs) / 1e6).toISOString().slice(0, 19).replace('T', ' '),
          labels,
          pod: labels.pod || '',
          namespace: labels.namespace || '',
          line,
        });
      }
    }
    lines.sort((a, b) => a.ns - b.ns);
    return { ok: true, count: lines.length, lines };
  } catch (e) {
    return {
      ok: false,
      count: 0,
      lines: [],
      error: e.message,
      hint: '需要 port-forward: kubectl -n monitoring port-forward svc/loki-gateway 3100:80',
    };
  }
}

/** Loki 标签列表（用于自动补全 namespace） */
export async function lokiLabels() {
  try {
    const ctrl = AbortSignal.timeout(8000);
    const res = await fetch(`${CONFIG.endpoints.loki}/loki/api/v1/labels`, {
      signal: ctrl,
      headers: { 'X-Scope-OrgID': 'foo' },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return (await res.json()).data || [];
  } catch {
    return [];
  }
}
