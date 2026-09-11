# 服务端升级部署说明 —— P2P 语音通话「自定义头像同步」

> 交给 66：请把服务器上的信令服务文件 `signaling.js` 整份替换为下面的内容，然后重启服务。改动文件只有这一个，没有新增 npm 依赖（仍然只需要 `ws`）。

---

## 一、背景与目标

App 端已支持用户从相册设置「自定义头像」。为了让**其他设备**也能看到该自定义头像，信令服务器需要在用户注册/上线/呼叫时，把头像图片数据（base64）一并存储并转发。

旧版服务器只会转发头像 ID（字符串，如 `custom_1726...`），其他设备拿不到图片，因此看不到自定义头像。

旧版服务器**不会因此报错**，只是该功能不生效。所以本次是纯增强，不影响现有通话。

---

## 二、要部署的文件

| 文件 | 说明 |
|---|---|
| `signaling.js` | 唯一需要更新的文件（Node.js WebSocket 信令服务） |

无新增依赖；无需改动 `package.json`、`Dockerfile`、`docker-compose.yml`。

---

## 三、完整文件内容（请整份替换服务器上的 `signaling.js`）

```javascript
/**
 * Lightweight WebRTC P2P Signaling Server with Avatar & Smart Reconnect Support
 *
 * Responsibilities:
 * 1. User registration with persistent User ID & customizable Avatar
 * 2. Instant cleanup of renamed or disconnected users (zero ghost devices)
 * 3. Forwarding WebRTC negotiation messages (offer, answer, ICE candidates)
 * 4. Forwarding call control signals (call, accept, reject, hangup)
 * 5. Ping/pong heartbeat to keep mobile connections alive
 * 6. Optional shared-token auth and time-limited TURN credentials (TURN REST API)
 *
 * Environment variables:
 *   PORT             Listening port (default 8080)
 *   SIGNALING_TOKEN  Optional shared secret required at registration
 *   ALLOWED_ORIGINS  Optional comma-separated list of allowed WebSocket origins
 *   TURN_SERVER      Optional "host:port" of the Coturn server (enables TURN)
 *   TURN_SECRET      Shared secret used for TURN REST API (HMAC-SHA1)
 *   TURN_TTL         TURN credential lifetime in seconds (default 3600)
 */

const crypto = require('crypto');
const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 8080;
const SIGNALING_TOKEN = process.env.SIGNALING_TOKEN || null;
const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean)
  : null;
const TURN_SERVER = process.env.TURN_SERVER || null;
const TURN_SECRET = process.env.TURN_SECRET || null;
const TURN_TTL = Number(process.env.TURN_TTL) || 3600;

// Reasonable limits to prevent abuse of a single connection.
const MAX_PAYLOAD_BYTES = 1024 * 1024; // 1 MB (accommodates base64 avatars)
const MAX_MESSAGES_PER_SECOND = 200;
const MAX_AVATAR_IMAGE_CHARS = 256 * 1024; // 256 KB of base64

const wss = new WebSocketServer({ port: PORT, maxPayload: MAX_PAYLOAD_BYTES });

// Map of userId -> { ws: WebSocket, avatar: string, avatarImage: string|null }
const clients = new Map();

console.log(`[Signaling] P2P Signaling Server running on port ${PORT}`);
console.log(`[Signaling] Auth ${SIGNALING_TOKEN ? 'enabled (shared token)' : 'disabled'}`);
console.log(`[Signaling] TURN ${TURN_SERVER && TURN_SECRET ? `enabled (${TURN_SERVER})` : 'disabled'}`);

function isValidUserId(id) {
  return typeof id === 'string' && /^[\w.-]{1,64}$/.test(id);
}

function isValidAvatar(avatar) {
  return typeof avatar === 'string' && avatar.length > 0 && avatar.length <= 64;
}

function sanitizeAvatarImage(image) {
  if (typeof image !== 'string') return null;
  const trimmed = image.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_AVATAR_IMAGE_CHARS) return null;
  return trimmed;
}

/**
 * Build a short-lived TURN credential using the standard Coturn REST API:
 * username = expiry timestamp, credential = base64(HMAC-SHA1(secret, username)).
 */
function buildTurnCredentials() {
  if (!TURN_SERVER || !TURN_SECRET) return null;
  const expiry = Math.floor(Date.now() / 1000) + TURN_TTL;
  const username = String(expiry);
  const credential = crypto
    .createHmac('sha1', TURN_SECRET)
    .update(username)
    .digest('base64');
  return {
    username,
    credential,
    ttl: TURN_TTL,
    uris: [
      `turn:${TURN_SERVER}?transport=udp`,
      `turn:${TURN_SERVER}?transport=tcp`,
    ],
  };
}

wss.on('connection', (ws, req) => {
  const remoteIp = req.socket.remoteAddress;

  // Optional origin allow-list (browser clients only; native apps send no origin).
  if (ALLOWED_ORIGINS) {
    const origin = req.headers.origin;
    if (origin && !ALLOWED_ORIGINS.includes(origin)) {
      console.warn(`[Signaling] Rejected connection from disallowed origin: ${origin}`);
      ws.close(1008, 'Origin not allowed');
      return;
    }
  }

  console.log(`[Signaling] Client connected from ${remoteIp}`);

  let currentUserId = null;
  ws.isAlive = true;

  // Per-connection rate limiting.
  let msgWindowStart = Date.now();
  let msgCount = 0;

  ws.on('pong', () => {
    ws.isAlive = true;
  });

  ws.on('message', (message) => {
    const now = Date.now();
    if (now - msgWindowStart > 1000) {
      msgWindowStart = now;
      msgCount = 0;
    }
    msgCount += 1;
    if (msgCount > MAX_MESSAGES_PER_SECOND) {
      ws.close(1008, 'Rate limit exceeded');
      return;
    }

    let data;
    try {
      data = JSON.parse(message.toString());
    } catch (err) {
      console.error('[Signaling] Malformed JSON message:', err.message);
      return;
    }

    const { type, to, payload } = data;

    switch (type) {
      // 1. User registers their ID and avatar on the signaling server
      case 'register': {
        const userId = data.userId?.trim();
        const avatar = isValidAvatar(data.avatar) ? data.avatar : 'pilot';
        const avatarImage = sanitizeAvatarImage(data.avatarImage);

        if (!isValidUserId(userId)) {
          ws.send(JSON.stringify({ type: 'error', message: 'Invalid user ID' }));
          return;
        }

        if (SIGNALING_TOKEN && data.token !== SIGNALING_TOKEN) {
          ws.send(JSON.stringify({ type: 'error', message: 'Unauthorized: invalid token' }));
          return;
        }

        // Clean up previous userId on the same connection if renamed
        if (currentUserId && currentUserId !== userId) {
          const previousEntry = clients.get(currentUserId);
          clients.delete(currentUserId);
          broadcastUserStatus(currentUserId, false, previousEntry);
          console.log(`[Signaling] User renamed from "${currentUserId}" to "${userId}"`);
        }

        // If another connection already held this ID, disconnect the stale one
        if (clients.has(userId)) {
          const oldEntry = clients.get(userId);
          if (oldEntry && oldEntry.ws !== ws && oldEntry.ws.readyState === WebSocket.OPEN) {
            oldEntry.ws.send(JSON.stringify({ type: 'conflict', message: 'Logged in from another device' }));
            oldEntry.ws.close();
          }
        }

        currentUserId = userId;
        clients.set(userId, { ws, avatar, avatarImage });
        ws.userId = userId;

        console.log(`[Signaling] User registered: "${userId}" (Avatar: ${avatar}) (Total online: ${clients.size})`);

        const onlineList = Array.from(clients.entries())
          .filter(([id]) => id !== userId)
          .map(([id, info]) => ({ userId: id, avatar: info.avatar, avatarImage: info.avatarImage || null }));

        ws.send(JSON.stringify({
          type: 'registered',
          userId: userId,
          avatar: avatar,
          avatarImage: avatarImage || null,
          onlineUsers: onlineList,
        }));

        broadcastUserStatus(userId, true, { avatar, avatarImage });
        break;
      }

      // 2. Explicit unregister
      case 'unregister': {
        if (currentUserId && clients.has(currentUserId)) {
          const entry = clients.get(currentUserId);
          clients.delete(currentUserId);
          console.log(`[Signaling] User "${currentUserId}" unregistered`);
          broadcastUserStatus(currentUserId, false, entry);
          currentUserId = null;
        }
        break;
      }

      // 3. Query online user list
      case 'get_users': {
        const onlineList = Array.from(clients.entries())
          .filter(([id]) => id !== currentUserId)
          .map(([id, info]) => ({ userId: id, avatar: info.avatar, avatarImage: info.avatarImage || null }));

        ws.send(JSON.stringify({ type: 'user_list', users: onlineList }));
        break;
      }

      // 3b. Request time-limited TURN credentials (TURN REST API)
      case 'get_turn': {
        ws.send(JSON.stringify({ type: 'turn_config', turn: buildTurnCredentials() }));
        break;
      }

      // 4. Forward call initiation, offer, answer, ice_candidate, reject, hangup
      case 'call_request':
      case 'call_accepted':
      case 'call_rejected':
      case 'offer':
      case 'answer':
      case 'ice_candidate':
      case 'hangup': {
        if (!currentUserId) {
          ws.send(JSON.stringify({ type: 'error', message: 'Not registered' }));
          return;
        }
        if (!to || !isValidUserId(to)) {
          ws.send(JSON.stringify({ type: 'error', message: 'Target user (to) is required' }));
          return;
        }

        const targetEntry = clients.get(to);
        if (targetEntry && targetEntry.ws.readyState === WebSocket.OPEN) {
          const sender = clients.get(currentUserId);
          targetEntry.ws.send(JSON.stringify({
            type: type,
            from: currentUserId,
            to: to,
            avatar: sender?.avatar || 'pilot',
            avatarImage: sender?.avatarImage || null,
            payload: payload,
          }));
          console.log(`[Signaling] Forwarded [${type}] from [${currentUserId}] to [${to}]`);
        } else {
          console.log(`[Signaling] User [${to}] not found or offline for [${type}]`);
          ws.send(JSON.stringify({
            type: 'user_offline',
            target: to,
            message: `User ${to} is currently offline`,
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
        broadcastUserStatus(currentUserId, false, entry);
      }
    }
  });

  ws.on('error', (err) => {
    console.error(`[Signaling] Socket error on user "${currentUserId}":`, err.message);
  });
});

wss.on('error', (err) => {
  console.error('[Signaling] Server error:', err.message);
});

function broadcastUserStatus(userId, isOnline, entry = {}) {
  const message = JSON.stringify({
    type: isOnline ? 'user_joined' : 'user_left',
    userId: userId,
    avatar: entry?.avatar || 'pilot',
    avatarImage: entry?.avatarImage || null,
  });

  for (const [id, entry] of clients.entries()) {
    if (id !== userId && entry.ws.readyState === WebSocket.OPEN) {
      entry.ws.send(message);
    }
  }
}

// Keepalive heartbeat ping every 20 seconds
const interval = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (ws.isAlive === false) {
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 20000);

function shutdown() {
  console.log('[Signaling] Shutting down gracefully...');
  clearInterval(interval);
  for (const ws of wss.clients) {
    try {
      ws.close(1001, 'Server shutting down');
    } catch (_) {}
  }
  wss.close(() => process.exit(0));
  // Force exit if connections do not close promptly.
  setTimeout(() => process.exit(0), 3000).unref();
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
```

---

## 四、部署步骤

### 方式 A：Docker Compose（推荐）

```bash
# 1. 进入服务器上的项目目录（按你实际路径，例如 /opt/p2p-server）
cd /opt/p2p-server

# 2. 用上面的内容替换 signaling.js 后，重建并重启信令容器
docker compose up -d --build signaling

# 3. 查看日志确认启动成功
docker compose logs -f signaling
```

启动日志应包含：

```
[Signaling] P2P Signaling Server running on port 8080
[Signaling] Auth disabled
[Signaling] TURN disabled        # 未配置 TURN 时正常显示 disabled
```

### 方式 B：直接运行 / pm2

```bash
cd /path/to/server
npm install          # 依赖无变化，通常可跳过
# 用上面的内容替换 signaling.js
pm2 restart p2p-signaling   # 若用 pm2 守护
# 或者：先 kill 旧进程，再 node signaling.js
```

---

## 五、环境变量（全部可选，不设置则保持旧行为）

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `8080` | 监听端口 |
| `SIGNALING_TOKEN` | 空 | 若设置，客户端注册时必须携带相同 token，否则拒绝 |
| `ALLOWED_ORIGINS` | 空 | 逗号分隔的来源白名单（主要给浏览器用，App 不发 origin） |
| `TURN_SERVER` | 空 | Coturn 地址（如 `1.2.3.4:3478`），配合 `TURN_SECRET` 启用临时 TURN 凭据签发 |
| `TURN_SECRET` | 空 | TURN REST API 密钥，须与 coturn 的 `static-auth-secret` 一致 |
| `TURN_TTL` | `3600` | TURN 凭据有效期（秒） |

> 本次头像同步功能**不依赖任何环境变量**。如果之前没有配置 TURN/鉴权，保持不配即可。

---

## 六、部署后验证

1. **端口存活**：`docker compose ps` 或 `ss -lntp | grep 8080` 应显示监听。
2. **日志无报错**：`docker compose logs --tail=100 signaling` 只应有启动信息。
3. **端到端验证（可选）**：用两台装了新 App 的手机：
   - 一方设置自定义头像 → 另一方在「在线设备」列表里应能看到该自定义照片头像。
   - 若仍是默认头像，检查服务器日志里注册行是否打印了该用户。

---

## 七、本次改动清单（供 66 核对）

- `maxPayload` 上限设为 **1 MB**，并新增单张头像 base64 上限 **256 KB**（`MAX_AVATAR_IMAGE_CHARS`）。
- `register` 消息新增接收并存储 `avatarImage`（自定义头像图片，base64）。
- 以下消息现在都会带上 `avatarImage` 字段：
  - `registered`（含 `onlineUsers` 列表）
  - `user_list`
  - `user_joined` / `user_left`
  - 呼叫转发消息（`call_request` / `offer` / `answer` / `ice_candidate` / `hangup` 等）
- 新增 `get_turn` → `turn_config`（可选 TURN 临时凭据，未配置时为 null）。
- 新增 `ping` → `pong` 心跳响应。
- 新增可选 `SIGNALING_TOKEN` 鉴权、`ALLOWED_ORIGINS` 来源校验、每连接消息限流、优雅退出（SIGTERM/SIGINT）。
- 修正了改名时 `user_left` 广播丢失 avatar 的小问题。

> 兼容性：以上全部为向后兼容。App 旧版本连接新服务器、或新 App 连接旧服务器，通话功能均不受影响；仅自定义头像同步需要双方都接上新版服务器。
