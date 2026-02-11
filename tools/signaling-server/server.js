const WebSocket = require("ws");

const PORT = process.env.PORT || 3000;
const wss = new WebSocket.Server({ port: PORT });
const clients = new Map(); // userId -> ws

function safeSend(ws, payload) {
  if (!ws || ws.readyState !== WebSocket.OPEN) return;
  ws.send(JSON.stringify(payload));
}

wss.on("connection", (ws) => {
  let userId = null;

  ws.on("message", (raw) => {
    let data = null;
    try {
      data = JSON.parse(raw.toString());
    } catch (_) {
      return;
    }

    if (!data || typeof data !== "object") return;

    if (data.type === "register" && data.userId) {
      userId = String(data.userId);
      clients.set(userId, ws);
      return;
    }

    // Forward to target user if present
    if (data.to) {
      const targetId = String(data.to);
      const target = clients.get(targetId);
      safeSend(target, data);
    }
  });

  ws.on("close", () => {
    if (userId) {
      clients.delete(userId);
    }
  });
});

console.log(`Signaling server running on ws://0.0.0.0:${PORT}`);
