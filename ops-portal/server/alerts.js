/**
 * alerts.js — 告警聚合状态
 *
 * 三路数据源合并成一个全局状态，供前端轮询：
 *   1. Prometheus firing 告警
 *   2. 飞书 Webhook 主动 POST 进来的消息
 *   3. 平台内执行失败产生的运维事件
 */
import { fetchAlerts } from './k8s.js';
import { CONFIG } from './config.js';

/** 内存态：重启代理会清空，演示环境可接受 */
const state = {
  prometheus: { count: 0, firing: [], pending: [], fetchedAt: null, error: null },
  webhook: [],        // 飞书推送进来的消息
  events: [],         // 平台自身操作事件
  startedAt: new Date().toISOString(),
};

const MAX_WEBHOOK = 30;
const MAX_EVENTS = 20;

let timer = null;

/** 主动拉取一次 Prometheus */
export async function refresh() {
  const r = await fetchAlerts();
  state.prometheus = {
    count: r.count,
    firing: r.firing || [],
    pending: r.pending || [],
    fetchedAt: new Date().toISOString(),
    error: r.ok ? null : (r.error || 'unknown'),
  };
  return state.prometheus;
}

/** 飞书 Webhook 收到一条消息 */
export function pushWebhook(payload) {
  const entry = {
    id: `wh-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    time: new Date().toISOString(),
    msgType: payload?.msg_type || payload?.type || 'unknown',
    text: extractText(payload),
    raw: payload,
  };
  state.webhook.unshift(entry);
  if (state.webhook.length > MAX_WEBHOOK) state.webhook.length = MAX_WEBHOOK;
  return entry;
}

/** 记录一次平台操作（成功/失败） */
export function pushEvent({ action, target, ok, message }) {
  const entry = {
    id: `ev-${Date.now()}`,
    time: new Date().toISOString(),
    action,
    target,
    ok: !!ok,
    message: String(message || '').slice(0, 300),
  };
  state.events.unshift(entry);
  if (state.events.length > MAX_EVENTS) state.events.length = MAX_EVENTS;
  return entry;
}

/** 从各种飞书消息格式里抠出可读文本 */
function extractText(payload) {
  if (!payload) return '(empty)';
  // 自定义机器人 text 类型
  if (payload.content?.text) return payload.content.text;
  // 卡片消息
  const card = payload.content?.text || payload.card;
  if (typeof card === 'string') {
    try {
      const c = JSON.parse(card);
      return extractCardText(c);
    } catch { return card.slice(0, 200); }
  }
  if (card) return extractCardText(card);
  // 事件订阅 im.message.receive_v1
  if (payload.event?.message?.content) {
    try {
      const c = JSON.parse(payload.event.message.content);
      return c.text || JSON.stringify(c).slice(0, 200);
    } catch { return String(payload.event.message.content).slice(0, 200); }
  }
  if (payload.text) return payload.text;
  return JSON.stringify(payload).slice(0, 200);
}

function extractCardText(card) {
  if (typeof card === 'string') return card.slice(0, 200);
  if (card.header?.title?.content) {
    const body = (card.elements || [])
      .map((e) => e.content?.text || e.tag || '')
      .filter(Boolean)
      .join(' | ');
    return `[${card.header.title.content}] ${body}`.trim();
  }
  return JSON.stringify(card).slice(0, 200);
}

/** 汇总视图 */
export function snapshot() {
  const p = state.prometheus;
  const recentWebhook = state.webhook.slice(0, 5);
  const recentEvents = state.events.slice(0, 5);
  // 飞书推送的告警也算"活跃告警"的一部分
  const webhookAlerts = state.webhook.filter((w) => isAlertText(w.text)).length;

  return {
    startedAt: state.startedAt,
    now: new Date().toISOString(),
    total: p.count + webhookAlerts,
    prometheus: {
      count: p.count,
      firing: p.firing,
      pending: p.pending,
      fetchedAt: p.fetchedAt,
      error: p.error,
      endpoint: CONFIG.endpoints.prometheus,
    },
    webhook: { count: state.webhook.length, alertCount: webhookAlerts, recent: recentWebhook },
    events: { count: state.events.length, recent: recentEvents },
  };
}

function isAlertText(text) {
  return /firing|critical|告警|alert|error|失败|异常/i.test(String(text || ''));
}

/** 启动定时刷新（默认 30s） */
export function startAutoRefresh(intervalMs = 30000) {
  if (timer) clearInterval(timer);
  refresh().catch(() => {});
  timer = setInterval(() => { refresh().catch(() => {}); }, intervalMs);
  console.log(`[alerts] 自动刷新已启动，间隔 ${intervalMs / 1000}s`);
}

export function stopAutoRefresh() {
  if (timer) clearInterval(timer);
  timer = null;
}
