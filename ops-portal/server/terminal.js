/**
 * terminal.js — WebSocket 交互式终端
 *
 * 原理：spawn 一个常驻的 `wsl ... kubectl exec -i <pod> -- /bin/sh` 子进程，
 * WebSocket 收到的按键写入子进程 stdin，子进程 stdout 推回浏览器。
 *
 * 注意：这里没有用 -t（TYY），因为 Node 侧没有真实 PTY。
 * 好处是纯 JS 实现、零原生依赖；代价是没有行编辑/彩色提示符。
 * 如果需要完整 PTY 体验，把 child_process.spawn 换成 node-pty 即可，接口不变。
 */
import { spawn } from 'node:child_process';
import { WebSocketServer } from 'ws';
import { CONFIG } from './config.js';

const sessions = new Map();  // sessionId -> Session

let sessionSeq = 0;

/**
 * 创建一个 kubectl exec 会话
 * @param {object} opts
 * @param {string} opts.context   集群 context
 * @param {string} opts.namespace 命名空间
 * @param {string} opts.pod       Pod 名
 * @param {string} [opts.container] 容器名（多容器 Pod 必填）
 * @param {string} [opts.shell]   shell，默认 /bin/sh
 */
export function createSession({ context, namespace, pod, container, shell = '/bin/sh' }) {
  const id = `t${++sessionSeq}`;

  const args = [
    '-d', CONFIG.wslDistro, '--',
    'kubectl', 'exec', '-i',
    '--context', context,
    '-n', namespace,
    pod,
  ];
  if (container) args.push('-c', container);
  args.push('--', shell);

  const child = spawn('wsl', args, {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: { ...process.env, TERM: 'dumb', COLUMNS: '200', LINES: '50' },
  });

  const session = {
    id,
    context,
    namespace,
    pod,
    container: container || null,
    child,
    createdAt: Date.now(),
    subscribers: new Set(),
    exitInfo: null,
    buffer: '',
  };

  child.stdout.on('data', (chunk) => {
    const text = chunk.toString('utf8');
    session.buffer += text;
    // 只保留最近 64KB，避免内存无限增长
    if (session.buffer.length > 65536) session.buffer = session.buffer.slice(-65536);
    broadcast(session, { type: 'data', data: text });
  });

  child.stderr.on('data', (chunk) => {
    broadcast(session, { type: 'data', data: chunk.toString('utf8') });
  });

  child.on('error', (err) => {
    broadcast(session, { type: 'error', data: `spawn 失败: ${err.message}` });
  });

  child.on('exit', (code, signal) => {
    session.exitInfo = { code, signal, at: Date.now() };
    broadcast(session, { type: 'exit', data: `\r\n[会话结束] exit=${code} signal=${signal || 'none'}\r\n` });
    setTimeout(() => destroySession(id), 1000);
  });

  sessions.set(id, session);
  return session;
}

export function getSession(id) {
  return sessions.get(id) || null;
}

export function destroySession(id) {
  const s = sessions.get(id);
  if (!s) return false;
  for (const ws of s.subscribers) {
    try { ws.close(1000, 'session destroyed'); } catch { /* noop */ }
  }
  s.subscribers.clear();
  if (s.child && !s.child.killed) {
    try { s.child.stdin.end(); } catch { /* noop */ }
    try { s.child.kill(); } catch { /* noop */ }
  }
  sessions.delete(id);
  return true;
}

export function destroyAll() {
  for (const id of [...sessions.keys()]) destroySession(id);
}

export function listSessions() {
  return [...sessions.values()].map((s) => ({
    id: s.id,
    context: s.context,
    namespace: s.namespace,
    pod: s.pod,
    container: s.container,
    alive: !s.child.killed && !s.exitInfo,
    subscribers: s.subscribers.size,
    uptimeSec: Math.round((Date.now() - s.createdAt) / 1000),
  }));
}

/** 向 session 写入用户输入 */
export function writeToSession(id, data) {
  const s = sessions.get(id);
  if (!s) return { ok: false, error: 'session not found' };
  if (s.child.killed || s.exitInfo) return { ok: false, error: 'session exited' };
  try {
    s.child.stdin.write(data);
    return { ok: true };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

function broadcast(session, msg) {
  const payload = JSON.stringify({ ...msg, sessionId: session.id });
  for (const ws of session.subscribers) {
    if (ws.readyState === 1) {  // OPEN
      try { ws.send(payload); } catch { /* noop */ }
    }
  }
}

/* ────────────────────────────────────────────────
   HTTP 触发的单命令执行（无状态，简单可靠）
──────────────────────────────────────────────── */

/**
 * 不开 WebSocket，直接执行一条 kubectl 命令并返回完整输出。
 * 适合 "点一下按钮看结果" 这种场景，比终端更稳。
 */
export async function execOnce(context, namespace, args, { timeout = 30000 } = {}) {
  const full = [
    '-d', CONFIG.wslDistro, '--',
    'kubectl', ...args, '--context', context, '-n', namespace,
  ];
  return new Promise((resolve) => {
    const child = spawn('wsl', full, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    const timer = setTimeout(() => {
      try { child.kill(); } catch { /* noop */ }
      resolve({ ok: false, code: -1, stdout: out, stderr: 'timeout' });
    }, timeout);

    child.stdout.on('data', (d) => { out += d.toString(); });
    child.stderr.on('data', (d) => { err += d.toString(); });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({ ok: code === 0, code, stdout: out, stderr: err });
    });
    child.on('error', (e) => {
      clearTimeout(timer);
      resolve({ ok: false, code: -1, stdout: out, stderr: e.message });
    });
  });
}

/* ────────────────────────────────────────────────
   WebSocketServer 挂载
──────────────────────────────────────────────── */

/**
 * 在给定 HTTP server 上挂载 /ws/term
 * 前端连上后发 {type:'create', context, namespace, pod, container}
 * 服务端创建 session 并回 sessionId，之后即可收发 {type:'input', data}
 */
export function attachTerminal(server) {
  const wss = new WebSocketServer({ server, path: '/ws/term' });

  wss.on('connection', (ws) => {
    console.log('[ws] 客户端已连接');
    let boundSession = null;

    const safeSend = (obj) => {
      if (ws.readyState === 1) {
        try { ws.send(JSON.stringify(obj)); } catch { /* noop */ }
      }
    };

    safeSend({ type: 'hello', data: 'connected, send {type:"create",...} to start a shell' });

    ws.on('message', async (raw) => {
      let msg;
      try { msg = JSON.parse(raw.toString()); }
      catch { return safeSend({ type: 'error', data: 'invalid JSON' }); }

      switch (msg.type) {
        case 'create': {
          const { context, namespace, pod, container } = msg;
          if (!context || !namespace || !pod) {
            return safeSend({ type: 'error', data: 'context / namespace / pod 必填' });
          }
          // 每次只保留一个终端，旧的关掉
          if (boundSession) destroySession(boundSession);
          const s = createSession({ context, namespace, pod, container });
          boundSession = s.id;
          s.subscribers.add(ws);
          safeSend({
            type: 'ready',
            sessionId: s.id,
            data: `connected to ${namespace}/${pod}`,
          });
          break;
        }

        case 'input': {
          if (!boundSession) return safeSend({ type: 'error', data: 'no active session' });
          const r = writeToSession(boundSession, msg.data ?? '');
          if (!r.ok) safeSend({ type: 'error', data: r.error });
          break;
        }

        case 'run': {
          // 一次性执行，不进入交互模式
          const { context, namespace, args } = msg;
          if (!context || !namespace || !Array.isArray(args)) {
            return safeSend({ type: 'error', data: 'context / namespace / args 必填' });
          }
          safeSend({ type: 'running', data: `kubectl ${args.join(' ')}` });
          const r = await execOnce(context, namespace, args);
          safeSend({
            type: 'result',
            ok: r.ok,
            data: r.stdout + (r.stderr ? `\n[stderr]\n${r.stderr}` : ''),
          });
          break;
        }

        case 'close': {
          if (boundSession) destroySession(boundSession);
          boundSession = null;
          safeSend({ type: 'closed' });
          break;
        }

        case 'ping':
          safeSend({ type: 'pong', t: Date.now() });
          break;

        default:
          safeSend({ type: 'error', data: `unknown message type: ${msg.type}` });
      }
    });

    ws.on('close', () => {
      console.log('[ws] 客户端已断开');
      if (boundSession) {
        const s = sessions.get(boundSession);
        if (s) {
          s.subscribers.delete(ws);
          if (s.subscribers.size === 0) destroySession(boundSession);
        }
      }
    });

    ws.on('error', (e) => console.warn('[ws] error:', e.message));
  });

  console.log('[ws] WebSocket 终端已挂载: /ws/term');
  return wss;
}
