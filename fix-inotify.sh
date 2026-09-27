#!/bin/bash
# WSL2 inotify 额度不足会导致 kind 集群内 kube-proxy 崩溃循环
echo "=== 当前 inotify 限制 ==="
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches fs.inotify.max_user_watches 2>/dev/null
echo
echo "=== 当前使用量 ==="
echo "watch 数:    $(find /proc/*/fd -lname anon_inode:inotify 2>/dev/null | wc -l) 个 fd"
echo "instances:   $(sudo -n cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || cat /proc/sys/fs/inotify/max_user_instances)"

echo
echo "=== 提升限制 ==="
sudo -n sysctl -w fs.inotify.max_user_instances=8192 2>/dev/null \
  || sysctl -w fs.inotify.max_user_instances=8192 2>/dev/null \
  || echo "  无权限，稍后用 root 处理"
sudo -n sysctl -w fs.inotify.max_user_watches=524288 2>/dev/null \
  || sysctl -w fs.inotify.max_user_watches=524288 2>/dev/null \
  || echo "  无权限"

echo
echo "=== 结果 ==="
cat /proc/sys/fs/inotify/max_user_instances
cat /proc/sys/fs/inotify/max_user_watches
