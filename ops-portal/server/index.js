/**
 * server/index.js — 服务入口
 *
 * 职责：
 *   1. 启动 HTTP 服务（API + 静态文件）
 *   2. 挂载 WebSocket 终端
 *   3. 启动告警轮询
 *
 * 启动：node server/index.js
 */
import http from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { CONFIG, CLUSTER_LIST } from './config.js';
import { match, listRoutes } from './routes.js';
import * as alerts from './alerts.js';
import { attachTerminal, destroyAll } from './terminal.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.resolve(__dirname, '..', 'public');

/* ────────────────────────────────────────────────
   静态文件
──────────────────────────────────────────────── */

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
};

async function serveStatic(req, res, pathname) {
  let rel = pathname === '/' ? '/index.html' : pathname;
  // 防目录穿越
  const full = path.join(PUBLIC_DIR, path.normalize(rel).replace(/^(\.\.[/\\])+/, ''));
  if (!full.startsWith(PUBLIC_DIR)) {
    res.writeHead(403).end('forbidden');
    return;
  }
  if (!existsSync(full)) {
    // SPA fallback
    const fallback = path.join(PUBLIC_DIR, 'index.html');
    if (existsSync(fallback)) {
      const html = await readFile(fallback);
      res.writeHead(200, { 'Content-Type': MIME['.html'] }).end(html);
      return;
    }
    res.writeHead(404).end('not found');
    return;
  }
  const s = await stat(full);
  if (s.isDirectory()) {
    res.writeHead(302, { Location: rel.replace(/\/?$/, '/') }).end();
    return;
  }
  const buf = await readFile(full);
  const ext = path.extname(full).toLowerCase();
  res.writeHead(200, {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Cache-Control': 'no-cache',
  }).end(buf);
}

/* ────────────────────────────────────────────────
   请求体解析
──────────────────────────────────────────────── */

const MAX_BODY = 1024 * 512;   // 512KB 足够

async function readBody(req) {
  if (req.method !== 'POST' && req.method !== 'PUT') return {};
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw new Error('payload too large');
    chunks.push(chunk);
  }
  if (!chunks.length) return {};
  const text = Buffer.concat(chunks).toString('utf8');
  try { return JSON.parse(text); }
  catch { return { _raw: text }; }
}

/* ────────────────────────────────────────────────
   请求处理
──────────────────────────────────────────────── */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, X-Webhook-Secret, Authorization',
  'Access-Control-Max-Age': '86400',
};

async function handle(req, res) {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = url.pathname.replace(/\/+$/, '') || '/';

  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS).end();
    return;
  }

  // 静态资源优先（不占用 /api 前缀）
  if (req.method === 'GET' && !pathname.startsWith('/api') &&
      pathname !== '/health' && pathname !== '/webhook/feishu') {
    await serveStatic(req, res, pathname);
    return;
  }

  const hit = match(req.method, pathname);
  if (!hit) {
    res.writeHead(404, { ...CORS, 'Content-Type': 'application/json' })
       .end(JSON.stringify({ error: 'not found', path: pathname }));
    return;
  }

  const t0 = Date.now();
  try {
    const body = await readBody(req);
    const result = await hit.handler({
      req,
      body,
      params: hit.params,
      query: url.searchParams,
      headers: new Headers(req.headers),
    });
    const { status = 200, data } = result || {};
    res.writeHead(status, { ...CORS, 'Content-Type': 'application/json' })
       .end(JSON.stringify(data));
    const dt = Date.now() - t0;
    if (dt > 1000) console.log(`[slow] ${req.method} ${pathname} ${dt}ms`);
  } catch (e) {
    console.error(`[error] ${req.method} ${pathname}:`, e.message);
    res.writeHead(500, { ...CORS, 'Content-Type': 'application/json' })
       .end(JSON.stringify({ error: e.message }));
  }
}

/* ────────────────────────────────────────────────
   启动
──────────────────────────────────────────────── */

const server = http.createServer((req, res) => {
  handle(req, res).catch((e) => {
    console.error('[fatal]', e);
    try { res.writeHead(500).end('internal error'); } catch { /* noop */ }
  });
});

// WebSocket 终端
attachTerminal(server);

// 告警轮询
alerts.startAutoRefresh(30000);

server.listen(CONFIG.httpPort, () => {
  const routes = listRoutes();
  console.log('');
  console.log('╔══════════════════════════════════════════════════════╗');
  console.log('║   Kind Ops Portal — Node.js 服务已启动               ║');
  console.log('╚══════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`  平台首页   http://localhost:${CONFIG.httpPort}/`);
  console.log(`  健康检查   http://localhost:${CONFIG.httpPort}/health`);
  console.log(`  WebSocket  ws://localhost:${CONFIG.httpPort}/ws/term`);
  console.log(`  飞书 Webhook  POST http://localhost:${CONFIG.httpPort}/webhook/feishu`);
  console.log('');
  console.log(`  WSL 发行版   ${CONFIG.wslDistro}`);
  console.log(`  目标集群     ${CLUSTER_LIST.map((c) => c.context).join(', ')}`);
  console.log(`  Prometheus   ${CONFIG.endpoints.prometheus}`);
  console.log(`  Loki         ${CONFIG.endpoints.loki}`);
  console.log('');
  console.log(`  已注册 ${routes.length} 条 API 路由`);
  console.log('');
  console.log('  提示：告警/日志需要先 port-forward');
  console.log(`    wsl -d ${CONFIG.wslDistro} kubectl --context ${CONFIG.clusters.ops} -n monitoring \\`);
  console.log('      port-forward svc/prometheus-prometheus 9090:9090 &');
  console.log(`    wsl -d ${CONFIG.wslDistro} kubectl --context ${CONFIG.clusters.ops} -n monitoring \\`);
  console.log('      port-forward svc/loki-gateway 3100:80 &');
  console.log('');
});

/* ────────────────────────────────────────────────
   优雅退出
──────────────────────────────────────────────── */

let shuttingDown = false;
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`\n[${signal}] 正在关闭…`);
  alerts.stopAutoRefresh();
  destroyAll();
  server.close(() => {
    console.log('HTTP 服务已关闭，再见。');
    process.exit(0);
  });
  // 兜底：3 秒后强制退出
  setTimeout(() => process.exit(0), 3000);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('uncaughtException', (e) => {
  console.error('[uncaughtException]', e);
});
process.on('unhandledRejection', (e) => {
  console.error('[unhandledRejection]', e);
});
