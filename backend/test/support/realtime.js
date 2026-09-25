import { io as connectClient } from 'socket.io-client';

import { buildTestApp } from './testApp.js';

// Builds the app like buildTestApp, and listens on a random port so real
// Socket.IO clients can connect. Callers close it with `stop()`.
export async function startTestServer(options) {
  const built = buildTestApp(options);
  const { httpServer } = built;
  await new Promise((resolve) => httpServer.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${httpServer.address().port}`;
  const clients = [];

  return {
    ...built,
    url,
    // An unconnected client; `auth` and `query` go into its handshake.
    client({ auth, query } = {}) {
      const socket = connectClient(url, {
        auth,
        query,
        transports: ['websocket'],
        reconnection: false,
        autoConnect: false,
        forceNew: true,
      });
      clients.push(socket);
      return socket;
    },
    async stop() {
      for (const socket of clients) socket.disconnect();
      await new Promise((resolve) => built.realtime.io.close(() => resolve()));
    },
  };
}

// Connects `socket`, resolving on `connect` and rejecting with the
// `connect_error`.
export function connect(socket) {
  return new Promise((resolve, reject) => {
    socket.once('connect', () => resolve(socket));
    socket.once('connect_error', reject);
    socket.connect();
  });
}

// Resolves with the payload of the next `event` on `socket`, or with
// `timedOut` if none arrives within `ms`.
export function nextEvent(socket, event, ms = 500) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      socket.off(event, onEvent);
      resolve(timedOut);
    }, ms);
    function onEvent(payload) {
      clearTimeout(timer);
      resolve(payload);
    }
    socket.once(event, onEvent);
  });
}

export const timedOut = Symbol('timedOut');

// Polls `condition` until it holds, failing after `ms`: for server-side
// effects of a client's disconnect, which the client can't observe.
export async function waitFor(condition, ms = 1000) {
  const deadline = Date.now() + ms;
  while (!(await condition())) {
    if (Date.now() > deadline) throw new Error(`Condition not met within ${ms}ms`);
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}
