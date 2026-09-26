import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/realtime/connection_manager.dart';

part 'presence_repository.g.dart';

/// A User's presence exactly as the server last reported it (#34): never
/// downgraded for our own connection being down — that's
/// [PresenceState]/`presenceProvider`'s job, one layer up.
class RawPresence {
  const RawPresence({required this.online, this.lastSeenAt});

  final bool online;

  /// Null while [online], or if the server has never seen them disconnect.
  final DateTime? lastSeenAt;
}

/// Turns the server's `presenceSnapshot`/`userOnline`/`userOffline` events
/// (#34) into a per-user [RawPresence] map. A snapshot **replaces** all
/// previously held state; the two incremental events update one entry.
class PresenceRepository {
  final _byUserId = <String, RawPresence>{};
  final _changes = StreamController<Map<String, RawPresence>>.broadcast();

  /// The current state of every User this Device has ever been told about.
  Map<String, RawPresence> get current => Map.unmodifiable(_byUserId);

  /// [current], then every subsequent change.
  Stream<Map<String, RawPresence>> get changes => Stream.multi((controller) {
    controller.add(current);
    final sub = _changes.stream.listen(controller.add, onDone: controller.close);
    controller.onCancel = sub.cancel;
  });

  /// Registers this repository's handlers on [socket]. Call once per new
  /// socket instance (`ConnectionManager.socketCreated`'s own contract) —
  /// automatic reconnects reuse it, so this never needs to run again for the
  /// same socket.
  void attach(io.Socket socket) {
    socket
      ..on('presenceSnapshot', (data) => _applySnapshot(data))
      ..on('userOnline', (data) => _applyOnline(data))
      ..on('userOffline', (data) => _applyOffline(data));
  }

  void _applySnapshot(dynamic data) {
    final payload = (data as Map).cast<String, dynamic>();
    final users = (payload['users'] as List).cast<Map>();
    _byUserId
      ..clear()
      ..addEntries(
        users.map((raw) {
          final user = raw.cast<String, dynamic>();
          return MapEntry(
            user['userId'] as String,
            RawPresence(
              online: user['online'] as bool,
              lastSeenAt: _parseTime(user['lastSeenAt']),
            ),
          );
        }),
      );
    _emit();
  }

  void _applyOnline(dynamic data) {
    final userId = ((data as Map)['userId']) as String;
    _byUserId[userId] = const RawPresence(online: true);
    _emit();
  }

  void _applyOffline(dynamic data) {
    final payload = (data as Map).cast<String, dynamic>();
    final userId = payload['userId'] as String;
    _byUserId[userId] = RawPresence(
      online: false,
      lastSeenAt: _parseTime(payload['lastSeenAt']),
    );
    _emit();
  }

  DateTime? _parseTime(Object? value) =>
      value == null ? null : DateTime.parse(value as String);

  void _emit() => _changes.add(current);
}

@Riverpod(keepAlive: true)
PresenceRepository presenceRepository(Ref ref) {
  final repository = PresenceRepository();
  final subscription = ref
      .read(connectionManagerProvider)
      .socketCreated
      .listen(repository.attach);
  ref.onDispose(subscription.cancel);
  return repository;
}
