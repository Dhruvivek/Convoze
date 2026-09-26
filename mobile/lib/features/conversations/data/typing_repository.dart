import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../core/realtime/connection_manager.dart';
import '../../../core/storage/token_store.dart';

part 'typing_repository.g.dart';

/// The `typing`/`stopTyping` relay (#35): who is composing in each
/// Conversation, from the server's point of view — never our own `userId`,
/// which the server never echoes back anyway (excluded at the source), but
/// double-checked here for a second Device of our own (`connectAs` on a
/// socket other than the one we attached to, say).
///
/// Stateless like the server: nothing here survives a disconnect —
/// [clearAll] is called by `typingRepositoryProvider` the moment the app's
/// own connection status leaves `connected`.
class TypingRepository {
  TypingRepository({
    required this.tokenStore,
    this.sendThrottle = const Duration(seconds: 3),
    this.idleTimeout = const Duration(seconds: 5),
    this.receiverTimeout = const Duration(seconds: 6),
  });

  final TokenStore tokenStore;

  /// How often outgoing `typing` is sent while the input keeps changing.
  final Duration sendThrottle;

  /// How long without a keystroke before `stopTyping` is sent on its own.
  final Duration idleTimeout;

  /// How long a typer stays listed after their last `typing`, absent a
  /// `stopTyping` or `userOffline` clearing them sooner. Overridable
  /// (constructor defaults match #35's spec) so tests don't wait the real
  /// several seconds out.
  final Duration receiverTimeout;

  io.Socket? _socket;

  // conversationId -> userId -> the Timer that expires that typer.
  final _typersByConversation = <String, Map<String, Timer>>{};
  final _changes = StreamController<Map<String, Set<String>>>.broadcast();

  // conversationId -> the Timer that sends stopTyping after idleTimeout.
  final _idleTimers = <String, Timer>{};

  // conversationId -> when `typing` was last actually sent (throttle).
  final _lastSentAt = <String, DateTime>{};

  /// Every Conversation with at least one current typer, mapped to their
  /// user ids.
  Map<String, Set<String>> get current => {
    for (final entry in _typersByConversation.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value.keys.toSet(),
  };

  /// [current], then every subsequent change.
  Stream<Map<String, Set<String>>> get changes => Stream.multi((controller) {
    controller.add(current);
    final sub = _changes.stream.listen(controller.add, onDone: controller.close);
    controller.onCancel = sub.cancel;
  });

  /// Registers this repository's handlers on [socket] and remembers it for
  /// outgoing `typing`/`stopTyping`. Call once per new socket instance
  /// (`ConnectionManager.socketCreated`'s own contract).
  void attach(io.Socket socket) {
    _socket = socket;
    socket
      ..on('typing', _handleTyping)
      ..on('stopTyping', _handleStopTyping)
      ..on('userOffline', _handleUserOffline);
  }

  // --- Sending -------------------------------------------------------------

  /// Call on every composer change for [conversationId]. Sends `typing`
  /// (throttled to at most once per [sendThrottle]) while [text] is
  /// non-empty, resets the idle timer, and sends `stopTyping` at once if
  /// [text] is empty (ADR 0005: "cleared the input").
  void composerChanged(String conversationId, String text) {
    if (text.isEmpty) {
      stopTyping(conversationId);
      return;
    }
    _idleTimers[conversationId]?.cancel();
    _idleTimers[conversationId] = Timer(
      idleTimeout,
      () => stopTyping(conversationId),
    );

    final lastSent = _lastSentAt[conversationId];
    final now = DateTime.now();
    if (lastSent != null && now.difference(lastSent) < sendThrottle) return;
    _lastSentAt[conversationId] = now;
    _socket?.emit('typing', {'conversationId': conversationId});
  }

  /// Sends `stopTyping` for [conversationId] and clears this Device's own
  /// throttle/idle state for it — call on send, on clearing the composer, or
  /// when leaving the chat screen, on top of [composerChanged]'s own idle
  /// timeout.
  void stopTyping(String conversationId) {
    _idleTimers.remove(conversationId)?.cancel();
    _lastSentAt.remove(conversationId);
    _socket?.emit('stopTyping', {'conversationId': conversationId});
  }

  // --- Receiving -------------------------------------------------------------

  Future<void> _handleTyping(dynamic data) =>
      _handleRemoteEvent(data, _addTyper);

  Future<void> _handleStopTyping(dynamic data) =>
      _handleRemoteEvent(data, _removeTyper);

  /// Shared shape of `typing`/`stopTyping`: decode `{conversationId, userId}`,
  /// drop it if it's our own userId (a second Device of ours), otherwise
  /// [apply] it.
  Future<void> _handleRemoteEvent(
    dynamic data,
    void Function(String conversationId, String userId) apply,
  ) async {
    final payload = (data as Map).cast<String, dynamic>();
    final userId = payload['userId'] as String;
    if (userId == await _myUserId()) return;
    apply(payload['conversationId'] as String, userId);
  }

  void _handleUserOffline(dynamic data) {
    final userId = ((data as Map)['userId']) as String;
    for (final conversationId in _typersByConversation.keys.toList()) {
      _removeTyper(conversationId, userId);
    }
  }

  Future<String?> _myUserId() async => (await tokenStore.readUser())?.id;

  void _addTyper(String conversationId, String userId) {
    final byUser = _typersByConversation.putIfAbsent(conversationId, () => {});
    byUser[userId]?.cancel();
    byUser[userId] = Timer(
      receiverTimeout,
      () => _removeTyper(conversationId, userId),
    );
    _emit();
  }

  void _removeTyper(String conversationId, String userId) {
    final byUser = _typersByConversation[conversationId];
    final timer = byUser?.remove(userId);
    if (timer == null) return;
    timer.cancel();
    if (byUser!.isEmpty) _typersByConversation.remove(conversationId);
    _emit();
  }

  /// Drops every typer, in every Conversation, with no `stopTyping` sent for
  /// any of them — there's nobody left to tell (#35: "all typing state is
  /// dropped whenever the app's own socket disconnects").
  void clearAll() {
    final hadAny = _typersByConversation.isNotEmpty;
    for (final byUser in _typersByConversation.values) {
      for (final timer in byUser.values) {
        timer.cancel();
      }
    }
    _typersByConversation.clear();
    for (final timer in _idleTimers.values) {
      timer.cancel();
    }
    _idleTimers.clear();
    _lastSentAt.clear();
    if (hadAny) _emit();
  }

  void _emit() => _changes.add(current);
}

@Riverpod(keepAlive: true)
TypingRepository typingRepository(Ref ref) {
  final repository = TypingRepository(tokenStore: ref.watch(tokenStoreProvider));
  final manager = ref.read(connectionManagerProvider);
  final socketSubscription = manager.socketCreated.listen(repository.attach);
  final statusSubscription = manager.statusStream.listen((status) {
    if (status != ConnectionStatus.connected) repository.clearAll();
  });
  ref.onDispose(() {
    socketSubscription.cancel();
    statusSubscription.cancel();
  });
  return repository;
}
