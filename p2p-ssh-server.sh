#!/bin/bash
set -e

# 配置项
MAX_PUNCH_COUNT=60
PUNCH_INTERVAL=1
SOCAT_TIMEOUT=300
# 日志：当前目录 + 追加写入 + 带时间戳
LOG_FILE="./p2p-server.log"

# 参数校验
[ $# -ne 1 ] && echo "用法：$0 客户端IP:PORT" && exit 1
CLIENT_IP=$(echo "$1" | cut -d: -f1)
CLIENT_PORT=$(echo "$1" | cut -d: -f2)
[ $(id -u) -ne 0 ] && echo "请用root运行" && exit 1

# 自动安装socat
install_socat() {
  command -v socat &>/dev/null && return
  if command -v yum &>/dev/null; then
    yum install socat -y
  else
    apt update && apt install socat -y
  fi
}
install_socat

# 生成端口 + 获取公网IP
PORT2=$((50000 + RANDOM % 15535))
IP2=$(curl -s ip.sb || echo "获取失败")
PID_FILE="/tmp/p2p-socat.pid"

# 清理历史进程（日志保留，仅杀进程）
rm -f $PID_FILE
pkill -f "socat.*$PORT2" 2>/dev/null

# ======================================
# 核心：立即输出，Agent 直接获取
# ======================================
echo "你的公网地址: $IP2:$PORT2"
echo "自动清理: 5分钟无连接自动关闭"

# 后台启动隧道（自动超时关闭）
socat UDP-LISTEN:$PORT2,fork,reuseaddr TCP:127.0.0.1:22 -T $SOCAT_TIMEOUT &
SOCAT_PID=$!
echo $SOCAT_PID > $PID_FILE

# ======================================
# 后台打洞 + 日志追加写入(带时间) + 不干扰终端
# ======================================
(
  COUNT=0
  # 标准输出/错误 追加到日志
  exec >> $LOG_FILE 2>&1
  while [ $COUNT -lt $MAX_PUNCH_COUNT ]; do
    if ss -au | grep -q ":${PORT2}.*ESTABLISHED"; then
      # 带时间戳输出成功日志
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ P2P 隧道连接成功"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📶 对端客户端: $CLIENT_IP:$CLIENT_PORT"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] 打洞包已发送: ${COUNT}次（最大60次）"
      break
    fi
    echo -n ""
    COUNT=$((COUNT+1))
    sleep $PUNCH_INTERVAL
  done
) | socat UDP:$CLIENT_IP:$CLIENT_PORT - &

# 脚本立即退出
exit 0
