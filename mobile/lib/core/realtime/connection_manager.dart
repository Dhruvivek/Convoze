import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../features/auth/presentation/auth_state.dart';
import '../storage/token_store.dart';
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
  ConnectionManager({required this._createSocket, required this._tokenStore}) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SocketFactory _createSocket;
  final TokenStore _tokenStore;
  final _statusChanges = StreamController<ConnectionStatus>.broadcast();

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
    final accessToken = await _tokenStore.readAccessToken();
    if (generation != _generation) return;

    // A socket the server refused is dead; don't leave it lying around.
    _socket?.dispose();
    // In the handshake's auth payload, never the URL: URLs end up in logs.
    final socket = _createSocket()..auth = {'token': accessToken};
    _socket = socket;
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
      // Inactive after a connect_error means the server refused the
      // handshake; active means it couldn't be reached and will be retried.
      ..onConnectError(
        (_) => onChange(
          () => !socket.active
              ? ConnectionStatus.offline
              : _status == ConnectionStatus.connecting
              ? ConnectionStatus.connecting
              : ConnectionStatus.reconnecting,
        ),
      )
      ..connect();
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
