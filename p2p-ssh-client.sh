#!/bin/bash
# P2P SSH 客户端 - 公司端（前台阻塞）
set -e

[ $(id -u) -ne 0 ] && echo "错误：请用 root 运行" && exit 1

install_socat() {
  if command -v socat &>/dev/null; then return; fi
  echo "安装 socat..."
  if command -v apt &>/dev/null; then
    apt update && apt install socat -y
  elif command -v yum &>/dev/null; then
    yum install socat -y
  fi
}
install_socat

PORT1=$((50000 + RANDOM % 15535))
SSH_PORT=2222
IP1=$(curl -s ip.sb || echo "获取失败")

echo -e "\n========= 客户端信息 ========="
echo "你的公网地址: $IP1:$PORT1"
echo "本地SSH端口: $SSH_PORT"
echo "=============================="
echo "请让 Agent 执行：./p2p-ssh-server.sh $IP1:$PORT1"
echo -n "请输入服务端返回的 IP:PORT → "
read addr

IP2=$(echo "$addr" | cut -d: -f1)
PORT2=$(echo "$addr" | cut -d: -f2)

echo -e "\n✅ 隧道建立中，保持本窗口打开"
echo "✅ 连接命令：ssh root@127.0.0.1 -p $SSH_PORT"

socat TCP-LISTEN:$SSH_PORT,fork,reuseaddr UDP:$IP2:$PORT2,sourceport=$PORT1
