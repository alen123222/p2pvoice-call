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

// Map of userId -> { ws: WebSocket, avatar: string }
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
          clients.delete(currentUserId);
          broadcastUserStatus(currentUserId, false, clients.get(currentUserId));
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
