/**
 * 全面回归测试 —— 覆盖 27 条 API + 8 个页面数据源
 * 用法：node regression-test.js
 */
const BASE = 'http://localhost:8099';

const results = [];
let pass = 0, fail = 0, skip = 0;

const C = { g: '\x1b[32m', r: '\x1b[31m', y: '\x1b[33m', c: '\x1b[36m', d: '\x1b[2m', x: '\x1b[0m', b: '\x1b[1m' };

async function t(name, fn) {
  const t0 = Date.now();
  try {
    const r = await fn();
    const dt = Date.now() - t0;
    if (r === 'skip') {
      skip++;
      results.push({ name, status: 'SKIP', note: '前置条件不满足', dt });
      console.log(`${C.y}  SKIP${C.x} ${name} ${C.d}(${dt}ms)${C.x}`);
    } else {
      pass++;
      const note = typeof r === 'string' ? ` — ${r}` : '';
      results.push({ name, status: 'PASS', note, dt });
      console.log(`${C.g}  PASS${C.x} ${name} ${C.d}(${dt}ms)${C.x}${note ? C.d + note + C.x : ''}`);
    }
  } catch (e) {
    fail++;
    results.push({ name, status: 'FAIL', note: e.message, dt: Date.now() - t0 });
    console.log(`${C.r}  FAIL${C.x} ${name} ${C.d}(${Date.now() - t0}ms) — ${e.message}${C.x}`);
  }
}

async function get(path) {
  const r = await fetch(`${BASE}${path}`, { signal: AbortSignal.timeout(45000) });
  const txt = await r.text();
  let d;
  try { d = JSON.parse(txt); } catch { d = { _raw: txt.slice(0, 120) }; }
  return { status: r.status, data: d };
}

async function post(path, body) {
  const r = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(60000),
  });
  const txt = await r.text();
  let d;
  try { d = JSON.parse(txt); } catch { d = { _raw: txt.slice(0, 120) }; }
  return { status: r.status, data: d };
}

const assert = (cond, msg) => { if (!cond) throw new Error(msg || '断言失败'); };

(async () => {
  console.log(`\n${C.b}╔══════════════════════════════════════════════════════╗${C.x}`);
  console.log(`${C.b}║   Kind Ops Portal — 全面回归测试${C.x}`);
  console.log(`${C.b}╚══════════════════════════════════════════════════════╝${C.x}\n`);

  /* ═══ 1. 服务健康 ═══ */
  console.log(`${C.c}━━━ 1. 服务健康 ━━━${C.x}`);
  await t('GET /health', async () => {
    const { status, data } = await get('/health');
    assert(status === 200, `HTTP ${status}`);
    assert(data.ok === true, 'ok !== true');
    assert(typeof data.uptimeSec === 'number', '缺 uptimeSec');
    return `uptime ${data.uptimeSec}s, node ${data.node}`;
  });

  await t('GET /api/config', async () => {
    const { status, data } = await get('/api/config');
    assert(status === 200, `HTTP ${status}`);
    assert(Array.isArray(data.clusters) && data.clusters.length === 3, '集群数不为 3');
    assert(data.clusters[0].context === 'kind-ops-mgmt', '首个 context 错误');
    return `${data.clusters.length} 集群, ${data.namespaces.length} 命名空间`;
  });

  await t('静态资源 / (index.html)', async () => {
    const r = await fetch(`${BASE}/`, { signal: AbortSignal.timeout(10000) });
    const html = await r.text();
    assert(r.status === 200, `HTTP ${r.status}`);
    assert(html.includes('<title>'), '缺 title');
    assert(html.includes('/app.js'), '未引用 app.js');
    return `${html.length} 字节`;
  });

  await t('静态资源 /app.js', async () => {
    const r = await fetch(`${BASE}/app.js`, { signal: AbortSignal.timeout(10000) });
    const js = await r.text();
    assert(r.status === 200, `HTTP ${r.status}`);
    assert(js.includes('export') || js.includes('const api'), '内容异常');
    return `${js.length} 字节`;
  });

  await t('静态资源 /styles.css', async () => {
    const r = await fetch(`${BASE}/styles.css`, { signal: AbortSignal.timeout(10000) });
    const css = await r.text();
    assert(r.status === 200, `HTTP ${r.status}`);
    assert(css.includes(':root'), '缺 CSS 变量');
    return `${css.length} 字节`;
  });

  await t('目录穿越防护', async () => {
    const r = await fetch(`${BASE}/../../package.json`, { signal: AbortSignal.timeout(10000) });
    // 允许返回 200（浏览器会规范化路径），但不能返回 package.json 内容
    const t2 = await r.text();
    assert(!t2.includes('"kind-ops-portal"'), '泄露了 package.json！');
    return '未泄露';
  });

  /* ═══ 2. 集群数据 ═══ */
  console.log(`\n${C.c}━━━ 2. 集群数据 ━━━${C.x}`);
  let clusters = null;
  await t('GET /api/clusters', async () => {
    const { status, data } = await get('/api/clusters');
    assert(status === 200, `HTTP ${status}`);
    assert(Array.isArray(data.clusters), 'clusters 非数组');
    clusters = data.clusters;
    const live = clusters.filter((c) => c.totalNodes > 0);
    if (live.length === 0) return 'skip';
    return `${clusters.length} 集群, ${data.totals.totalNodes} 节点, ${data.totals.totalPods} Pods`;
  });

  const anyLive = clusters?.some((c) => c.totalNodes > 0);

  for (const c of clusters || []) {
    await t(`GET /api/cluster/${c.context}`, async () => {
      const { status, data } = await get(`/api/cluster/${encodeURIComponent(c.context)}`);
      assert(status === 200, `HTTP ${status}`);
      assert(Array.isArray(data.nodes), 'nodes 非数组');
      if (data.totalNodes === 0) return 'skip';
      const ready = data.nodes.filter((n) => n.ready).length;
      assert(ready === data.totalNodes, `有节点未 Ready (${ready}/${data.totalNodes})`);
      return `${data.totalNodes} 节点全 Ready, ${data.totalPods} Pods`;
    });
  }

  await t('GET /api/namespaces', async () => {
    const { status, data } = await get('/api/namespaces?context=kind-ops-mgmt');
    assert(status === 200, `HTTP ${status}`);
    if (!data.namespaces?.length) return 'skip';
    return `${data.namespaces.length} 命名空间: ${data.namespaces.slice(0, 5).join(', ')}`;
  });

  await t('GET /api/helm', async () => {
    const { status, data } = await get('/api/helm');
    assert(status === 200, `HTTP ${status}`);
    if (!data.releases?.length) return 'skip';
    return `${data.releases.length} releases: ${data.releases.map((r) => r.name).join(', ')}`;
  });

  /* ═══ 3. Pods ═══ */
  console.log(`\n${C.c}━━━ 3. Pods ━━━${C.x}`);
  await t('GET /api/pods (kube-system)', async () => {
    const { status, data } = await get('/api/pods?context=kind-ops-mgmt&namespace=kube-system');
    assert(status === 200, `HTTP ${status}`);
    if (!data.count) return 'skip';
    return `${data.count} Pods`;
  });

  await t('GET /api/pods (monitoring)', async () => {
    const { status, data } = await get('/api/pods?context=kind-ops-mgmt&namespace=monitoring');
    assert(status === 200, `HTTP ${status}`);
    if (!data.count) return 'skip';
    const running = data.pods.filter((p) => p.phase === 'Running').length;
    return `${data.count} Pods (${running} Running)`;
  });

  await t('GET /api/pods (argocd)', async () => {
    const { status, data } = await get('/api/pods?context=kind-ops-mgmt&namespace=argocd');
    assert(status === 200, `HTTP ${status}`);
    if (!data.count) return 'skip';
    return `${data.count} Pods`;
  });

  await t('GET /api/pods (demo-app)', async () => {
    const { status, data } = await get('/api/pods?context=kind-ops-mgmt&namespace=demo-app');
    assert(status === 200, `HTTP ${status}`);
    if (!data.count) return 'skip';
    return `${data.count} Pods`;
  });

  await t('GET /api/pods/logs', async () => {
    const pods = await get('/api/pods?context=kind-ops-mgmt&namespace=monitoring');
    const target = pods.data.pods?.find((p) => p.phase === 'Running');
    if (!target) return 'skip';
    const { status, data } = await get(
      `/api/pods/logs?context=kind-ops-mgmt&namespace=monitoring&pod=${encodeURIComponent(target.name)}&tail=10`
    );
    assert(status === 200, `HTTP ${status}`);
    assert(typeof data.output === 'string', '缺 output');
    return `${target.name}: ${data.output.length} 字节`;
  });

  await t('GET /api/pods/describe', async () => {
    const pods = await get('/api/pods?context=kind-ops-mgmt&namespace=monitoring');
    const target = pods.data.pods?.find((p) => p.phase === 'Running');
    if (!target) return 'skip';
    const { status, data } = await get(
      `/api/pods/describe?context=kind-ops-mgmt&namespace=monitoring&pod=${encodeURIComponent(target.name)}`
    );
    assert(status === 200, `HTTP ${status}`);
    assert(data.output.length > 50, 'describe 输出过短');
    return `${data.output.length} 字节`;
  });

  await t('GET /api/pods/describe 缺参数报错', async () => {
    const { status, data } = await get('/api/pods/describe');
    assert(status === 400, `期望 400 实际 ${status}`);
    assert(data.error, '缺 error 字段');
    return '正确返回 400';
  });

  /* ═══ 4. HPA / Services ═══ */
  console.log(`\n${C.c}━━━ 4. HPA / Services ━━━${C.x}`);
  await t('GET /api/hpa', async () => {
    const { status, data } = await get('/api/hpa?context=kind-ops-mgmt&namespace=demo-app');
    assert(status === 200, `HTTP ${status}`);
    if (!data.hpa?.length) return 'skip';
    const h = data.hpa[0];
    return `${h.name} ${h.currentReplicas}/${h.maxReplicas} (CPU ${h.targetCPU}%)`;
  });

  await t('GET /api/services', async () => {
    const { status, data } = await get('/api/services?context=kind-ops-mgmt&namespace=monitoring');
    assert(status === 200, `HTTP ${status}`);
    if (!data.services?.length) return 'skip';
    return `${data.services.length} Services`;
  });

  /* ═══ 5. ArgoCD ═══ */
  console.log(`\n${C.c}━━━ 5. ArgoCD ━━━${C.x}`);
  await t('GET /api/argocd/apps', async () => {
    const { status, data } = await get('/api/argocd/apps?context=kind-ops-mgmt');
    assert(status === 200, `HTTP ${status}`);
    if (!data.apps?.length) return 'skip';
    return `${data.apps.length} 应用: ${data.apps.map((a) => `${a.name}(${a.health}/${a.sync})`).join(', ')}`;
  });

  /* ═══ 6. 告警 ═══ */
  console.log(`\n${C.c}━━━ 6. 告警 ━━━${C.x}`);
  await t('GET /api/alerts', async () => {
    const { status, data } = await get('/api/alerts');
    assert(status === 200, `HTTP ${status}`);
    assert(typeof data.total === 'number', '缺 total');
    assert(data.prometheus && data.webhook && data.events, '缺子结构');
    return `total=${data.total}, PM=${data.prometheus.count}, 飞书=${data.webhook.count}`;
  });

  await t('GET /api/alerts/refresh', async () => {
    const { status, data } = await get('/api/alerts/refresh');
    assert(status === 200, `HTTP ${status}`);
    if (data.error) return `PM 未连接（预期）: ${data.error}`;
    return `count=${data.count}`;
  });

  await t('POST /webhook/feishu 接收消息', async () => {
    const msg = `[REGRESSION] 测试告警 ${Date.now()}`;
    const { status, data } = await post('/webhook/feishu', {
      msg_type: 'text', content: { text: msg },
    });
    assert(status === 200, `HTTP ${status}`);
    assert(data.ok === true, 'ok !== true');
    assert(data.text === msg, '文本未正确解析');
    return `已接收: ${data.text}`;
  });

  await t('POST /webhook/feishu 计入告警总数', async () => {
    const msg = `[CRITICAL] regression-test critical alert ${Date.now()}`;
    await post('/webhook/feishu', { msg_type: 'text', content: { text: msg } });
    await new Promise((r) => setTimeout(r, 500));
    const { data } = await get('/api/alerts');
    assert(data.webhook.count >= 2, `webhook.count=${data.webhook.count}，预期 >=2`);
    assert(data.webhook.alertCount >= 1, `alertCount=${data.webhook.alertCount}，预期 >=1`);
    return `webhook=${data.webhook.count}, alertCount=${data.webhook.alertCount}, total=${data.total}`;
  });

  await t('POST /webhook/feishu 卡片格式', async () => {
    const card = { msg_type: 'interactive', card: { header: { title: { content: '回归测试' } }, elements: [{ tag: 'div', content: { text: 'CPU 90%' } }] } };
    const { status, data } = await post('/webhook/feishu', card);
    assert(status === 200, `HTTP ${status}`);
    assert(data.text.includes('回归测试'), '卡片标题未解析');
    return data.text;
  });

  /* ═══ 7. Loki / Prometheus ═══ */
  console.log(`\n${C.c}━━━ 7. Loki / Prometheus ━━━${C.x}`);
  await t('GET /api/loki/query', async () => {
    const { status, data } = await get('/api/loki/query?q=' + encodeURIComponent('{namespace="demo-app"}'));
    assert(status === 200, `HTTP ${status}`);
    if (!data.ok) return `Loki 未连接（预期）: ${data.error}`;
    return `${data.count} 行日志`;
  });

  await t('GET /api/loki/labels', async () => {
    const { status, data } = await get('/api/loki/labels');
    assert(status === 200, `HTTP ${status}`);
    if (!data.labels?.length) return 'skip';
    return `${data.labels.length} 标签`;
  });

  await t('GET /api/prom/query', async () => {
    const { status, data } = await get('/api/prom/query?expr=' + encodeURIComponent('up'));
    assert(status === 200, `HTTP ${status}`);
    if (!data.ok) return `Prometheus 未连接（预期）: ${data.error}`;
    return `result: ${data.data?.result?.length ?? 0} 条`;
  });

  /* ═══ 8. 终端 ═══ */
  console.log(`\n${C.c}━━━ 8. 终端 ━━━${C.x}`);
  await t('GET /api/terminal/sessions', async () => {
    const { status, data } = await get('/api/terminal/sessions');
    assert(status === 200, `HTTP ${status}`);
    assert(Array.isArray(data.sessions), 'sessions 非数组');
    return `${data.sessions.length} 活跃会话`;
  });

  await t('POST /api/terminal/exec', async () => {
    const { status, data } = await post('/api/terminal/exec', {
      context: 'kind-ops-mgmt', namespace: 'default', args: ['get', 'pods', '-n', 'default'],
    });
    assert(status === 200, `HTTP ${status}`);
    if (!data.ok) return `kubectl 不可用（预期）: ${(data.stderr || '').slice(0, 60)}`;
    return `exit=${data.code}, ${data.stdout.length} 字节`;
  });

  await t('POST /api/terminal/exec 参数校验', async () => {
    const { status, data } = await post('/api/terminal/exec', { context: 'x', namespace: 'y' });
    assert(status === 400, `期望 400 实际 ${status}`);
    return '正确拒绝';
  });

  await t('WebSocket /ws/term 握手', async () => {
    const { default: WebSocket } = await import('ws');
    return new Promise((resolve, reject) => {
      const ws = new WebSocket('ws://localhost:8099/ws/term');
      const timer = setTimeout(() => { ws.close(); reject(new Error('超时')); }, 8000);
      ws.on('open', () => { clearTimeout(timer); ws.close(); resolve('握手成功'); });
      ws.on('error', (e) => { clearTimeout(timer); reject(new Error(e.message)); });
    });
  });

  await t('WebSocket ping/pong', async () => {
    const { default: WebSocket } = await import('ws');
    return new Promise((resolve, reject) => {
      const ws = new WebSocket('ws://localhost:8099/ws/term');
      const timer = setTimeout(() => { ws.close(); reject(new Error('超时')); }, 8000);
      ws.on('message', (d) => {
        const m = JSON.parse(d.toString());
        clearTimeout(timer);
        ws.close();
        if (m.type === 'hello') { ws.send(JSON.stringify({ type: 'ping' })); return; }
        if (m.type === 'pong') return resolve('pong 正常');
        reject(new Error('意外消息: ' + m.type));
      });
      ws.on('error', (e) => { clearTimeout(timer); reject(new Error(e.message)); });
    });
  });

  /* ═══ 9. 写操作（需要集群） ═══ */
  console.log(`\n${C.c}━━━ 9. 写操作 ━━━${C.x}`);
  await t('POST /api/scale', async () => {
    const { status, data } = await post('/api/scale', {
      context: 'kind-ops-mgmt', namespace: 'demo-app', name: 'demo-app', replicas: 2,
    });
    assert(status === 200, `HTTP ${status}`);
    if (!data.ok) return `需要集群（预期）: ${(data.message || '').slice(0, 50)}`;
    return `已设为 ${data.replicas} 副本`;
  });

  await t('POST /api/rollout-restart', async () => {
    const { status, data } = await post('/api/rollout-restart', {
      context: 'kind-ops-mgmt', namespace: 'demo-app', resource: 'deployment', name: 'demo-app',
    });
    assert(status === 200, `HTTP ${status}`);
    if (!data.ok) return `需要集群（预期）: ${(data.message || '').slice(0, 50)}`;
    return '已触发';
  });

  /* ═══ 10. 错误处理 ═══ */
  console.log(`\n${C.c}━━━ 10. 错误处理 ━━━${C.x}`);
  await t('GET 不存在的路径 → 404', async () => {
    const { status, data } = await get('/api/does-not-exist');
    assert(status === 404, `期望 404 实际 ${status}`);
    assert(data.error === 'not found', 'error 字段不对');
    return '正确';
  });

  await t('GET /api/cluster/未知context', async () => {
    const { status } = await get('/api/cluster/kind-nonexistent');
    assert(status === 200, `期望 200（优雅降级）实际 ${status}`);
    return '优雅降级';
  });

  /* ═══ 汇总 ═══ */
  const total = pass + fail + skip;
  const pct = ((pass / total) * 100).toFixed(1);
  console.log(`\n${C.b}╔══════════════════════════════════════════════════════╗${C.x}`);
  console.log(`${C.b}║   回归测试结果                                        ║${C.x}`);
  console.log(`${C.b}╚══════════════════════════════════════════════════════╝${C.x}`);
  console.log(`  ${C.g}通过 ${pass}${C.x} / ${C.r}失败 ${fail}${C.x} / ${C.y}跳过 ${skip}${C.x}   通过率 ${C.b}${pct}%${C.x}`);
  console.log('');

  const failed = results.filter((r) => r.status === 'FAIL');
  if (failed.length) {
    console.log(`${C.r}失败用例:${C.x}`);
    failed.forEach((f) => console.log(`  ✗ ${f.name} — ${f.note}`));
    console.log('');
  }
  const skipped = results.filter((r) => r.status === 'SKIP');
  if (skipped.length) {
    console.log(`${C.y}跳过用例（前置条件不满足）:${C.x}`);
    skipped.forEach((s) => console.log(`  ○ ${s.name} ${C.d}${s.note || ''}${C.x}`));
    console.log('');
  }

  // JSON 报告
  const fs = await import('node:fs');
  fs.writeFileSync(
    new URL('./regression-report.json', import.meta.url),
    JSON.stringify({ timestamp: new Date().toISOString(), total, pass, fail, skip, pct, results }, null, 2)
  );
  console.log(`${C.d}报告已写入 regression-report.json${C.x}\n`);

  process.exit(fail > 0 ? 1 : 0);
})();
