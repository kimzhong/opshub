/**
 * 全局配置
 */
export const CONFIG = {
  // HTTP API 端口
  httpPort: Number(process.env.OPS_PORT || 8099),
  // WebSocket 终端端口
  wsPort: Number(process.env.OPS_WS_PORT || 8098),

  // WSL 发行版名
  wslDistro: process.env.WSL_DISTRO || 'Ubuntu',

  // 目标集群 context
  clusters: {
    ops: 'kind-ops-mgmt',
    regionA: 'kind-biz-prod-regiona',
    regionB: 'kind-biz-prod-regionb',
  },

  // 集群内部服务 → 宿主机 NodePort 直连地址
  // 全部走 NodePort，不再依赖 kubectl port-forward
  endpoints: {
    prometheus: process.env.PROM_URL || 'http://localhost:30090',
    loki: process.env.LOKI_URL || 'http://localhost:30212',
    alertmanager: process.env.ALERTMANAGER_URL || 'http://localhost:30093',
    grafana: process.env.GRAFANA_URL || 'http://localhost:30300',
    argocd: process.env.ARGOCD_URL || 'http://localhost:31773',
  },

  // 常用命名空间
  commonNamespaces: [
    'default',
    'monitoring',
    'argocd',
    'demo-app',
    'gitlab-runner',
    'kube-system',
  ],

  // 单条命令超时（毫秒）
  cmdTimeout: Number(process.env.CMD_TIMEOUT || 30000),
};

/** 集群 context 列表（顺序与前端展示一致） */
export const CLUSTER_LIST = [
  { key: 'ops', name: 'ops-mgmt', role: '管理集群', context: CONFIG.clusters.ops },
  { key: 'regionA', name: 'biz-prod-regiona', role: '生产集群 A', context: CONFIG.clusters.regionA },
  { key: 'regionB', name: 'biz-prod-regionb', role: '生产集群 B', context: CONFIG.clusters.regionB },
];
