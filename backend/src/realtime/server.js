import { Server } from 'socket.io';

import { createMessageDeleter } from '../messaging/deleteMessage.js';
import { createMessageEditor } from '../messaging/editMessage.js';
import { createReadMarker } from '../messaging/markRead.js';
import { createPump } from '../messaging/pump.js';
import { createSendRateLimit } from '../messaging/rateLimiter.js';
import { createReactionToggler } from '../messaging/reactionToggle.js';
import { createMessageSender } from '../messaging/sendMessage.js';
import { resolveStartSeq } from '../messaging/syncState.js';
import { createConnectionRegistry } from './registry.js';

export const userRoom = (userId) => `user:${userId}`;
export const conversationRoom = (conversationId) => `conversation:${conversationId}`;

// The Socket.IO server, not yet attached to an HTTP server. Every socket is
// authenticated at its handshake and joined to its rooms by the server;
// clients can't join or leave rooms themselves (ADR 0005).
export function createRealtime({ prisma, authenticate, clock, sessionRevoked, pumpOptions = {} }) {
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
  const rateLimiter = createSendRateLimit({ clock });
  const pumpsByUser = new Map(); // userId -> Set<pump>, every live pump of theirs

  function addPump(userId, pump) {
    let pumps = pumpsByUser.get(userId);
    if (!pumps) pumpsByUser.set(userId, (pumps = new Set()));
    pumps.add(pump);
  }

  function removePump(userId, pump) {
    const pumps = pumpsByUser.get(userId);
    if (!pumps) return;
    pumps.delete(pump);
    if (pumps.size === 0) pumpsByUser.delete(userId);
  }

  // The Update writer's `onWake` hook (ADR 0008): every one of this User's
  // connected pumps notices a new Update immediately, across all Devices.
  function wakeUser(userId) {
    for (const pump of pumpsByUser.get(userId) ?? []) pump.wake();
  }

  const sendMessage = createMessageSender({ prisma, rateLimiter, onWake: wakeUser });
  const editMessage = createMessageEditor({ prisma, rateLimiter, onWake: wakeUser });
  const deleteMessage = createMessageDeleter({ prisma, onWake: wakeUser });
  const toggleReaction = createReactionToggler({ prisma, rateLimiter, onWake: wakeUser });
  const markRead = createReadMarker({ prisma, onWake: wakeUser });

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
    const { startSeq, resetSeq } = await resolveStartSeq(
      prisma,
      auth.userId,
      socket.handshake.auth?.since,
    );
    socket.data = {
      ...auth,
      rooms: [
        userRoom(auth.userId),
        ...participants.map(({ conversationId }) => conversationRoom(conversationId)),
      ],
      startSeq,
      resetSeq,
    };
    return undefined;
  }

  io.on('connection', (socket) => {
    const { userId, sessionId, rooms, startSeq, resetSeq } = socket.data;
    registry.register(socket.id, { userId, sessionId });
    socket.join(rooms);
    // The handshake extension (#48/ADR 0008): a Device too far behind (or
    // connecting for the first time) is told to rebuild from a snapshot and
    // resume from here, instead of the pump trying to resend a gap it can't.
    if (resetSeq !== null) socket.emit('sync:reset', { currentSeq: resetSeq });

    const pump = createPump({ prisma, socket, userId, startSeq, onWake: wakeUser, ...pumpOptions });
    addPump(userId, pump);
    pump.wake();

    function handle(action) {
      return async (payload, callback) => {
        try {
          const result = await action(userId, payload);
          callback?.(result);
        } catch (err) {
          // Never ack an unexpected failure (a DB hiccup, say) as `INVALID`:
          // that code means "bad request" and isn't retryable, but a
          // transient fault is. Leaving it unacked lets the client's own
          // ack-timeout-driven retry run instead, which every one of these
          // actions is built to accept safely (clientMsgId, edits setting a
          // value, deletes flagging, reactions keyed by their unique
          // constraint).
          console.error(err);
        }
      };
    }

    socket.on('message:send', handle(sendMessage));
    socket.on('message:edit', handle(editMessage));
    socket.on('message:delete', handle(deleteMessage));
    socket.on('reaction:toggle', handle(toggleReaction));
    socket.on('conversation:read', handle(markRead));

    socket.on('disconnect', () => {
      pump.stop();
      removePump(userId, pump);
      registry.unregister(socket.id);
    });
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
