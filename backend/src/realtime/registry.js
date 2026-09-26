// Which live sockets belong to which Session and User (ADR 0005). In memory,
// so it assumes one server process.
export function createConnectionRegistry() {
  const socketsBySession = new Map(); // sessionId → Set<socketId>
  const sessionsByUser = new Map(); // userId → Set<sessionId>
  const owners = new Map(); // socketId → { userId, sessionId }

  function add(map, key, value) {
    let set = map.get(key);
    if (!set) map.set(key, (set = new Set()));
    set.add(value);
  }

  // Removes `value` from the set at `key`, dropping the set once it's empty.
  function remove(map, key, value) {
    const set = map.get(key);
    set?.delete(value);
    if (set?.size === 0) map.delete(key);
  }

  return {
    // Reports whether this was the user's first live socket (#34: fires
    // `userOnline`), which a reconnecting Session's second socket, or a
    // second Device, is not.
    register(socketId, { userId, sessionId }) {
      const userCameOnline = !sessionsByUser.has(userId);
      owners.set(socketId, { userId, sessionId });
      add(socketsBySession, sessionId, socketId);
      add(sessionsByUser, userId, sessionId);
      return { userCameOnline };
    },

    // Forgets the socket. Reports whether it was its user's last live socket.
    unregister(socketId) {
      const owner = owners.get(socketId);
      if (!owner) return { userWentOffline: false };
      owners.delete(socketId);
      remove(socketsBySession, owner.sessionId, socketId);
      if (!socketsBySession.has(owner.sessionId)) {
        remove(sessionsByUser, owner.userId, owner.sessionId);
      }
      return { userWentOffline: !sessionsByUser.has(owner.userId) };
    },

    socketsForSession(sessionId) {
      return [...(socketsBySession.get(sessionId) ?? [])];
    },

    // Every live socket of the user, across all their Sessions/Devices.
    socketsForUser(userId) {
      const sessionIds = sessionsByUser.get(userId) ?? [];
      return [...sessionIds].flatMap((sessionId) => [...(socketsBySession.get(sessionId) ?? [])]);
    },

    isOnline(userId) {
      return sessionsByUser.has(userId);
    },

    // Every currently online user (#34's graceful-shutdown pass).
    onlineUserIds() {
      return [...sessionsByUser.keys()];
    },
  };
}
