import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../features/auth/presentation/auth_state.dart';
import '../network/dio_provider.dart';
import '../network/session_refresher.dart';
import '../storage/jwt.dart';
import '../storage/token_store.dart';
import '../sync/sync_engine.dart';
import 'socket_factory.dart';

part 'connection_manager.g.dart';

/// This app's own connection to the server; not another User's Presence.
enum ConnectionStatus {
  connecting,
  connected,

  /// The connection dropped and the socket is retrying by itself.
  reconnecting,

  /// Not connected and not trying to be: signed out, or refused.
  offline,
}

/// Owns the app's one live connection to the server (ADR 0005): opens it
/// with the stored access token, closes it on request, and reports its
/// status. Features take the raw [socket] and handle their own events;
/// nothing here parses them.
///
/// Also owns the app-lifecycle policy (ADR 0005): backgrounding
/// ([AppLifecycleState.paused], `.hidden`, `.detached`) disconnects
/// deliberately, and returning to the foreground ([AppLifecycleState.resumed])
/// reconnects. `.inactive` (e.g. a brief system UI overlay) is ignored.
class ConnectionManager with WidgetsBindingObserver {
  ConnectionManager({
    required this._createSocket,
    required this._tokenStore,
    required this._sessionRefresher,
    required this._onSessionEnded,
    required this._readSyncCursor,
    required this._onSocketCreated,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SocketFactory _createSocket;
  final TokenStore _tokenStore;
  final SessionRefresher _sessionRefresher;

  /// The sync engine's stored cursor (#51 / ADR 0008), read fresh for every
  /// (re)connect attempt — including automatic ones — the same way the
  /// token already is, so `since` is never stale.
  final Future<int?> Function() _readSyncCursor;

  /// Lets the sync engine (#51) attach its `sync:*` handlers to a new socket
  /// instance, the same way `sessionRevoked` is wired below — called once
  /// per [connect], before the socket connects.
  final void Function(io.Socket socket) _onSocketCreated;

  /// Tells the app the Session is gone, once its tokens are already cleared
  /// (#20's `AuthState.sessionEnded`), so the router sends it to login.
  final void Function() _onSessionEnded;
  final _statusChanges = StreamController<ConnectionStatus>.broadcast();

  /// How long before its expiry an access token is treated as due for
  /// renewal, so a handshake sent just under the wire doesn't land at the
  /// server already expired.
  static const _refreshSkew = Duration(seconds: 60);

  /// The generation, if any, that has already had one refresh-and-retry
  /// after a handshake rejected for an unauthenticated token. Bounded to one
  /// entry rather than a growing set, since only the current generation is
  /// ever checked again.
  int? _authRetryGeneration;

  /// Whether there's a Session to connect for. Backgrounding while this is
  /// false (or foregrounding before it's true) does nothing.
  bool _authenticated = false;

  /// Bumped by every connect and disconnect, so a connect still reading the
  /// token when it's superseded gives up.
  int _generation = 0;

  io.Socket? _socket;

  /// The live socket, or null while there is none.
  io.Socket? get socket => _socket;

  ConnectionStatus _status = ConnectionStatus.offline;
  ConnectionStatus get status => _status;

  /// The current status, then every change.
  Stream<ConnectionStatus> get statusStream => Stream.multi((controller) {
    controller.add(_status);
    final sub = _statusChanges.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = sub.cancel;
  });

  /// Opens a connection unless one is open or on its way.
  Future<void> connect() async {
    if (_status != ConnectionStatus.offline) return;
    final generation = ++_generation;
    _setStatus(ConnectionStatus.connecting);
    final ready = await _ensureFreshToken();
    if (generation != _generation) return;
    if (!ready) {
      // The Session turned out to be dead; the shared refresher has already
      // sent the app to login. Nothing to connect for.
      _setStatus(ConnectionStatus.offline);
      return;
    }

    // A socket the server refused is dead; don't leave it lying around.
    _socket?.dispose();
    // In the handshake's auth payload, never the URL: URLs end up in logs.
    // A function rather than a fixed map, so it's re-read — and the token
    // re-checked for freshness — on every automatic reconnect too, not just
    // this explicit connect (the "library check" from #32).
    final socket = _createSocket()
      ..auth = (callback) => unawaited(_authenticate(generation, callback));
    _socket = socket;
    _onSocketCreated(socket);
    void onChange(ConnectionStatus Function() next) {
      if (identical(_socket, socket)) _setStatus(next());
    }

    socket
      ..onConnect((_) => onChange(() => ConnectionStatus.connected))
      // An inactive socket won't retry: the server disconnected it.
      ..onDisconnect(
        (_) => onChange(
          () => socket.active
              ? ConnectionStatus.reconnecting
              : ConnectionStatus.offline,
        ),
      )
      ..onConnectError((data) => _onConnectError(socket, generation, data))
      ..on('sessionRevoked', (_) => _onSessionRevoked(socket))
      ..connect();
  }

  /// The Session was revoked from elsewhere (or this Device's own logout
  /// reaching the server first): #20's sign-out path, directly — no refresh
  /// attempt, and no reconnect, since the server's disconnect that follows
  /// this event is server-initiated and the library won't retry it (ADR
  /// 0005).
  void _onSessionRevoked(io.Socket socket) {
    if (!identical(_socket, socket)) return;
    disconnect();
    unawaited(_endSession());
  }

  /// Forgets the Session (the Device ID stays) and tells the app, which
  /// sends the user to login.
  Future<void> _endSession() async {
    await _tokenStore.clearSession();
    _onSessionEnded();
  }

  /// Supplies the handshake's auth payload for every (re)connect attempt
  /// this socket makes, including the automatic ones after a dropped
  /// transport that never go through [connect].
  Future<void> _authenticate(int generation, dynamic callback) async {
    await _ensureFreshToken();
    if (generation != _generation) return;
    callback({
      'token': await _tokenStore.readAccessToken(),
      'since': await _readSyncCursor(),
    });
  }

  /// A handshake rejected because the token had already expired: refresh
  /// once and retry once, rather than treating it like any other refusal.
  void _onConnectError(io.Socket socket, int generation, dynamic data) {
    if (!identical(_socket, socket)) return;
    if (data == 'unauthenticated' && _authRetryGeneration != generation) {
      _authRetryGeneration = generation;
      unawaited(_retryAfterUnauthenticated(socket, generation));
      return;
    }
    _setStatus(
      // Inactive after a connect_error means the server refused the
      // handshake; active means it couldn't be reached and will be retried.
      !socket.active
          ? ConnectionStatus.offline
          : _status == ConnectionStatus.connecting
          ? ConnectionStatus.connecting
          : ConnectionStatus.reconnecting,
    );
  }

  Future<void> _retryAfterUnauthenticated(
    io.Socket socket,
    int generation,
  ) async {
    final refreshed = await _sessionRefresher.refresh();
    if (generation != _generation || !identical(_socket, socket)) return;
    if (!refreshed) {
      _setStatus(ConnectionStatus.offline);
      return;
    }
    socket.connect();
  }

  /// Refreshes the stored access token first if it's expired or close to it,
  /// reusing the single-flight refresh the Dio auth interceptor also uses
  /// (ADR 0005). False when the Session turned out to be dead.
  Future<bool> _ensureFreshToken() async {
    final token = await _tokenStore.readAccessToken();
    if (token == null || !_needsRefresh(token)) return true;
    return _sessionRefresher.refresh();
  }

  /// True only when the token's own `exp` claim says so. A token that can't
  /// be read this way (never expected in practice) is left to the reactive
  /// fallback instead of guessed at here.
  bool _needsRefresh(String token) {
    final expiry = jwtExpiry(token);
    return expiry != null &&
        expiry.isBefore(DateTime.now().toUtc().add(_refreshSkew));
  }

  /// Closes the connection, if any, and stops any retrying.
  void disconnect() {
    _generation++;
    _socket?.dispose();
    _socket = null;
    _setStatus(ConnectionStatus.offline);
  }

  /// Connects or disconnects as sign-in state changes. Call with `true` on
  /// sign-in and `false` on sign-out; this is what backgrounding while
  /// signed out avoids trying to connect for.
  void setAuthenticated(bool authenticated) {
    _authenticated = authenticated;
    if (authenticated) {
      unawaited(connect());
    } else {
      disconnect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_authenticated) return;
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(connect());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        disconnect();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
    _statusChanges.close();
  }

  void _setStatus(ConnectionStatus status) {
    if (status == _status) return;
    _status = status;
    _statusChanges.add(status);
  }
}

/// Connected while signed in, and disconnected and disposed on sign-out.
@Riverpod(keepAlive: true)
ConnectionManager connectionManager(Ref ref) {
  final manager = ConnectionManager(
    createSocket: ref.watch(socketFactoryProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    sessionRefresher: ref.watch(sessionRefresherProvider),
    // Read when it happens, not now: auth state itself depends on Dio.
    onSessionEnded: () => ref.read(authStateProvider.notifier).sessionEnded(),
    // Both read lazily (#51's sync engine also depends on Dio, transitively
    // on this provider's own dependents), same trick as onSessionEnded above.
    readSyncCursor: () => ref.read(syncEngineProvider).readCursor(),
    onSocketCreated: (socket) => ref.read(syncEngineProvider).attach(socket),
  );
  ref.onDispose(manager.dispose);
  ref.listen(authStateProvider, (_, auth) {
    switch (auth) {
      case Authenticated():
        manager.setAuthenticated(true);
      case Unauthenticated():
        manager.setAuthenticated(false);
      case Restoring():
        break;
    }
  }, fireImmediately: true);
  return manager;
}

/// The current status, then every change, for widgets like the "Connecting…"
/// banner to watch.
@Riverpod(keepAlive: true)
Stream<ConnectionStatus> connectionStatus(Ref ref) =>
    ref.watch(connectionManagerProvider).statusStream;
