// Presence (#34, ADR 0005): "online" is derived from the live-connection
// registry and never stored. Only the moment a User's last live socket
// disconnects is persisted, as `User.lastSeenAt`, so "last seen" survives a
// restart while "online" always reflects who's actually connected right now.
export function createPresenceService({ prisma, registry, clock }) {
  // The Users who share at least one Conversation with `userId` — the
  // audience allowed to see their presence (`CONTEXT.md`).
  async function audienceFor(userId, conversationIds) {
    if (conversationIds.length === 0) return [];
    const rows = await prisma.participant.findMany({
      where: { conversationId: { in: conversationIds }, userId: { not: userId } },
      select: { userId: true },
      distinct: ['userId'],
    });
    return rows.map((row) => row.userId);
  }

  return {
    audienceFor,

    // `{ users: [{ userId, online, lastSeenAt }] }` for everyone in
    // `userId`'s audience — sent once, right after every successful connect.
    async snapshotFor(userId, conversationIds) {
      const audience = await audienceFor(userId, conversationIds);
      if (audience.length === 0) return { users: [] };
      const rows = await prisma.user.findMany({
        where: { id: { in: audience } },
        select: { id: true, lastSeenAt: true },
      });
      const lastSeenById = new Map(rows.map((row) => [row.id, row.lastSeenAt]));
      return {
        users: audience.map((id) => {
          const online = registry.isOnline(id);
          return { userId: id, online, lastSeenAt: online ? null : (lastSeenById.get(id) ?? null) };
        }),
      };
    },

    // Persists `lastSeenAt = now` for `userId` — called once their last live
    // socket disconnects (never while they still have one, since "online"
    // itself is never stored).
    markOffline(userId) {
      return prisma.user.update({ where: { id: userId }, data: { lastSeenAt: clock.now() } });
    },

    // Graceful shutdown (#34): every currently online User's `lastSeenAt` is
    // written before sockets close, so a deliberate restart doesn't leave
    // "last seen" wrong until they next connect and disconnect (a crash,
    // unlike this, is a documented known limitation).
    async markAllOfflineForShutdown() {
      const userIds = registry.onlineUserIds();
      if (userIds.length === 0) return;
      await prisma.user.updateMany({
        where: { id: { in: userIds } },
        data: { lastSeenAt: clock.now() },
      });
    },
  };
}
