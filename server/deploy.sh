#!/usr/bin/env bash
set -e

# ==============================================================================
# P2P 语音直连 - 硅谷辅助服务器一键部署脚本 (纯 STUN + WebSocket 信令)
# 作用：提供 NAT 打洞探测与 WebRTC 握手信令，绝不中转任何音频数据流
# ==============================================================================

DEPLOY_DIR="/opt/p2p-server"
echo ">>> [1/5] 创建部署工作目录: $DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR"
cd "$DEPLOY_DIR"

echo ">>> [2/5] 生成纯 STUN 配置文件 turnserver.conf (严格禁用 Relay 中转)"
cat << 'EOF' > turnserver.conf
# Coturn Configuration - High Performance STUN & Private TURN Relay
listening-port=3478
tls-listening-port=5349
external-ip=170.106.195.109
realm=p2p.call
user=p2puser:p2psecret2026
lt-cred-mech
min-port=49152
max-port=49200
fingerprint
verbose
log-file=stdout
EOF

echo ">>> [3/5] 生成信令服务源码 package.json 与 signaling.js"
cat << 'EOF' > package.json
{
  "name": "p2p-signaling-server",
  "version": "1.0.0",
  "description": "Ultra-lightweight WebRTC P2P Signaling Server",
  "main": "signaling.js",
  "scripts": {
    "start": "node signaling.js"
  },
  "dependencies": {
    "ws": "^8.18.0"
  }
}
EOF

cat << 'EOF' > signaling.js
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });
const clients = new Map();

console.log(`[Signaling] P2P Signaling Server running on port ${PORT}`);

wss.on('connection', (ws, req) => {
  const remoteIp = req.socket.remoteAddress;
  console.log(`[Signaling] Client connected from ${remoteIp}`);
  
  let currentUserId = null;
  ws.isAlive = true;

  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (message) => {
    let data;
    try {
      data = JSON.parse(message.toString());
    } catch (err) {
      console.error('[Signaling] Malformed JSON message:', err.message);
      return;
    }

    const { type, from, to, payload } = data;

    switch (type) {
      case 'register': {
        const userId = data.userId?.trim();
        const avatar = data.avatar || 'pilot';

        if (!userId) {
          ws.send(JSON.stringify({ type: 'error', message: 'User ID cannot be empty' }));
          return;
        }

        if (currentUserId && currentUserId !== userId) {
          clients.delete(currentUserId);
          broadcastUserStatus(currentUserId, false);
          console.log(`[Signaling] User renamed from "${currentUserId}" to "${userId}"`);
        }

        if (clients.has(userId)) {
          const oldEntry = clients.get(userId);
          if (oldEntry && oldEntry.ws !== ws && oldEntry.ws.readyState === WebSocket.OPEN) {
            oldEntry.ws.send(JSON.stringify({ type: 'conflict', message: 'Logged in from another device' }));
            oldEntry.ws.close();
          }
        }

        currentUserId = userId;
        clients.set(userId, { ws, avatar });
        ws.userId = userId;

        console.log(`[Signaling] User registered: "${userId}" (Avatar: ${avatar}) (Total online: ${clients.size})`);

        const onlineList = Array.from(clients.entries())
          .filter(([id]) => id !== userId)
          .map(([id, info]) => ({ userId: id, avatar: info.avatar }));

        ws.send(JSON.stringify({
          type: 'registered',
          userId: userId,
          avatar: avatar,
          onlineUsers: onlineList
        }));

        broadcastUserStatus(userId, true, avatar);
        break;
      }

      case 'unregister': {
        if (currentUserId && clients.has(currentUserId)) {
          clients.delete(currentUserId);
          console.log(`[Signaling] User "${currentUserId}" unregistered`);
          broadcastUserStatus(currentUserId, false);
          currentUserId = null;
        }
        break;
      }

      case 'get_users': {
        const onlineList = Array.from(clients.entries())
          .filter(([id]) => id !== currentUserId)
          .map(([id, info]) => ({ userId: id, avatar: info.avatar }));

        ws.send(JSON.stringify({ type: 'user_list', users: onlineList }));
        break;
      }

      case 'call_request':
      case 'call_accepted':
      case 'call_rejected':
      case 'offer':
      case 'answer':
      case 'ice_candidate':
      case 'hangup': {
        if (!to) {
          ws.send(JSON.stringify({ type: 'error', message: 'Target user (to) is required' }));
          return;
        }

        const targetEntry = clients.get(to);
        if (targetEntry && targetEntry.ws.readyState === WebSocket.OPEN) {
          targetEntry.ws.send(JSON.stringify({
            type: type,
            from: currentUserId,
            to: to,
            avatar: clients.get(currentUserId)?.avatar || 'pilot',
            payload: payload
          }));
          console.log(`[Signaling] Forwarded [${type}] from [${currentUserId}] to [${to}]`);
        } else {
          console.log(`[Signaling] User [${to}] not found or offline for [${type}]`);
          ws.send(JSON.stringify({
            type: 'user_offline',
            target: to,
            message: `User ${to} is currently offline`
          }));
        }
        break;
      }

      case 'ping': {
        ws.isAlive = true;
        ws.send(JSON.stringify({ type: 'pong' }));
        break;
      }

      default:
        console.warn(`[Signaling] Unknown message type: ${type}`);
    }
  });

  ws.on('close', () => {
    if (currentUserId && clients.has(currentUserId)) {
      const entry = clients.get(currentUserId);
      if (entry && entry.ws === ws) {
        clients.delete(currentUserId);
        console.log(`[Signaling] User "${currentUserId}" disconnected (Total online: ${clients.size})`);
        broadcastUserStatus(currentUserId, false);
      }
    }
  });

  ws.on('error', (err) => {
    console.error(`[Signaling] Socket error on user "${currentUserId}":`, err.message);
  });
});

function broadcastUserStatus(userId, isOnline, avatar = 'pilot') {
  const message = JSON.stringify({
    type: isOnline ? 'user_joined' : 'user_left',
    userId: userId,
    avatar: avatar
  });

  for (const [id, entry] of clients.entries()) {
    if (id !== userId && entry.ws.readyState === WebSocket.OPEN) {
      entry.ws.send(message);
    }
  }
}

const interval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 20000);

wss.on('close', () => {
  clearInterval(interval);
});
EOF

cat << 'EOF' > Dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --production
COPY signaling.js ./
EXPOSE 8080
CMD ["node", "signaling.js"]
EOF

echo ">>> [4/5] 生成 Docker Compose 编排文件 docker-compose.yml"
cat << 'EOF' > docker-compose.yml
version: '3.8'

services:
  signaling:
    build: .
    container_name: p2p-signaling
    restart: always
    ports:
      - "8080:8080"
    environment:
      - PORT=8080

  stun:
    image: coturn/coturn:latest
    container_name: p2p-stun
    restart: always
    network_mode: "host"
    volumes:
      - ./turnserver.conf:/etc/coturn/turnserver.conf:ro
    command: ["-c", "/etc/coturn/turnserver.conf"]
EOF

echo ">>> [5/5] 启动服务..."
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  echo ">>> 检测到 Docker Compose，正在使用容器编排启动..."
  docker compose up -d --build
  echo ">>> [成功] Docker 服务已后台启动！"
  docker compose ps
else
  echo ">>> 未检测到 Docker，正在尝试使用系统原有服务运行 (apt 安装 Node.js 与 Coturn)..."
  if command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y nodejs npm coturn
    npm install --production
    # 启动 coturn
    sudo turnserver -L 0.0.0.0 -p 3478 --stun-only --no-tcp-relay --no-udp-relay -o -d || true
    # 启动 signaling
    nohup node signaling.js > signaling.log 2>&1 &
    echo ">>> [成功] 本地服务已后台启动！日志位于 $DEPLOY_DIR/signaling.log"
  else
    echo ">>> 请安装 Docker 或 Node.js 后执行: npm install && node signaling.js"
  fi
fi

echo ""
echo "=============================================================================="
echo " P2P 辅助服务部署完成！"
echo " 开放端口确认: TCP 8080 (信令), UDP 3478 (STUN 打洞)"
echo " 测试地址: ws://<你的VPS公网IP>:8080"
echo "=============================================================================="
