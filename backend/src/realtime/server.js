import { Server } from 'socket.io';

import { createConnectionRegistry } from './registry.js';

export const userRoom = (userId) => `user:${userId}`;
export const conversationRoom = (conversationId) => `conversation:${conversationId}`;

// The Socket.IO server, not yet attached to an HTTP server. Every socket is
// authenticated at its handshake and joined to its rooms by the server;
// clients can't join or leave rooms themselves (ADR 0005).
export function createRealtime({ prisma, authenticate, sessionRevoked }) {
  // The only client is the app, so no HTTP long-polling fallback.
  const io = new Server({ transports: ['websocket'] });
  const registry = createConnectionRegistry();

  // Revocation reaches open sockets immediately (ADR 0005, #33): logout,
  // logout-others and refresh-token reuse detection all fire this hook.
  // `disconnect(true)` is a server-initiated close, which the client sees
  // (and its library doesn't retry) unlike a dropped transport. Normal
  // disconnect handling then updates the registry.
  sessionRevoked?.subscribe(({ sessionId }) => {
    for (const socketId of registry.socketsForSession(sessionId)) {
      const socket = io.sockets.sockets.get(socketId);
      if (!socket) continue;
      socket.emit('sessionRevoked', {});
      socket.disconnect(true);
    }
  });

  // Rejecting here refuses the connection outright, as a `connect_error`,
  // rather than accepting it and booting it afterwards. The token is read
  // from the auth payload only: a query string lands in access logs. Once
  // accepted, a socket isn't re-checked when its token expires: revocation
  // is to be pushed to it instead (ADR 0005).
  io.use((socket, next) => {
    // A failure (the database being down, say) must still answer the
    // handshake, or the client waits until its connect timeout.
    admit(socket).then(
      (error) => next(error),
      (err) => {
        console.error(err);
        next(new Error('server_error'));
      },
    );
  });

  // Readies an authenticated socket, or returns the error refusing it.
  async function admit(socket) {
    const token = socket.handshake.auth?.token;
    const auth = typeof token === 'string' ? await authenticate(token) : null;
    if (!auth) return new Error('unauthenticated');
    // Looked up before the connection is accepted, so the socket is in all
    // of its rooms by the time the client sees `connect`.
    const participants = await prisma.participant.findMany({
      where: { userId: auth.userId },
      select: { conversationId: true },
    });
    socket.data = {
      ...auth,
      rooms: [
        userRoom(auth.userId),
        ...participants.map(({ conversationId }) => conversationRoom(conversationId)),
      ],
    };
    return undefined;
  }

  io.on('connection', (socket) => {
    const { userId, sessionId, rooms } = socket.data;
    registry.register(socket.id, { userId, sessionId });
    socket.join(rooms);
    socket.on('disconnect', () => registry.unregister(socket.id));
  });

  // Moves an already-connected user's live sockets, across every Device, into
  // or out of a Conversation's room without them reconnecting. A no-op while
  // the user is offline: their next connection's auto-join picks up the
  // current Participant rows instead (ADR 0005).
  function changeConversationMembership(action, { userId, conversationId }) {
    const socketIds = registry.socketsForUser(userId);
    if (socketIds.length > 0) io.in(socketIds)[action](conversationRoom(conversationId));
  }

  // Any code that creates a Participant row must call this.
  function joinUserToConversation(args) {
    changeConversationMembership('socketsJoin', args);
  }

  // Any code that deletes a Participant row must call this.
  function removeUserFromConversation(args) {
    changeConversationMembership('socketsLeave', args);
  }

  // Kills the raw transport under each of the Session's live sockets without
  // a Socket.IO disconnect packet, so the client sees its connection die the
  // way a dropped network does (not the way a server-initiated disconnect
  // does) and its own reconnection logic runs, rather than being told to
  // stop retrying.
  function dropTransports(sessionId) {
    for (const socketId of registry.socketsForSession(sessionId)) {
      const socket = io.sockets.sockets.get(socketId);
      socket?.conn.transport.socket?.terminate();
    }
  }

  return {
    io,
    registry,
    joinUserToConversation,
    removeUserFromConversation,
    dropTransports,
  };
}
