# 发送给 VPS AI 助手“66”的指令

请复制以下整段文本，直接发给您 VPS 上的助手“66”：

```markdown
报告 66！我们刚刚在客户端完成了【自定义头像同步】与【改名防幽灵设备即时清理】功能。
请帮我更新 /opt/p2p-server/signaling.js 为以下最新代码，并重启信令容器：

1. 写入更新后的 signaling.js：

cat << 'EOF' > /opt/p2p-server/signaling.js
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

        // 清理同连接改名前的旧 ID，杜绝幽灵设备
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

2. 重新构建并启动 signaling 容器：
cd /opt/p2p-server && docker compose up -d --build signaling

3. 检查容器日志，确认运行正常：
docker logs --tail 20 p2p-signaling
```
