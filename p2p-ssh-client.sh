#!/bin/bash
set -e
# 退出时自动清理进程
trap 'echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] 🔌 隧道已断开"; pkill -f "socat.*$SSH_PORT" 2>/dev/null; exit 0' INT

# 配置项
CLIENT_LOG="./p2p-client.log"
MAX_DETECT_SECOND=30  # 最大检测时长30秒，防止无限循环

# 检查root
[ $(id -u) -ne 0 ] && echo "请用root运行" && exit 1

# 安装socat
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

# ======================================
# 后台检测连接：限时30秒 + 带时间 + 日志追加
# ======================================
(
  USE_TIME=0
  exec >> $CLIENT_LOG 2>&1  # 日志追加写入
  while [ $USE_TIME -lt $MAX_DETECT_SECOND ]; do
    sleep 1
    USE_TIME=$((USE_TIME+1))
    if ss -tuln | grep -q ":$SSH_PORT"; then
      # 终端输出（带时间）
      echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 客户端已成功连接到服务端隧道！"
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 连接命令：ssh root@127.0.0.1 -p $SSH_PORT"
      # 日志写入（带时间）
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ 客户端隧道连接成功，本地端口：$SSH_PORT"
      break
    fi
  done
  # 超时日志
  if [ $USE_TIME -ge $MAX_DETECT_SECOND ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ⏰ 客户端检测超时（${MAX_DETECT_SECOND}秒）"
  fi
) &

# 启动隧道（前台阻塞）
socat TCP-LISTEN:$SSH_PORT,fork,reuseaddr UDP:$IP2:$PORT2,sourceport=$PORT1
