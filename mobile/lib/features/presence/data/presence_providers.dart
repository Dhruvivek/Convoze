import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/realtime/connection_manager.dart';
import 'presence_repository.dart';
import 'presence_state.dart';

part 'presence_providers.g.dart';

/// The moment this Device's own connection was last seen leaving `connected`
/// — null while connected, or if it never has dropped. The anchor
/// [presence]'s `lastSeen` downgrade uses while our own socket is down
/// (#34, `CONTEXT.md` **Presence**), since nothing more recent than that can
/// be vouched for.
@Riverpod(keepAlive: true)
class OwnDisconnectedAt extends _$OwnDisconnectedAt {
  @override
  DateTime? build() {
    ref.listen(connectionStatusProvider, (_, next) {
      if (next.value == ConnectionStatus.connected) {
        state = null;
      } else if (state == null) {
        state = DateTime.now().toUtc();
      }
    });
    final current = ref.read(connectionStatusProvider).value;
    return current == ConnectionStatus.connected ? null : DateTime.now().toUtc();
  }
}

/// [PresenceRepository.current], then every change — a plain
/// `Map<String, RawPresence>` rather than the repository object itself, so
/// [presence] rebuilds on every emission rather than once per new instance.
@Riverpod(keepAlive: true)
Stream<Map<String, RawPresence>> presenceMap(Ref ref) =>
    ref.watch(presenceRepositoryProvider).changes;

/// One User's presence as this Device should show it right now (#34):
/// `online`/`lastSeen`/`unknown`, already downgraded for our own connection
/// being down. The conversation list and chat header just watch this.
@riverpod
PresenceState presence(Ref ref, String userId) {
  final byUserId = ref.watch(presenceMapProvider).value ?? const {};
  final raw = byUserId[userId];
  if (raw == null) return const PresenceUnknown();

  final connected = ref.watch(connectionStatusProvider).value == ConnectionStatus.connected;
  if (raw.online && connected) return const PresenceOnline();
  if (raw.online) {
    // Reported online, but our own connection is down: not confidently
    // "offline" — the last moment we could actually vouch for anything.
    final droppedAt = ref.watch(ownDisconnectedAtProvider) ?? DateTime.now().toUtc();
    return PresenceLastSeen(droppedAt);
  }
  // Offline with no `lastSeenAt` at all means the server has never seen
  // them disconnect (never used the app, say) — nothing to show yet.
  final lastSeenAt = raw.lastSeenAt;
  return lastSeenAt == null ? const PresenceUnknown() : PresenceLastSeen(lastSeenAt);
}
