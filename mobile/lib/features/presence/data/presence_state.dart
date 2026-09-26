/// A User's presence as this Device should show it (#34) — [RawPresence]
/// (`presence_repository.dart`) downgraded for our own connection being
/// down (`CONTEXT.md` **Presence**: never a confident "offline" during that
/// gap).
sealed class PresenceState {
  const PresenceState();
}

class PresenceOnline extends PresenceState {
  const PresenceOnline();
}

/// Either the server's own `lastSeenAt` for them, or — while this Device's
/// own connection is down and they were last known online — the moment
/// *our* connection dropped, since anything more recent than that can't be
/// vouched for.
class PresenceLastSeen extends PresenceState {
  const PresenceLastSeen(this.time);

  final DateTime time;
}

/// Nothing has been heard about this User yet (no snapshot has arrived, or
/// they aren't in it — never in anyone's presence audience).
class PresenceUnknown extends PresenceState {
  const PresenceUnknown();
}
