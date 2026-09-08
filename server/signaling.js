/**
 * Ultra-lightweight WebRTC P2P Signaling Server with Avatar & Smart Reconnect Support
 * 
 * Responsibilities:
 * 1. User registration with persistent User ID & customizable Avatar
 * 2. Instant cleanup of renamed or disconnected users (zero ghost devices)
 * 3. Forwarding WebRTC negotiation messages (offer, answer, ICE candidates)
 * 4. Forwarding call control signals (call, accept, reject, hangup)
 * 5. Ping/pong heartbeat to keep mobile connections alive
 */

const { WebSocketServer, WebSocket } = require('ws');

const PORT = process.env.PORT || 8080;
const wss = new WebSocketServer({ port: PORT });

// Map of userId -> { ws: WebSocket, avatar: string }
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
      // 1. User registers their ID and avatar on the signaling server
      case 'register': {
        const userId = data.userId?.trim();
        const avatar = data.avatar || 'pilot';

        if (!userId) {
          ws.send(JSON.stringify({ type: 'error', message: 'User ID cannot be empty' }));
          return;
        }

        // Clean up previous userId on the same connection if renamed
        if (currentUserId && currentUserId !== userId) {
          clients.delete(currentUserId);
          broadcastUserStatus(currentUserId, false);
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
        clients.set(userId, { ws, avatar });
        ws.userId = userId;

        console.log(`[Signaling] User registered: "${userId}" (Avatar: ${avatar}) (Total online: ${clients.size})`);

        // Format online list with avatars
        const onlineList = Array.from(clients.entries())
          .filter(([id]) => id !== userId)
          .map(([id, info]) => ({ userId: id, avatar: info.avatar }));

        ws.send(JSON.stringify({
          type: 'registered',
          userId: userId,
          avatar: avatar,
          onlineUsers: onlineList
        }));

        // Broadcast to other users that a new user came online
        broadcastUserStatus(userId, true, avatar);
        break;
      }

      // 2. Explicit unregister
      case 'unregister': {
        if (currentUserId && clients.has(currentUserId)) {
          clients.delete(currentUserId);
          console.log(`[Signaling] User "${currentUserId}" unregistered`);
          broadcastUserStatus(currentUserId, false);
          currentUserId = null;
        }
        break;
      }

      // 3. Query online user list
      case 'get_users': {
        const onlineList = Array.from(clients.entries())
          .filter(([id]) => id !== currentUserId)
          .map(([id, info]) => ({ userId: id, avatar: info.avatar }));

        ws.send(JSON.stringify({ type: 'user_list', users: onlineList }));
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

wss.on('close', () => {
  clearInterval(interval);
});
