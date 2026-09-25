import 'dart:async';

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
class ConnectionManager {
  ConnectionManager({required this._createSocket, required this._tokenStore});

  final SocketFactory _createSocket;
  final TokenStore _tokenStore;
  final _statusChanges = StreamController<ConnectionStatus>.broadcast();

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

  void dispose() {
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
        unawaited(manager.connect());
      case Unauthenticated():
        manager.disconnect();
      case Restoring():
        break;
    }
  }, fireImmediately: true);
  return manager;
}
