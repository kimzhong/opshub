/**
 * routes.js — HTTP API 路由
 *
 * 手写极简 router（零依赖），路径 → handler 映射。
 * 统一 JSON 响应 + CORS，方便独立调试。
 */
import { CONFIG, CLUSTER_LIST } from './config.js';
import * as k8s from './k8s.js';
import * as alerts from './alerts.js';
import { execOnce, listSessions, destroySession } from './terminal.js';

const routes = new Map();

/** 注册路由 */
function route(method, pattern, handler) {
  // /api/pods/:context/:namespace → 正则 + 参数名
  const keys = [];
  const regexSrc = pattern.replace(/:([A-Za-z_]+)/g, (_, k) => {
    keys.push(k);
    return '([^/]+)';
  });
  routes.set(`${method} ${pattern}`, {
    regex: new RegExp(`^${regexSrc}$`),
    keys,
    handler,
  });
}

/**
 * 匹配请求
 * @returns {{handler:Function, params:object}|null}
 */
function match(method, pathname) {
  const direct = routes.get(`${method} ${pathname}`);
  if (direct) return { handler: direct.handler, params: {} };

  for (const [key, r] of routes) {
    const [m, p] = key.split(' ');
    if (m !== method) continue;
    const hit = pathname.match(r.regex);
    if (hit) {
      const params = {};
      r.keys.forEach((k, i) => { params[k] = decodeURIComponent(hit[i + 1]); });
      return { handler: r.handler, params };
    }
  }
  return null;
}

const json = (data, status = 200) => ({ status, data });
const bad = (msg, status = 400) => ({ status, data: { error: msg } });

/* ══════════════════════════════════════════════
   健康检查 / 元信息
══════════════════════════════════════════════ */

route('GET', '/health', async () => {
  const snap = alerts.snapshot();
  return json({
    ok: true,
    service: 'kind-ops-portal',
    version: '2.0.0',
    node: process.version,
    uptimeSec: Math.round(process.uptime()),
    wslDistro: CONFIG.wslDistro,
    alerts: snap.total,
  });
});

route('GET', '/api/config', async () => json({
  clusters: CLUSTER_LIST,
  namespaces: CONFIG.commonNamespaces,
  endpoints: CONFIG.endpoints,
}));

/* ══════════════════════════════════════════════
   集群
══════════════════════════════════════════════ */

route('GET', '/api/clusters', async () => {
  const clusters = await k8s.getAllClusters(CLUSTER_LIST);
  const totals = clusters.reduce(
    (acc, c) => ({
      totalNodes: acc.totalNodes + c.totalNodes,
      readyNodes: acc.readyNodes + c.readyNodes,
      totalPods: acc.totalPods + c.totalPods,
    }),
    { totalNodes: 0, readyNodes: 0, totalPods: 0 }
  );
  return json({ clusters, totals });
});

route('GET', '/api/cluster/:context', async ({ params }) =>
  json(await k8s.getClusterOverview(params.context))
);

route('GET', '/api/namespaces', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const data = await k8s.getClusterOverview(context);
  return json({ context, namespaces: data.namespaces, namespaceStats: data.namespaceStats });
});

/* ══════════════════════════════════════════════
   Pod
══════════════════════════════════════════════ */

route('GET', '/api/pods', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const namespace = query.get('namespace') || 'default';
  const pods = await k8s.listPods(context, namespace);
  return json({ context, namespace, count: pods.length, pods });
});

route('GET', '/api/pods/logs', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const namespace = query.get('namespace') || 'default';
  const pod = query.get('pod');
  const tail = Number(query.get('tail') || 50);
  if (!pod) return bad('pod 参数必填');
  const r = await k8s.podLogs(context, namespace, pod, tail);
  return json({ ok: r.ok, pod, namespace, output: r.output });
});

route('GET', '/api/pods/describe', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const namespace = query.get('namespace') || 'default';
  const pod = query.get('pod');
  if (!pod) return bad('pod 参数必填');
  const r = await k8s.podDescribe(context, namespace, pod);
  return json({ ok: r.ok, pod, namespace, output: r.output });
});

route('GET', '/api/pods/describe/:context/:namespace/:pod', async ({ params }) => {
  const r = await k8s.podDescribe(params.context, params.namespace, params.pod);
  return json({ ok: r.ok, pod: params.pod, output: r.output });
});

/* ══════════════════════════════════════════════
   Deployment / HPA
══════════════════════════════════════════════ */

route('GET', '/api/hpa', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const namespace = query.get('namespace') || 'demo-app';
  return json({ hpa: await k8s.listHpa(context, namespace) });
});

route('GET', '/api/services', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const namespace = query.get('namespace') || 'default';
  return json({ services: await k8s.listServices(context, namespace) });
});

route('GET', '/api/helm', async () => json({ releases: await k8s.listHelmReleases() }));

route('POST', '/api/rollout-restart', async ({ body }) => {
  const {
    context = CONFIG.clusters.ops,
    namespace = 'demo-app',
    resource = 'deployment',
    name = 'demo-app',
  } = body;

  const r = await k8s.rolloutRestart(context, namespace, resource, name);
  alerts.pushEvent({
    action: 'rollout-restart',
    target: `${namespace}/${resource}/${name}`,
    ok: r.ok,
    message: r.message,
  });

  let status = null;
  if (r.ok) status = await k8s.rolloutStatus(context, namespace, resource, name, 30);

  return json({
    ok: r.ok,
    message: r.message,
    rollout: status,
    target: `${namespace}/${resource}/${name}`,
  });
});

route('POST', '/api/scale', async ({ body }) => {
  const {
    context = CONFIG.clusters.ops,
    namespace = 'demo-app',
    name = 'demo-app',
    replicas = 3,
  } = body;

  const r = await k8s.scaleDeployment(context, namespace, name, Number(replicas));
  alerts.pushEvent({
    action: 'scale',
    target: `${namespace}/deployment/${name}`,
    ok: r.ok,
    message: `→ ${replicas} 副本: ${r.message}`,
  });
  return json(r);
});

/* ══════════════════════════════════════════════
   ArgoCD
══════════════════════════════════════════════ */

route('GET', '/api/argocd/apps', async ({ query }) => {
  const context = query.get('context') || CONFIG.clusters.ops;
  const apps = await k8s.listArgoApps(context);
  return json({ context, count: apps.length, apps });
});

route('POST', '/api/argocd/sync', async ({ body }) => {
  const { context = CONFIG.clusters.ops, app = 'demo-app' } = body;
  const r = await k8s.syncArgoApp(context, app);
  alerts.pushEvent({
    action: 'argocd-sync',
    target: app,
    ok: r.ok,
    message: r.error || r.output,
  });
  return json({ app, ...r });
});

/* ══════════════════════════════════════════════
   告警
══════════════════════════════════════════════ */

route('GET', '/api/alerts', async () => json(alerts.snapshot()));
route('GET', '/api/alerts/refresh', async () => json(await alerts.refresh()));
route('GET', '/api/alerts/prometheus', async () => json(await k8s.fetchAlerts()));
route('GET', '/api/alerts/webhook', async () => json(alerts.snapshot().webhook));

route('POST', '/webhook/feishu', async ({ body, headers }) => {
  // 可选：共享密钥校验
  const expected = process.env.WEBHOOK_SECRET;
  if (expected && headers.get('x-webhook-secret') !== expected) {
    return { status: 401, data: { error: 'invalid secret' } };
  }
  const entry = alerts.pushWebhook(body);
  console.log(`[feishu] 收到消息: ${entry.text.slice(0, 120)}`);
  return json({ ok: true, id: entry.id, text: entry.text });
});

/* ══════════════════════════════════════════════
   Loki
══════════════════════════════════════════════ */

route('GET', '/api/loki/query', async ({ query }) => {
  const q = query.get('q') || '{namespace="demo-app"}';
  const limit = Number(query.get('limit') || 100);
  const seconds = Number(query.get('seconds') || 3600);
  return json(await k8s.lokiQuery(q, { limit, seconds }));
});

route('GET', '/api/loki/labels', async () => json({ labels: await k8s.lokiLabels() }));

/* ══════════════════════════════════════════════
   Prometheus 即席查询
══════════════════════════════════════════════ */

route('GET', '/api/prom/query', async ({ query }) => {
  const expr = query.get('expr') || 'up';
  return json(await k8s.promQuery(expr));
});

/* ══════════════════════════════════════════════
   终端（HTTP 侧）
══════════════════════════════════════════════ */

route('GET', '/api/terminal/sessions', async () => json({ sessions: listSessions() }));

route('POST', '/api/terminal/exec', async ({ body }) => {
  const { context = CONFIG.clusters.ops, namespace = 'default', args } = body;
  if (!Array.isArray(args) || !args.length) return bad('args 必填（数组）');
  const r = await execOnce(context, namespace, args);
  return json(r);
});

route('POST', '/api/terminal/destroy', async ({ body }) =>
  json({ destroyed: destroySession(body.sessionId) })
);

/* ══════════════════════════════════════════════
   导出
══════════════════════════════════════════════ */

export { routes, match, json, bad };

/** 打印所有已注册路由（启动时自检用） */
export function listRoutes() {
  return [...routes.keys()].sort();
}
