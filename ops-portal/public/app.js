/**
 * app.js — 前端主逻辑（ES Module，零框架）
 *
 * 分层：
 *   api.*     — 所有后端调用集中在这里
 *   store     — 全局状态
 *   render.*  — 每个页面的渲染函数
 *   actions   — 事件绑定
 */

const API = '';   // 同源，留空即可

/* ══════════════════════════════════════════════
   1. API 层
══════════════════════════════════════════════ */

async function req(path, opts = {}) {
  const url = `${API}${path}`;
  try {
    const res = await fetch(url, {
      headers: { 'Content-Type': 'application/json' },
      ...opts,
      body: opts.body ? JSON.stringify(opts.body) : undefined,
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
    return data;
  } catch (e) {
    if (e instanceof TypeError) {
      throw new Error('后端未连接（请运行 npm start）');
    }
    throw e;
  }
}

const api = {
  health:   ()               => req('/health'),
  config:   ()               => req('/api/config'),

  clusters: ()               => req('/api/clusters'),
  cluster:  (ctx)            => req(`/api/cluster/${encodeURIComponent(ctx)}`),
  namespaces:(ctx)           => req(`/api/namespaces?context=${encodeURIComponent(ctx)}`),

  pods:     (ctx, ns)        => req(`/api/pods?context=${encodeURIComponent(ctx)}&namespace=${encodeURIComponent(ns)}`),
  logs:     (ctx, ns, pod, tail=50) => req(`/api/logs?context=${encodeURIComponent(ctx)}&namespace=${encodeURIComponent(ns)}&pod=${encodeURIComponent(pod)}&tail=${tail}`),
  describe: (ctx, ns, pod)   => req(`/api/pods/describe?context=${encodeURIComponent(ctx)}&namespace=${encodeURIComponent(ns)}&pod=${encodeURIComponent(pod)}`),
  hpa:      (ctx, ns)        => req(`/api/hpa?context=${encodeURIComponent(ctx)}&namespace=${encodeURIComponent(ns)}`),
  services: (ctx, ns)        => req(`/api/services?context=${encodeURIComponent(ctx)}&namespace=${encodeURIComponent(ns)}`),
  helm:     ()               => req('/api/helm'),

  argoApps: (ctx)            => req(`/api/argocd/apps?context=${encodeURIComponent(ctx)}`),
  argoSync: (ctx, app)       => req('/api/argocd/sync', { method: 'POST', body: { context: ctx, app } }),

  restart:  (ctx, ns, res, name) =>
               req('/api/rollout-restart', { method: 'POST', body: { context: ctx, namespace: ns, resource: res, name } }),
  scale:    (ctx, ns, name, replicas) =>
               req('/api/scale', { method: 'POST', body: { context: ctx, namespace: ns, name, replicas } }),

  alerts:   ()               => req('/api/alerts'),
  alertsRefresh: ()          => req('/api/alerts/refresh'),

  loki:     (q, limit=100, seconds=3600) =>
               req(`/api/loki/query?q=${encodeURIComponent(q)}&limit=${limit}&seconds=${seconds}`),
  lokiLabels: ()             => req('/api/loki/labels'),

  exec:     (ctx, ns, args)  => req('/api/terminal/exec', { method: 'POST', body: { context: ctx, namespace: ns, args } }),
  sessions: ()               => req('/api/terminal/sessions'),
};

/* ══════════════════════════════════════════════
   2. 全局状态
══════════════════════════════════════════════ */

const store = {
  online: false,
  config: { clusters: [], namespaces: [] },
  clusters: [],
  alerts: null,
  autoRefresh: true,
  timer: null,
  page: 'overview',
  alertTab: 'firing',
  lokiAutoRun: false,
  podsAutoPicked: false,
  selected: {
    cluster: null,
    clusterPage: null,
    podsCluster: null,
    podsNamespace: 'default',
    gitopsCluster: null,
    termCluster: null,
    termNamespace: 'default',
  },
};

/* ══════════════════════════════════════════════
   3. 工具函数
══════════════════════════════════════════════ */

const $  = (sel) => document.querySelector(sel);
const $$ = (sel) => [...document.querySelectorAll(sel)];

const esc = (s) => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

function toast(msg, kind = 'info', ms = 3500) {
  const host = $('#toast-host');
  const el = document.createElement('div');
  el.className = `toast toast-${kind}`;
  el.textContent = msg;
  host.appendChild(el);
  setTimeout(() => el.remove(), ms);
}

function showModal(title, content) {
  $('#modal-title').textContent = title;
  $('#modal-body').textContent = content;
  $('#modal').classList.add('open');
}

function hideModal() { $('#modal').classList.remove('open'); }

function loading(text = '加载中…') {
  return `<div class="loading"><span class="spinner"></span>${esc(text)}</div>`;
}

function empty(icon, text) {
  return `<div class="empty"><div class="empty-icon">${icon}</div>${esc(text)}</div>`;
}

function copyText(text) {
  navigator.clipboard.writeText(text)
    .then(() => toast('已复制到剪贴板', 'ok', 1800))
    .catch(() => toast('复制失败', 'err'));
}

function fmtTime(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('zh-CN', { hour12: false });
}

function fmtAgo(iso) {
  if (!iso) return '—';
  const s = Math.round((Date.now() - new Date(iso)) / 1000);
  if (s < 60) return `${s}秒前`;
  if (s < 3600) return `${Math.round(s / 60)}分钟前`;
  if (s < 86400) return `${Math.round(s / 3600)}小时前`;
  return `${Math.round(s / 86400)}天前`;
}

function healthPill(health) {
  const map = { Healthy: 'pill-ok', Degraded: 'pill-err', Progressing: 'pill-warn', Suspended: 'pill-warn', Missing: 'pill-err' };
  return `<span class="pill ${map[health] || 'pill-neutral'}">${esc(health)}</span>`;
}
function syncPill(sync) {
  const map = { Synced: 'pill-ok', OutOfSync: 'pill-warn', Unknown: 'pill-neutral' };
  return `<span class="pill ${map[sync] || 'pill-neutral'}">${esc(sync)}</span>`;
}
function phasePill(phase) {
  const map = { Running: 'pill-ok', Pending: 'pill-warn', Failed: 'pill-err', Succeeded: 'pill-info', Unknown: 'pill-neutral' };
  return `<span class="pill ${map[phase] || 'pill-neutral'}">${esc(phase)}</span>`;
}

/* ══════════════════════════════════════════════
   4. 页面切换
══════════════════════════════════════════════ */

function goto(page) {
  store.page = page;
  history.replaceState(null, '', `#${page === 'overview' ? '' : page}`);
  $$('.nav-item').forEach((b) => b.classList.toggle('active', b.dataset.page === page));
  $$('.page').forEach((s) => s.classList.toggle('active', s.id === `page-${page}`));
  window.scrollTo(0, 0);

  // 懒加载：进页面才拉数据
  const loaders = {
    clusters:  loadClusterPage,
    pods:      loadPodsPage,
    gitops:    loadGitOps,
    // 进入日志页时自动跑一次默认查询（输入框本身就有预置 LogQL），
    // 否则直接打开这一页只能看到一个空壳
    logs:      () => { if (!store.lokiAutoRun) { store.lokiAutoRun = true; queryLoki(); } },
    alerts:    () => {},
    terminal:  loadTerminalForm,
    links:     renderLinks,
    tools:     renderLinks,
  };
  loaders[page]?.();
}

/* ══════════════════════════════════════════════
   5. 概览页
══════════════════════════════════════════════ */

async function renderOverview() {
  $('#overview-alerts').innerHTML = loading();
  try {
    const d = await api.clusters();
    store.clusters = d.clusters;

    // 指标
    $('#m-nodes').textContent = d.totals.readyNodes;
    $('#m-nodes-sub').textContent = `${d.totals.readyNodes} / ${d.totals.totalNodes} Ready`;
    $('#m-pods').textContent = d.totals.totalPods;
    $('#m-pods-sub').textContent = '全集群合计';

    // 集群卡片
    $('#cluster-cards').innerHTML = d.clusters.map((c, i) => {
      const meta = store.config.clusters[i] || {};
      const healthy = c.readyNodes === c.totalNodes;
      return `
        <div class="cluster-card" data-cluster-idx="${i}">
          <div class="flex-center gap6">
            <span class="cluster-name">${esc(meta.name || c.context)}</span>
            <span class="badge ${healthy ? 'badge-ok' : 'badge-warn'}">
              <span class="badge-dot"></span>${healthy ? '健康' : '异常'}
            </span>
          </div>
          <div class="cluster-role">${esc(meta.role || '')} · ${esc(c.context)}</div>
          ${c.nodes.map((n) => `
            <div class="node-row">
              <span class="node-dot ${n.ready ? 'dot-ok' : 'dot-err'}"></span>
              <span class="node-name" title="${esc(n.name)}">${esc(n.name)}</span>
              <span class="node-role ${n.role === 'control-plane' ? 'role-cp' : 'role-w'}">
                ${n.role === 'control-plane' ? 'CP' : 'W'}
              </span>
              <span class="node-ver">${esc(n.version)}</span>
            </div>`).join('')}
        </div>`;
    }).join('');

    $$('#cluster-cards .cluster-card').forEach((el) => {
      el.addEventListener('click', () => {
        const c = d.clusters[Number(el.dataset.clusterIdx)];
        store.selected.clusterPage = c.context;
        $('#cluster-select').value = c.context;
        goto('clusters');
      });
    });
  } catch (e) {
    $('#cluster-cards').innerHTML = empty('⚠️', e.message);
  }

  await renderAlerts();
}

async function renderAlerts() {
  try {
    const a = await api.alerts();
    store.alerts = a;

    // 指标
    const total = a.total || 0;
    $('#m-alerts').textContent = total;
    $('#m-alerts').className = `metric-value ${total === 0 ? 'ok' : total < 5 ? 'warn' : 'err'}`;
    $('#m-alerts-sub').textContent = a.prometheus.error
      ? '⚠️ Prometheus 未连接'
      : `PM ${a.prometheus.count} · 飞书 ${a.webhook.alertCount}`;

    // 导航角标
    const badge = $('#alert-count');
    badge.textContent = total;
    badge.classList.toggle('hidden', total === 0);

    // 概览告警列表
    const list = $('#overview-alerts');
    const items = [
      ...(a.prometheus.firing || []).map((x) => ({ ...x, _src: 'prometheus' })),
      ...(a.webhook.recent || []).filter((w) => /alert|告警|critical|error/i.test(w.text))
        .map((w) => ({ state: 'firing', labels: { alertname: '飞书推送' }, annotations: { summary: w.text }, _src: 'webhook', activeAt: w.time })),
    ];
    list.innerHTML = items.length === 0
      ? empty('✅', '没有活跃告警')
      : items.slice(0, 6).map(alertItemHTML).join('');

    // 操作事件
    const evBox = $('#overview-events');
    $('#overview-events-count').textContent = a.events.count ? `${a.events.count} 条` : '';
    evBox.innerHTML = a.events.recent.length === 0
      ? empty('⚡', '还没有操作记录')
      : `<div class="timeline">${a.events.recent.map((e) => `
          <div class="tl-item ${e.ok ? 'ok' : 'err'}">
            <div class="tl-time">${fmtTime(e.time)} · ${esc(e.action)}</div>
            <div class="tl-text">${esc(e.target)} ${e.ok ? '✅' : '❌'}</div>
            ${e.message ? `<div class="tl-text small dim">${esc(e.message.slice(0, 120))}</div>` : ''}
          </div>`).join('')}</div>`;

    // 告警页
    renderAlertTabs(a);
  } catch (e) {
    $('#overview-alerts').innerHTML = empty('⚠️', e.message);
  }
}

function alertItemHTML(x) {
  const lab = x.labels || {};
  const ann = x.annotations || {};
  const src = x._src === 'webhook' ? '飞书' : 'Prometheus';
  return `
    <div class="alert-item">
      <span class="pill ${x.state === 'firing' ? 'pill-err' : 'pill-warn'}">
        ${x.state === 'firing' ? '🔴' : '🟡'} ${esc(lab.severity || x.state)}
      </span>
      <span class="pill pill-neutral">${src}</span>
      <div class="alert-title">${esc(lab.alertname || ann.summary || '未命名告警')}</div>
      ${ann.summary && ann.summary !== lab.alertname
        ? `<div class="alert-desc">${esc(ann.summary)}</div>` : ''}
      <div class="alert-labels">
        ${Object.entries(lab).filter(([k]) => k !== 'alertname').slice(0, 6)
          .map(([k, v]) => `<span class="label-chip">${esc(k)}=${esc(v)}</span>`).join('')}
      </div>
      <div class="small dim mt8">${fmtAgo(x.activeAt)}</div>
    </div>`;
}

function renderAlertTabs(a) {
  // firing
  const firing = [...(a.prometheus.firing || []), ...(a.prometheus.pending || [])];
  $('#alerts-firing').innerHTML = a.prometheus.error
    ? `<div class="notice notice-warn" style="margin:16px;">
         <span class="notice-icon">⚠️</span>
         <div><strong>Prometheus 未连接</strong><br>${esc(a.prometheus.error)}<br>
         <code>浏览器打开 http://localhost:30090（NodePort 直连）</code></div>
       </div>`
    : firing.length === 0
      ? empty('✅', '没有告警')
      : firing.map(alertItemHTML).join('');

  // webhook
  $('#webhook-count').textContent = `${a.webhook.count} 条消息`;
  $('#alerts-webhook').innerHTML = a.webhook.count === 0
    ? empty('📨', '暂无飞书消息')
    : `<div class="list-row" style="padding:10px 16px;">
         <span class="pill pill-info">Webhook</span>
         <div class="list-main"><div class="list-meta">端点 <code>POST /webhook/feishu</code></div>
         <div class="small dim">在"接入配置"标签页可以发送测试消息</div></div>
       </div>
       ${a.webhook.recent.map((w) => `
         <div class="list-row" style="align-items:flex-start;">
           <span class="pill ${/alert|告警|critical|error/i.test(w.text) ? 'pill-err' : 'pill-neutral'}">${esc(w.msgType)}</span>
           <div class="list-main">
             <div class="list-name" style="font-family:inherit;white-space:normal;">${esc(w.text)}</div>
             <div class="list-meta">${fmtTime(w.time)} · ${fmtAgo(w.time)}</div>
           </div>
         </div>`).join('')}`;

  // events
  $('#alerts-events').innerHTML = a.events.count === 0
    ? empty('⚡', '还没有操作')
    : `<div class="timeline">${a.events.recent.concat().reverse().map((e) => `
        <div class="tl-item ${e.ok ? 'ok' : 'err'}">
          <div class="tl-time">${fmtTime(e.time)} · ${esc(e.action)}</div>
          <div class="tl-text"><code>${esc(e.target)}</code> ${e.ok ? '✅ 成功' : '❌ 失败'}</div>
          ${e.message ? `<div class="tl-text small dim">${esc(e.message.slice(0, 160))}</div>` : ''}
        </div>`).join('')}</div>`;

  // prom status
  $('#prom-status').innerHTML = a.prometheus.error
    ? `<div class="notice notice-warn" style="margin:0;">
         <span class="notice-icon">⚠️</span>
         <div>${esc(a.prometheus.error)}<br><code>浏览器打开 http://localhost:30090（NodePort 直连）</code></div>
       </div>`
    : `<div class="grid g3">
         <div class="metric"><div class="metric-value ok">${a.prometheus.count}</div><div class="metric-label">Firing</div></div>
         <div class="metric"><div class="metric-value warn">${a.prometheus.pending.length}</div><div class="metric-label">Pending</div></div>
         <div class="metric"><div class="metric-value info">${a.webhook.count}</div><div class="metric-label">飞书消息</div></div>
       </div>
       <div class="small dim mt8">端点 ${esc(a.prometheus.endpoint)} · 更新于 ${fmtTime(a.prometheus.fetchedAt)}</div>`;
}

/* ══════════════════════════════════════════════
   6. 集群页
══════════════════════════════════════════════ */

async function loadClusterPage() {
  const ctx = store.selected.clusterPage || store.selected.cluster;
  if (!ctx) return;
  $('#cluster-nodes').innerHTML = loading();
  $('#cluster-ns').innerHTML = loading();

  try {
    const d = await api.cluster(ctx);
    $('#cluster-fresh').textContent = `更新于 ${new Date().toLocaleTimeString('zh-CN', { hour12: false })}`;

    $('#cluster-nodes').innerHTML = `
      <div class="flex-center gap6 mb12">
        <span class="badge ${d.readyNodes === d.totalNodes ? 'badge-ok' : 'badge-warn'}">
          <span class="badge-dot"></span>${d.readyNodes}/${d.totalNodes} Ready
        </span>
        <span class="badge badge-info">${d.totalPods} Pods</span>
      </div>
      ${d.nodes.map((n) => `
        <div class="node-row">
          <span class="node-dot ${n.ready ? 'dot-ok' : 'dot-err'}"></span>
          <span class="node-name" title="${esc(n.name)}">${esc(n.name)}</span>
          <span class="node-role ${n.role === 'control-plane' ? 'role-cp' : 'role-w'}">
            ${n.role === 'control-plane' ? 'CP' : 'W'}</span>
        </div>
        <div class="small dim" style="padding:2px 0 8px 15px;">
          ${esc(n.osImage)} · CPU ${esc(n.cpu)} · MEM ${esc(n.memory)} · Pods ${esc(n.pods)}
        </div>`).join('')}`;

    const ns = Object.entries(d.namespaceStats).sort((a, b) => b[1].total - a[1].total);
    $('#cluster-ns').innerHTML = ns.length === 0 ? empty('📦', '没有 Pod')
      : ns.map(([name, s]) => `
        <div class="list-row">
          <div class="list-main">
            <div class="list-name">${esc(name)}</div>
            <div class="list-meta">
              <span>总计 ${s.total}</span>
              <span style="color:var(--green)">运行 ${s.running}</span>
              ${s.pending ? `<span style="color:var(--yellow)">等待 ${s.pending}</span>` : ''}
              ${s.failed ? `<span style="color:var(--red)">失败 ${s.failed}</span>` : ''}
            </div>
          </div>
          <button class="btn btn-sm" data-ns="${esc(name)}">查看</button>
        </div>`).join('');

    $$('#cluster-ns [data-ns]').forEach((b) => b.addEventListener('click', () => {
      store.selected.podsCluster = ctx;
      store.selected.podsNamespace = b.dataset.ns;
      goto('pods');
    }));
  } catch (e) {
    $('#cluster-nodes').innerHTML = empty('⚠️', e.message);
  }

  // helm
  try {
    const h = await api.helm();
    $('#cluster-helm').innerHTML = h.releases.length === 0 ? empty('📦', '没有 Helm release')
      : h.releases.map((r) => `
        <div class="list-row">
          <div class="list-main">
            <div class="list-name">${esc(r.name)}</div>
            <div class="list-meta"><span>${esc(r.namespace)}</span><span>rev ${r.revision}</span><span>${fmtAgo(r.updated)}</span></div>
          </div>
          <span class="pill ${r.status === 'deployed' ? 'pill-ok' : 'pill-warn'}">${esc(r.status)}</span>
        </div>`).join('');
  } catch {
    $('#cluster-helm').innerHTML = empty('⚠️', 'Helm 查询失败');
  }
}

/* ══════════════════════════════════════════════
   7. Pods 页
══════════════════════════════════════════════ */

async function loadPodsPage() {
  const ctx = store.selected.podsCluster;
  if (!ctx) return;
  const sel = $('#pods-namespace');
  // 下拉默认第一项是 default，往往是空命名空间。
  // 自动进入本页时（而非用户主动点查询）逐个找一个真有 Pod 的命名空间，
  // 免得每次进来都是「命名空间 default 没有 Pod」
  if (!store.podsAutoPicked) {
    store.podsAutoPicked = true;
    for (const opt of [...sel.options]) {
      sel.value = opt.value;
      const d = await api.pods(ctx, opt.value);
      if (d.ok !== false && (d.pods || []).length > 0) break;
    }
  }
  await queryPods();
}

async function queryPods() {
  const ctx = $('#pods-cluster').value;
  const ns = $('#pods-namespace').value;
  store.selected.podsCluster = ctx;
  store.selected.podsNamespace = ns;

  $('#pods-list').innerHTML = `<div style="padding:16px;">${loading()}</div>`;
  try {
    const d = await api.pods(ctx, ns);
    const running = d.pods.filter((p) => p.phase === 'Running').length;
    const bad = d.pods.filter((p) => p.phase === 'Failed').length;
    const restarts = d.pods.reduce((s, p) => s + p.restarts, 0);

    $('#pods-summary').innerHTML =
      `<span class="pill pill-ok">${running} Running</span> ` +
      (bad ? `<span class="pill pill-err">${bad} Failed</span> ` : '') +
      (restarts ? `<span class="pill pill-warn">${restarts} 重启</span>` : '') +
      `<span class="dim">共 ${d.pods.length}</span>`;

    $('#pods-list').innerHTML = d.pods.length === 0 ? empty('📦', `命名空间 ${ns} 没有 Pod`)
      : d.pods.map((p) => `
        <div class="list-row">
          ${phasePill(p.phase)}
          <div class="list-main">
            <div class="list-name">${esc(p.name)}</div>
            <div class="list-meta">
              <span>${esc(p.ready)}</span>
              <span>${esc(p.image)}:${esc(p.imageTag || 'latest')}</span>
              <span>${esc(p.node)}</span>
              <span>${esc(p.age)}</span>
            </div>
          </div>
          ${p.restarts > 2 ? `<span class="pill pill-warn">↻${p.restarts}</span>` : ''}
          <button class="btn btn-sm" data-log="${esc(p.name)}" title="查看日志">📋</button>
          <button class="btn btn-sm" data-desc="${esc(p.name)}" title="describe 详情">🔍</button>
          <button class="btn btn-sm" data-exec="${esc(p.name)}" title="进入终端">💻</button>
        </div>`).join('');

    $$('#pods-list [data-log]').forEach((b) => b.addEventListener('click', () => showPodLogs(ctx, ns, b.dataset.log)));
    $$('#pods-list [data-desc]').forEach((b) => b.addEventListener('click', () => showPodDescribe(ctx, ns, b.dataset.desc)));
    $$('#pods-list [data-exec]').forEach((b) => b.addEventListener('click', () => {
      store.selected.termCluster = ctx;
      store.selected.termNamespace = ns;
      goto('terminal');
      $('#term-cluster').value = ctx;
      $('#term-namespace').value = ns;
      $('#term-pod').value = b.dataset.exec;
    }));

    // demo-app 时顺带拉 HPA / Services
    if (ns === 'demo-app') {
      loadHpa(ctx, ns);
      loadServices(ctx, ns);
    } else {
      $('#hpa-card').classList.add('hidden');
      $('#svc-card').classList.add('hidden');
    }
  } catch (e) {
    $('#pods-list').innerHTML = empty('⚠️', e.message);
  }
}

async function loadHpa(ctx, ns) {
  try {
    const d = await api.hpa(ctx, ns);
    const card = $('#hpa-card');
    if (d.hpa.length === 0) { card.classList.add('hidden'); return; }
    card.classList.remove('hidden');
    $('#hpa-list').innerHTML = d.hpa.map((h) => `
      <div class="list-row">
        <div class="list-main">
          <div class="list-name">${esc(h.name)}</div>
          <div class="list-meta">
            <span>当前 ${h.currentReplicas}</span>
            <span>期望 ${h.desiredReplicas}</span>
            <span>范围 ${h.minReplicas}~${h.maxReplicas}</span>
            ${h.targetCPU ? `<span>CPU ${h.targetCPU}%</span>` : ''}
          </div>
        </div>
        <span class="pill ${h.currentReplicas > h.maxReplicas ? 'pill-warn' : 'pill-ok'}">${h.currentReplicas} 副本</span>
      </div>`).join('');
  } catch { $('#hpa-card').classList.add('hidden'); }
}

async function loadServices(ctx, ns) {
  try {
    const d = await api.services(ctx, ns);
    const card = $('#svc-card');
    if (d.services.length === 0) { card.classList.add('hidden'); return; }
    card.classList.remove('hidden');
    $('#svc-list').innerHTML = d.services.map((s) => `
      <div class="list-row">
        <span class="pill ${s.type === 'NodePort' ? 'pill-purple' : s.type === 'LoadBalancer' ? 'pill-warn' : 'pill-info'}">${esc(s.type)}</span>
        <div class="list-main">
          <div class="list-name">${esc(s.name)}</div>
          <div class="list-meta">
            <span>ClusterIP ${esc(s.clusterIP)}</span>
            ${s.ports.map((p) => `<span>${p.port}${p.nodePort ? `→${p.nodePort}` : ''}${p.targetPort ? `/${p.targetPort}` : ''}</span>`).join('')}
          </div>
        </div>
      </div>`).join('');
  } catch { $('#svc-card').classList.add('hidden'); }
}

async function showPodLogs(ctx, ns, pod) {
  showModal(`Pod 日志 — ${pod}`, '加载中…');
  try {
    const d = await api.logs(ctx, ns, pod, 100);
    $('#modal-body').textContent = d.output || d.output === '' ? (d.output || '(无输出)') : d.output;
  } catch (e) {
    $('#modal-body').textContent = `错误: ${e.message}`;
  }
}

async function showPodDescribe(ctx, ns, pod) {
  showModal(`Pod 详情 — ${pod}`, '加载中…');
  try {
    const d = await api.describe(ctx, ns, pod);
    $('#modal-body').textContent = d.output || '(无输出)';
  } catch (e) {
    $('#modal-body').textContent = `错误: ${e.message}`;
  }
}

/* ══════════════════════════════════════════════
   8. GitOps 页
══════════════════════════════════════════════ */

async function loadGitOps() {
  const ctx = store.selected.gitopsCluster || store.selected.cluster;
  if (!ctx) return;
  const box = $('#gitops-apps');
  box.innerHTML = `<div class="card"><div class="card-body">${loading()}</div></div>`;

  try {
    const d = await api.argoApps(ctx);
    if (d.apps.length === 0) {
      box.innerHTML = `<div class="card"><div class="card-body">${
        empty('🔄', `集群 ${ctx} 的 argocd 命名空间没有 Application CRD`)}</div></div>`;
      $('#m-apps').textContent = '0';
      return;
    }

    $('#m-apps').textContent = d.apps.length;
    const healthy = d.apps.filter((a) => a.health === 'Healthy').length;
    $('#m-apps-sub').textContent = `${healthy}/${d.apps.length} Healthy`;

    box.innerHTML = d.apps.map((a) => `
      <div class="card mb12">
        <div class="card-body">
          <div class="app-head">
            ${healthPill(a.health)}
            ${syncPill(a.sync)}
            ${a.autoSync ? '<span class="pill pill-info">auto-sync</span>' : '<span class="pill pill-neutral">manual</span>'}
            ${a.selfHeal ? '<span class="pill pill-info">self-heal</span>' : ''}
            <span class="app-name">${esc(a.name)}</span>
            <button class="btn btn-sm btn-primary" data-sync="${esc(a.name)}">🔄 同步</button>
          </div>
          <div class="app-grid">
            <div><div class="app-field-label">仓库</div><div class="app-field-value">${esc(a.repo || '—')}</div></div>
            <div><div class="app-field-label">路径</div><div class="app-field-value">${esc(a.path || '—')}</div></div>
            <div><div class="app-field-label">目标分支</div><div class="app-field-value">${esc(a.targetRevision || '—')}</div></div>
            <div><div class="app-field-label">当前 revision</div><div class="app-field-value">${esc(a.revision || '—')}</div></div>
            <div><div class="app-field-label">命名空间</div><div class="app-field-value">${esc(a.namespace)}</div></div>
            <div><div class="app-field-label">最后同步</div><div class="app-field-value">${esc(a.lastSyncAt || '—')}</div></div>
          </div>
        </div>
      </div>`).join('');

    $$('#gitops-apps [data-sync]').forEach((b) =>
      b.addEventListener('click', () => doArgoSync(ctx, b.dataset.sync)));
  } catch (e) {
    box.innerHTML = `<div class="card"><div class="card-body">${empty('⚠️', e.message)}</div></div>`;
  }
}

async function doArgoSync(ctx, app) {
  toast(`正在同步 ${app}…`, 'info');
  try {
    const d = await api.argoSync(ctx, app);
    if (d.ok) {
      toast(`${app} 同步成功`, 'ok');
    } else {
      toast(`${app} 同步失败`, 'err', 6000);
      if (d.output || d.error) showModal(`同步输出 — ${app}`, `${d.output || ''}\n${d.error || ''}`);
    }
  } catch (e) {
    toast(`同步失败: ${e.message}`, 'err', 6000);
  }
  setTimeout(loadGitOps, 1500);
}

async function gitopsAction(action) {
  const ctx = store.selected.gitopsCluster;
  switch (action) {
    case 'sync': {
      const app = prompt('要同步哪个应用？', 'demo-app');
      if (app) doArgoSync(ctx, app.trim());
      break;
    }
    case 'restart':
      doRestart();
      break;
    case 'history':
      try {
        const r = await api.exec(ctx, 'argocd', [
          'get', 'application', 'demo-app',
          '-o', 'jsonpath={.status.history[*].deployedAt}',
        ]);
        showModal('demo-app 同步历史', r.stdout || '(无历史记录)');
      } catch (e) { toast(e.message, 'err'); }
      break;
    case 'diff':
      try {
        const r = await api.exec(ctx, 'argocd', [
          'get', 'application', 'demo-app', '-o', 'yaml',
        ]);
        showModal('demo-app Application 定义', r.stdout || '(无输出)');
      } catch (e) { toast(e.message, 'err'); }
      break;
    case 'open-argocd':
      window.open('http://localhost:31773', '_blank', 'noopener');
      break;
    case 'open-grafana':
      window.open('http://localhost:30300', '_blank', 'noopener');
      break;
  }
}

async function syncAllApps() {
  const ctx = store.selected.gitopsCluster;
  try {
    const d = await api.argoApps(ctx);
    if (d.apps.length === 0) return toast('没有应用可同步', 'warn');
    toast(`开始同步 ${d.apps.length} 个应用…`, 'info');
    for (const a of d.apps) {
      await api.argoSync(ctx, a.name).catch(() => {});
      await new Promise((r) => setTimeout(r, 800));
    }
    toast('全部同步完成', 'ok');
  } catch (e) {
    toast(e.message, 'err');
  }
  loadGitOps();
}

/* ══════════════════════════════════════════════
   9. 日志页
══════════════════════════════════════════════ */

async function queryLoki() {
  const q = $('#loki-input').value.trim() || '{namespace="demo-app"}';
  const limit = Number($('#logs-limit').value);
  const seconds = Number($('#logs-window').value);
  const box = $('#loki-output');
  box.innerHTML = loading('查询中…');

  try {
    const d = await api.loki(q, limit, seconds);
    if (!d.ok) {
      box.innerHTML = `<div class="notice notice-warn" style="margin:0;">
        <span class="notice-icon">⚠️</span>
        <div><strong>Loki 未连接</strong><br>${esc(d.error || '')}<br>
        <code>浏览器打开 http://localhost:30212（NodePort 直连）</code></div>
      </div>`;
      $('#logs-summary').textContent = '';
      return;
    }
    $('#logs-summary').textContent = `${d.count} 行 · ${limit} 限制 · ${seconds / 60} 分钟窗口`;
    box.innerHTML = d.lines.length === 0
      ? empty('📋', '没有匹配的日志')
      : d.lines.slice().reverse().map((l) => {
          const cls = /error|err\b|fatal|exception/i.test(l.line) ? 'log-text-error'
                    : /warn/i.test(l.line) ? 'log-text-warn' : 'log-text-info';
          return `<div class="log-line">
            <span class="log-time">${esc(l.time)}</span>
            ${l.pod ? `<span class="log-pod">${esc(l.pod)}</span>` : ''}
            <span class="${cls}">${esc(l.line)}</span>
          </div>`;
        }).join('');
  } catch (e) {
    box.innerHTML = empty('⚠️', e.message);
  }
}

/* ══════════════════════════════════════════════
   10. 终端页
══════════════════════════════════════════════ */

let ws = null;
let wsSession = null;

function termLog(text, cls = '') {
  const out = $('#term-output');
  const line = document.createElement('div');
  line.className = `term-line ${cls}`;
  line.textContent = text;
  out.appendChild(line);
  out.scrollTop = out.scrollHeight;
}

function setTermStatus(state, text) {
  const el = $('#term-status');
  const map = { connected: 'badge-ok', connecting: 'badge-info', error: 'badge-err', idle: 'badge-neutral' };
  el.className = `badge ${map[state] || 'badge-neutral'}`;
  el.innerHTML = `<span class="badge-dot"></span> ${esc(text)}`;
}

async function loadTerminalForm() {
  const ctx = $('#term-cluster').value;
  const ns = $('#term-namespace').value;
  // 拉 Pod 列表作为自动补全
  try {
    const d = await api.pods(ctx, ns);
    const running = d.pods.filter((p) => p.phase === 'Running');
    if (running.length > 0 && !$('#term-pod').value) {
      $('#term-pod').placeholder = `留空自动选: ${running[0].name}`;
    }
  } catch { /* 忽略 */ }
}

async function connectTerminal() {
  const ctx = $('#term-cluster').value;
  const ns = $('#term-namespace').value;
  let pod = $('#term-pod').value.trim();

  $('#term-output').innerHTML = '';
  termLog('正在连接…', 'dim');

  // pod 留空 → 自动选第一个 Running
  if (!pod) {
    try {
      const d = await api.pods(ctx, ns);
      const p = d.pods.find((x) => x.phase === 'Running');
      if (!p) { termLog(`命名空间 ${ns} 没有 Running 的 Pod`, 'warn'); return; }
      pod = p.name;
      $('#term-pod').value = pod;
    } catch (e) {
      termLog(`获取 Pod 列表失败: ${e.message}`, 'err');
      return;
    }
  }

  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws/term`);

  ws.onopen = () => {
    setTermStatus('connecting', '连接中');
    termLog('WebSocket 已建立，请求 shell…', 'dim');
    ws.send(JSON.stringify({ type: 'create', context: ctx, namespace: ns, pod }));
  };

  ws.onmessage = (evt) => {
    let m;
    try { m = JSON.parse(evt.data); }
    catch { termLog(evt.data); return; }

    switch (m.type) {
      case 'hello':
        termLog(m.data, 'dim');
        break;
      case 'ready':
        wsSession = m.sessionId;
        setTermStatus('connected', '已连接');
        $('#term-target').textContent = ` ${ctx} / ${ns} / ${pod}`;
        $('#btn-term-connect').disabled = true;
        $('#btn-term-disconnect').disabled = false;
        $('#term-input').disabled = false;
        $('#btn-term-send').disabled = false;
        termLog(`已进入 ${ns}/${pod}，输入命令后回车执行\n`, 'ok');
        break;
      case 'data':
        (m.data.match(/[^\n]*\n|[^\n]+/g) || [m.data]).forEach((l) => termLog(l));
        break;
      case 'error':
        termLog(m.data, 'err');
        break;
      case 'exit':
        termLog(m.data, 'warn');
        setTermStatus('idle', '已断开');
        resetTermButtons();
        break;
      case 'result':
        termLog(m.data, m.ok ? '' : 'err');
        break;
    }
  };

  ws.onerror = () => termLog('WebSocket 错误', 'err');
  ws.onclose = () => {
    setTermStatus('idle', '未连接');
    resetTermButtons();
  };
}

function resetTermButtons() {
  $('#btn-term-connect').disabled = false;
  $('#btn-term-disconnect').disabled = true;
  $('#term-input').disabled = true;
  $('#btn-term-send').disabled = true;
  wsSession = null;
}

function disconnectTerminal() {
  if (ws) { try { ws.send(JSON.stringify({ type: 'close' })); } catch {} ws.close(); }
  resetTermButtons();
  termLog('已断开', 'warn');
}

function sendTermInput() {
  const input = $('#term-input');
  const cmd = input.value.trim();
  if (!cmd || !ws || ws.readyState !== WebSocket.OPEN) return;
  termLog(`$ ${cmd}`, 'cmd');
  ws.send(JSON.stringify({ type: 'input', data: `${cmd}\n` }));
  input.value = '';
}

async function quickExec() {
  const ctx = $('#term-cluster').value;
  const ns = $('#term-namespace').value;
  const raw = $('#quick-cmd').value.trim();
  if (!raw) return;
  const args = raw.split(/\s+/);
  const pre = $('#quick-output');
  pre.style.display = 'block';
  pre.textContent = `$ kubectl ${args.join(' ')}  (${ctx} / ${ns})\n\n执行中…`;
  try {
    const d = await api.exec(ctx, ns, args);
    pre.textContent = `$ kubectl ${args.join(' ')}\n(${ctx} / ${ns}, exit=${d.code})\n\n${d.stdout}${d.stderr ? `\n[stderr]\n${d.stderr}` : ''}`;
  } catch (e) {
    pre.textContent = `错误: ${e.message}`;
  }
}

/* ══════════════════════════════════════════════
   11. 工具链接页
══════════════════════════════════════════════ */

const TOOLS = [
  { name: 'Ops Portal', url: '', desc: '本平台', cred: '—', icon: '⚙️' },
  { name: 'Grafana', url: 'http://localhost:30300', desc: '可视化 + 日志', cred: 'admin / sQrlls83VtTlkHU0bL2vVstGbaJ4oeToSNkwYM2b', icon: '📈' },
  { name: 'ArgoCD', url: 'http://localhost:31773', desc: 'GitOps 控制台', cred: 'admin / wG0YYYIbLXX31dVf', icon: '🔄' },
  { name: 'Prometheus', url: 'http://localhost:30090', desc: '指标 + 告警规则', cred: '—（NodePort）', icon: '📊' },
  { name: 'Alertmanager', url: 'http://localhost:30093', desc: '告警路由', cred: '—（NodePort）', icon: '🔔' },
  { name: 'Loki', url: 'http://localhost:30212', desc: '日志查询 API', cred: '—（NodePort）', icon: '📋' },
  { name: 'GitLab', url: 'https://gitlab.com', desc: 'CI/CD 平台', cred: '在线版', icon: '🦊' },
  { name: '飞书文档', url: 'https://my.feishu.cn/docx/KyfgdKymPokFgzxT6Ljc3auGnpg', desc: '使用手册', cred: '—', icon: '📖' },
  { name: '飞书故障手册', url: 'https://my.feishu.cn/docx/CNwudFGMnocYvRxjLngcFGaYnFh', desc: '应急处理', cred: '—', icon: '🛠️' },
];

function renderLinks() {
  $('#links-grid').innerHTML = TOOLS.map((t) => `
    <div class="card">
      <div class="card-body">
        <div class="flex-center gap10 mb8">
          <span style="font-size:24px;">${t.icon}</span>
          <div>
            <div style="font-weight:700;font-size:15px;color:#fff;">${esc(t.name)}</div>
            <div class="small dim">${esc(t.desc)}</div>
          </div>
        </div>
        ${t.url
          ? `<div class="flex-center gap6 mb8">
               <span class="chip" style="flex:1;overflow:hidden;text-overflow:ellipsis;">${esc(t.url)}</span>
               <button class="btn btn-sm" data-open="${esc(t.url)}">打开</button>
             </div>`
          : ''}
        <div class="small dim">凭据：<code>${esc(t.cred)}</code></div>
      </div>
    </div>`).join('');

  $$('#links-grid [data-open]').forEach((b) =>
    b.addEventListener('click', () => window.open(b.dataset.open, '_blank', 'noopener')));
}

/* ══════════════════════════════════════════════
   12. 操作按钮
══════════════════════════════════════════════ */

async function doRestart() {
  const ctx = store.selected.podsCluster;
  const ns = store.selected.podsNamespace;
  if (!ctx) return toast('请先选择集群', 'warn');
  toast('滚动重启中…', 'info');
  try {
    const d = await api.restart(ctx, ns, 'deployment', 'demo-app');
    if (d.ok) {
      toast('滚动重启已触发', 'ok');
      if (d.rollout) showModal('rollout 状态', d.rollout.message);
      setTimeout(queryPods, 3000);
    } else {
      toast('重启失败', 'err');
    }
  } catch (e) { toast(e.message, 'err'); }
  renderAlerts();
}

async function doScale(replicas) {
  const ctx = store.selected.podsCluster;
  const ns = store.selected.podsNamespace;
  if (!ctx) return toast('请先选择集群', 'warn');
  toast(`扩容到 ${replicas} 副本…`, 'info');
  try {
    const d = await api.scale(ctx, ns, 'demo-app', replicas);
    if (d.ok) { toast(`已设为 ${replicas} 副本`, 'ok'); setTimeout(queryPods, 2500); }
    else toast('扩缩容失败', 'err');
  } catch (e) { toast(e.message, 'err'); }
  renderAlerts();
}

async function sendTestWebhook() {
  const url = $('#webhook-url').textContent.trim();
  try {
    await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        msg_type: 'text',
        content: { text: `[测试] demo-app Pod 重启次数超过阈值 — ${new Date().toLocaleString('zh-CN')}` },
      }),
    });
    toast('测试消息已发送', 'ok');
    setTimeout(renderAlerts, 800);
  } catch (e) {
    toast(`发送失败: ${e.message}`, 'err');
  }
}

const AM_CONFIG = `receivers:
  - name: feishu
    webhook_configs:
      - url: http://WEBHOOK_HOST:8099/webhook/feishu
        send_resolved: true

route:
  receiver: feishu
  group_wait: 10s
  group_interval: 5m
  repeat_interval: 4h
`;

/* ══════════════════════════════════════════════
   13. 健康检查 + 自动刷新
══════════════════════════════════════════════ */

async function checkHealth() {
  try {
    const h = await api.health();
    store.online = true;
    $('#proxy-badge').className = 'badge badge-ok';
    $('#proxy-text').textContent = '后端在线';
    $('#uptime-badge').textContent = `⏱ ${formatUptime(h.uptimeSec)}`;
    $('#banner-offline').classList.remove('active');
    $('#uptime-badge').classList.remove('hidden');
    return true;
  } catch {
    store.online = false;
    $('#proxy-badge').className = 'badge badge-err';
    $('#proxy-text').textContent = '后端离线';
    $('#banner-offline').classList.add('active');
    return false;
  }
}

function formatUptime(sec) {
  if (sec < 60) return `${sec}秒`;
  if (sec < 3600) return `${Math.floor(sec / 60)}分`;
  if (sec < 86400) return `${Math.floor(sec / 3600)}时${Math.floor((sec % 3600) / 60)}分`;
  return `${Math.floor(sec / 86400)}天`;
}

async function refreshAll() {
  if (!store.online && !(await checkHealth())) return;
  const jobs = [];
  if (store.page === 'overview') jobs.push(renderOverview());
  if (store.page === 'alerts') jobs.push(renderAlerts());
  if (store.page === 'gitops') jobs.push(loadGitOps());
  await Promise.allSettled(jobs);
}

function toggleAuto() {
  store.autoRefresh = !store.autoRefresh;
  const btn = $('#btn-auto');
  btn.textContent = store.autoRefresh ? '⏸ 暂停' : '▶ 继续';
  if (store.autoRefresh) startAuto(); else stopAuto();
}

function startAuto() {
  stopAuto();
  store.timer = setInterval(refreshAll, 30000);
}
function stopAuto() {
  if (store.timer) clearInterval(store.timer);
  store.timer = null;
}

/* ══════════════════════════════════════════════
   14. 初始化
══════════════════════════════════════════════ */

async function init() {
  // 事件绑定
  $$('.nav-item').forEach((b) => b.addEventListener('click', () => goto(b.dataset.page)));
  $$('[data-goto]').forEach((b) => b.addEventListener('click', () => goto(b.dataset.goto)));

  $('#btn-refresh').addEventListener('click', async () => {
    await refreshAll();
    toast('已刷新', 'ok', 1500);
  });
  $('#btn-auto').addEventListener('click', toggleAuto);

  // 集群下拉
  const ok = await checkHealth();
  if (ok) {
    store.config = await api.config();
    store.selected.cluster = store.config.clusters[0]?.context;
    store.selected.podsCluster = store.selected.cluster;
    store.selected.gitopsCluster = store.selected.cluster;
    store.selected.termCluster = store.selected.cluster;

    const opts = store.config.clusters
      .map((c) => `<option value="${esc(c.context)}">${esc(c.name)}</option>`).join('');
    for (const id of ['cluster-select', 'pods-cluster', 'gitops-cluster', 'term-cluster']) {
      $(`#${id}`).innerHTML = opts;
    }
    $('#cluster-select').value = store.selected.clusterPage || store.selected.cluster;

    // 命名空间下拉：先用配置，再用集群实际 namespaces
    const nsOpts = store.config.namespaces
      .map((n) => `<option value="${esc(n)}">${esc(n)}</option>`).join('');
    $('#pods-namespace').innerHTML = nsOpts;
    $('#term-namespace').innerHTML = nsOpts;
  }

  $('#cluster-select').addEventListener('change', (e) => {
    store.selected.clusterPage = e.target.value;
    loadClusterPage();
  });
  $('#pods-cluster').addEventListener('change', (e) => { store.selected.podsCluster = e.target.value; });
  $('#pods-namespace').addEventListener('change', (e) => { store.selected.podsNamespace = e.target.value; });
  $('#gitops-cluster').addEventListener('change', (e) => { store.selected.gitopsCluster = e.target.value; loadGitOps(); });
  $('#term-cluster').addEventListener('change', loadTerminalForm);
  $('#term-namespace').addEventListener('change', loadTerminalForm);

  $('#btn-load-pods').addEventListener('click', queryPods);
  $('#btn-scale-up').addEventListener('click', () => doScale(3));
  $('#btn-scale-down').addEventListener('click', () => doScale(1));
  $('#btn-restart').addEventListener('click', doRestart);

  $('#btn-argocd-refresh').addEventListener('click', loadGitOps);
  $('#btn-argocd-sync-all').addEventListener('click', syncAllApps);
  $$('[data-action]').forEach((b) => b.addEventListener('click', () => gitopsAction(b.dataset.action)));

  $('#btn-loki-query').addEventListener('click', queryLoki);
  $('#loki-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') queryLoki(); });
  $$('[data-lq]').forEach((c) => c.addEventListener('click', () => {
    $('#loki-input').value = c.dataset.lq;
    queryLoki();
  }));

  $$('#alert-tabs .tab').forEach((t) => t.addEventListener('click', () => {
    store.alertTab = t.dataset.atab;
    $$('#alert-tabs .tab').forEach((x) => x.classList.toggle('active', x === t));
    ['firing', 'webhook', 'events', 'config'].forEach((k) =>
      $(`#atab-${k}`).classList.toggle('hidden', k !== store.alertTab));
  }));
  $('#btn-alerts-refresh').addEventListener('click', async () => {
    toast('拉取中…', 'info', 1500);
    await api.alertsRefresh().catch(() => {});
    renderAlerts();
  });
  $('#btn-copy-webhook').addEventListener('click', () => copyText($('#webhook-url').textContent.trim()));
  $('#btn-copy-am').addEventListener('click', () => copyText(AM_CONFIG));
  $('#btn-test-webhook').addEventListener('click', sendTestWebhook);

  $('#btn-term-connect').addEventListener('click', connectTerminal);
  $('#btn-term-disconnect').addEventListener('click', disconnectTerminal);
  $('#btn-term-clear').addEventListener('click', () => { $('#term-output').innerHTML = ''; });
  $('#btn-term-send').addEventListener('click', sendTermInput);
  $('#term-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendTermInput(); });
  $('#btn-quick-exec').addEventListener('click', quickExec);
  $('#quick-cmd').addEventListener('keydown', (e) => { if (e.key === 'Enter') quickExec(); });
  $$('[data-qc]').forEach((c) => c.addEventListener('click', () => {
    $('#quick-cmd').value = c.dataset.qc;
    quickExec();
  }));

  // 弹窗
  $('#modal-close').addEventListener('click', hideModal);
  $('#btn-close-modal').addEventListener('click', hideModal);
  $('#btn-copy-modal').addEventListener('click', () => copyText($('#modal-body').textContent));
  $('#modal').addEventListener('click', (e) => { if (e.target.id === 'modal') hideModal(); });

  // 全局快捷键
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') hideModal();
    if ((e.ctrlKey || e.metaKey) && e.key === 'r') { e.preventDefault(); refreshAll(); }
  });

  // Webhook URL
  $('#webhook-url').textContent = `${location.origin}/webhook/feishu`;

  // hash 路由支持（书签/浏览器前进后退）
  const pageFromHash = () => location.hash.replace('#', '') || 'overview';
  window.addEventListener('hashchange', () => {
    const p = pageFromHash();
    if (p !== store.page) goto(p);
  });

  // 首次加载
  if (ok) {
    const initial = pageFromHash();
    if (initial !== 'overview') {
      // 非概览页：确保已有选中集群再跳转，避免 loadClusterPage 等数据时 ctx 为空
      if (!store.selected.clusterPage) {
        store.selected.clusterPage = store.config.clusters[0]?.context;
        store.selected.podsCluster = store.selected.clusterPage;
        store.selected.gitopsCluster = store.selected.clusterPage;
        store.selected.termCluster = store.selected.clusterPage;
      }
      goto(initial);
    } else {
      await renderOverview();
    }
    startAuto();
  }
}

document.addEventListener('DOMContentLoaded', init);
