#!/bin/bash
set -e

# 配置项
CLIENT_LOG="./p2p-client.log"
# 记录当前脚本的PID（父进程PID）
MAIN_PID=$$

# 清理函数：Ctrl+C/退出时 杀死所有子进程（检测进程+socat）
cleanup() {
    echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 🔌 隧道已断开，正在清理进程..."
    # 杀死当前脚本的所有子进程（检测进程 + socat）
    pkill -P $MAIN_PID 2>/dev/null
    exit 0
}
# 绑定信号：Ctrl+C / 进程终止 都触发清理
trap cleanup INT TERM

# 检查root
[ $(id -u) -ne 0 ] && echo "请用root运行" && exit 1

# 自动安装socat
install_socat() {
    command -v socat &>/dev/null && return
    apt update && apt install socat -y || yum install socat -y
}
install_socat

# 端口配置
PORT1=$((50000 + RANDOM % 15535))
SSH_PORT=2222
IP1=$(curl -s ip.sb || echo "获取失败")

# 输出客户端信息
echo -e "\n========= 客户端信息 ========="
echo "你的公网地址: $IP1:$PORT1"
echo "本地SSH端口: $SSH_PORT"
echo "=============================="
echo -n "请输入服务端 IP:PORT → "
read addr

IP2=$(echo "$addr" | cut -d: -f1)
PORT2=$(echo "$addr" | cut -d: -f2)
[ -z "$IP2" ] || [ -z "$PORT2" ] && echo "格式错误" && exit 1

# ===================== 核心修复：检测进程绑定父进程PID =====================
# 传入父进程PID，父进程死则检测进程自毁
connection_detect() {
    local parent_pid=$1
    exec >> "$CLIENT_LOG" 2>&1
    
    while true; do
        # 【关键】判断父进程是否存活（父进程死了，立即退出）
        if ! kill -0 $parent_pid 2>/dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 父进程已退出，检测进程自动关闭"
            break
        fi
        # 检测隧道连通状态
        if ss -tuln | grep -q ":$SSH_PORT" && ss -au | grep -q ":$PORT1"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 客户端隧道连接成功，本地端口：$SSH_PORT"
        fi
        sleep 2
    done
}

# 后台启动检测，传入当前主进程PID（强绑定）
connection_detect $MAIN_PID &

# 前台启动隧道（阻塞运行，保持隧道永久开通）
echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 正在连接服务端隧道..."
socat TCP-LISTEN:"$SSH_PORT",fork,reuseaddr UDP:"$IP2":"$PORT2",sourceport="$PORT1"
