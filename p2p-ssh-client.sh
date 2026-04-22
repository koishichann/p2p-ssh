#!/bin/bash
set -e

# 配置项
CLIENT_LOG="./p2p-client.log"
MAIN_PID=$$
MAX_PUNCH_ATTEMPTS=30
PUNCH_INTERVAL=2

# 清理函数
cleanup() {
    echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 隧道已断开，正在清理进程..."
    pkill -P $MAIN_PID 2>/dev/null
    exit 0
}
trap cleanup INT TERM

# 检查root
[ $(id -u) -ne 0 ] && echo "请用root运行" && exit 1

# 自动安装socat
install_socat() {
    command -v socat &>/dev/null && return
    apt update && apt install socat -y || yum install socat -y
}
install_socat

# 端口配置 - sourceport 固定，以便NAT正确映射
SOURCE_PORT=50000
SSH_PORT=2222
IP1=$(curl -s ip.sb || echo "获取失败")

# 输出客户端信息
echo -e "\n========= 客户端信息 ========="
echo "你的公网地址: $IP1:$SOURCE_PORT"
echo "本地SSH端口: $SSH_PORT"
echo "=============================="

# 获取服务端地址
echo -n "请输入服务端 IP:PORT → "
read addr

IP2=$(echo "$addr" | cut -d: -f1)
PORT2=$(echo "$addr" | cut -d: -f2)
[ -z "$IP2" ] || [ -z "$PORT2" ] && echo "格式错误" && exit 1

echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 正在连接服务端..."

# ======================================
# 【修复1】先发送打洞包，触发NAT映射
# ======================================
echo "[打洞] 正在发送初始打洞包..."
echo "dummy" | socat - UDP:$IP2:$PORT2,sourceport=$SOURCE_PORT,bind=0.0.0.0:0 2>/dev/null &

# 等待一小段时间让打洞包到达
sleep 1

# ======================================
# 【核心】启动双向打洞进程
# ======================================
(
    COUNT=0
    exec >> "$CLIENT_LOG" 2>&1

    while [ $COUNT -lt $MAX_PUNCH_ATTEMPTS ]; do
        # 每次循环发送一个打洞包
        echo "打洞尝试 $COUNT" | socat - UDP:$IP2:$PORT2,sourceport=$SOURCE_PORT,bind=0.0.0.0:0 2>/dev/null

        # 检查隧道是否建立成功
        if ss -tuln | grep -q ":$SSH_PORT" && ss -au | grep -q ":$SOURCE_PORT"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 隧道打通成功"
            break
        fi

        COUNT=$((COUNT+1))
        sleep $PUNCH_INTERVAL
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 打洞完成，次数: $COUNT"
) &

# 等待打洞初始包发出
sleep 2

# ======================================
# 【修复2】前台启动隧道（使用固定sourceport）
# ======================================
echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 启动隧道守护进程..."
socat TCP-LISTEN:$SSH_PORT,fork,reuseaddr UDP:$IP2:$PORT2,sourceport=$SOURCE_PORT
