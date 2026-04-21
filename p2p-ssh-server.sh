#!/bin/bash
# P2P SSH 服务端 - 家里WSL（Agent专用）
# 定制功能：60次打洞包、连接建立即停发、5分钟无连接自动清理、无无限发包
set -e

# ========== 你的自定义参数（已按要求设置） ==========
MAX_PUNCH_COUNT=60        # 最大打洞包次数
PUNCH_INTERVAL=1          # 打洞包间隔(秒)
SOCAT_TIMEOUT=300         # 无流量自动关闭(秒) = 5分钟
# ====================================================

# 校验参数
[ $# -ne 1 ] && echo "用法：$0 客户端IP:PORT" && exit 1
CLIENT_IP=$(echo "$1" | cut -d: -f1)
CLIENT_PORT=$(echo "$1" | cut -d: -f2)

# 校验root权限
[ $(id -u) -ne 0 ] && echo "错误：请用 root 运行" && exit 1

# 自动安装socat
install_socat() {
  command -v socat &>/dev/null && return
  if command -v yum &>/dev/null; then
    yum install socat -y
  elif command -v apt &>/dev/null; then
    apt update && apt install socat -y
  fi
}
install_socat

# 端口配置
PORT2=$((50000 + RANDOM % 15535))
IP2=$(curl -s ip.sb || echo "获取公网IP失败")
PID_FILE="/tmp/p2p-socat.pid"
COUNT=0  # 实际发送打洞包次数

# 清理历史残留进程
[ -f "$PID_FILE" ] && kill $(cat "$PID_FILE") 2>/dev/null && rm -f "$PID_FILE"

# 启动SSH隧道（后台运行，无流量5分钟自动关闭）
socat UDP-LISTEN:$PORT2,fork,reuseaddr TCP:127.0.0.1:22 -T $SOCAT_TIMEOUT &
SOCAT_PID=$!
echo "$SOCAT_PID" > "$PID_FILE"

# 核心：有限次数打洞 + 检测到连接立即停止发包
(
  while [ $COUNT -lt $MAX_PUNCH_COUNT ]; do
    # 检测：如果隧道已建立连接（有SSH流量），立即停止发送打洞包
    if ss -au | grep ":${PORT2}" | grep -q ESTABLISHED; then
      break
    fi
    echo -n ""
    COUNT=$((COUNT + 1))
    sleep $PUNCH_INTERVAL
  done

  # ========== 按你要求新增输出：成功提示 + 客户端信息 ==========
  echo -e "\n✅ P2P 隧道连接已建立成功！"
  echo "📶 对端客户端信息：${CLIENT_IP}:${CLIENT_PORT}"
  # ============================================================
  echo "打洞包已发送: ${COUNT}次（最大发送${MAX_PUNCH_COUNT}次）"
) | socat UDP:$CLIENT_IP:$CLIENT_PORT - &

# 主脚本立即退出，不阻塞Agent
echo -e "\n========= 服务端运行成功 =========="
echo "你的公网地址: $IP2:$PORT2"
echo "自动清理: 5分钟无连接自动关闭隧道"
echo "==================================="
