#!/bin/bash
set -e

# 配置项
MAX_PUNCH_COUNT=120
PUNCH_INTERVAL=1
LOG_FILE="./p2p-server.log"

# 参数校验
[ $# -ne 1 ] && echo "用法: $0 客户端IP:PORT" && exit 1
CLIENT_IP=$(echo "$1" | cut -d: -f1)
CLIENT_PORT=$(echo "$1" | cut -d: -f2)
[ -z "$CLIENT_IP" ] || [ -z "$CLIENT_PORT" ] && echo "格式错误" && exit 1

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
# 监听端口固定，方便客户端打洞
LISTEN_PORT=50000
IP2=$(curl -s ip.sb || echo "获取失败")
PID_FILE="/tmp/p2p-socat.pid"

# 清理历史进程
rm -f $PID_FILE
pkill -f "socat.*${LISTEN_PORT}" 2>/dev/null
sleep 1

# 输出服务端信息（无阻塞）
echo "========= 服务端信息 ========="
echo "你的公网地址: $IP2:$LISTEN_PORT"
echo "客户端地址: $CLIENT_IP:$CLIENT_PORT"
echo "SSH服务: 127.0.0.1:22"
echo "=============================="
echo "5分钟无连接自动关闭"

# ======================================
# 【核心】后台启动UDP监听隧道
# ======================================
socat UDP-LISTEN:$LISTEN_PORT,fork,reuseaddr TCP:127.0.0.1:22 &>/dev/null &
SOCAT_PID=$!
echo $SOCAT_PID > $PID_FILE
echo "[$(date '+%Y-%m-%d %H:%M:%S')] UDP监听已启动，PID=$SOCAT_PID，端口=$LISTEN_PORT"

# ======================================
# 【核心】后台打洞进程 - 持续发送打洞包
# ======================================
(
    exec >> $LOG_FILE 2>&1

    COUNT=0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始打洞，目标: $CLIENT_IP:$CLIENT_PORT"

    while [ $COUNT -lt $MAX_PUNCH_COUNT ]; do
        # 发送打洞包到客户端
        echo "punch" | socat - UDP:$CLIENT_IP:$CLIENT_PORT 2>/dev/null

        # 检查是否有连接建立
        if ss -au | grep -q ":${LISTEN_PORT}.*ESTABLISHED"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ P2P 隧道打通成功"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 📶 对端: $CLIENT_IP:$CLIENT_PORT"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 打洞次数: $COUNT"
            exit 0
        fi

        COUNT=$((COUNT+1))

        # 前10次快速打洞，后面降低频率
        if [ $COUNT -lt 10 ]; then
            sleep $PUNCH_INTERVAL
        else
            sleep 3
        fi
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⚠️ 打洞超时，次数: $COUNT"
) &

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 打洞进程已后台运行"
exit 0
