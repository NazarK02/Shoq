const WebSocket = require("ws");

const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT });
const clients = new Map(); // userId -> Set<ws>
const socketToUser = new Map(); // ws -> userId

function safeSend(ws, payload) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(payload));
}

function unregisterSocket(ws) {
  const userId = socketToUser.get(ws);
  if (!userId) return;

  socketToUser.delete(ws);
  const sockets = clients.get(userId);
  if (!sockets) return;

  sockets.delete(ws);
  if (sockets.size === 0) {
    clients.delete(userId);
  }
}

function registerSocket(userId, clientId, ws) {
  const prevUserId = socketToUser.get(ws);
  if (prevUserId && prevUserId !== userId) {
    unregisterSocket(ws);
  }

  ws.clientId = clientId || null;
  socketToUser.set(ws, userId);
  if (!clients.has(userId)) {
    clients.set(userId, new Set());
  }
  clients.get(userId).add(ws);
}

wss.on("connection", (ws) => {
  ws.on("message", (raw) => {
    let data = null;
    try {
      data = JSON.parse(raw.toString());
    } catch (_) {
      return;
    }

    if (!data || typeof data !== "object") return;

    if (data.type === "register" && data.userId) {
      registerSocket(
        String(data.userId),
        data.clientId ? String(data.clientId) : null,
        ws
      );
      return;
    }

    // Forward to target user if present
    if (data.to) {
      const targetId = String(data.to);
      const targets = clients.get(targetId);
      if (!targets) return;

      const targetClientId = data.toClientId ? String(data.toClientId) : null;
      if (!targetClientId) {
        for (const target of targets) {
          safeSend(target, data);
        }
        return;
      }

      let delivered = false;
      for (const target of targets) {
        if (target.clientId === targetClientId) {
          safeSend(target, data);
          delivered = true;
        }
      }

      // Fallback for older clients that don't send/register clientId yet.
      if (!delivered) {
        for (const target of targets) {
          safeSend(target, data);
        }
      }
    }
  });

  ws.on("close", () => {
    unregisterSocket(ws);
  });
});

console.log(`Signaling server running on ws://0.0.0.0:${PORT}`);
