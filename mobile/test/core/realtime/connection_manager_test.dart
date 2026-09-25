import 'package:convoze/core/network/session_refresher.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

import '../../support/fake_backend.dart';
import '../../support/fake_jwt.dart';

/// A [io.Socket] double that does no real IO: [connect] is a no-op and the
/// test drives `connect`/`disconnect`/`connect_error` by hand via
/// [emitReserved], with [active] set directly to stand in for whether the
/// real socket would keep retrying.
class _TestSocket extends io.Socket {
  _TestSocket(Manager manager) : super(manager, '/', const {});

  bool active_ = true;

  /// How many times [connect] has been called, so a test can tell a
  /// refresh-and-retry apart from giving up.
  int connectCalls = 0;

  @override
  bool get active => active_;

  @override
  io.Socket connect() {
    connectCalls++;
    return this;
  }

  @override
  io.Socket disconnect() {
    connected = false;
    return this;
  }

  @override
  void dispose() {
    connected = false;
    clearListeners();
  }
}

/// Lets scheduled microtasks (broadcast-stream event delivery) run.
Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_TestSocket> sockets;
  late FakeBackend backend;
  late TokenStore tokenStore;
  late int sessionEndedCalls;
  late ConnectionManager manager;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': fakeJwt(secondsFromNow: 3600),
      'refresh_token': 'refresh-1',
    });
    sockets = [];
    backend = FakeBackend();
    sessionEndedCalls = 0;
    tokenStore = TokenStore(const FlutterSecureStorage());
    manager = ConnectionManager(
      createSocket: () {
        final socket = _TestSocket(
          Manager(uri: 'http://fake', options: {'autoConnect': false}),
        );
        sockets.add(socket);
        return socket;
      },
      tokenStore: tokenStore,
      sessionRefresher: SessionRefresher(
        refreshDio: Dio()..httpClientAdapter = backend,
        tokenStore: tokenStore,
        onSessionEnded: () => sessionEndedCalls++,
      ),
      onSessionEnded: () => sessionEndedCalls++,
    );
  });

  tearDown(() => manager.dispose());

  test('connect goes offline -> connecting -> connected', () async {
    expect(manager.status, ConnectionStatus.offline);
    final connectFuture = manager.connect();
    expect(manager.status, ConnectionStatus.connecting);
    await connectFuture;

    sockets.single.emitReserved('connect');
    expect(manager.status, ConnectionStatus.connected);
  });

  test('statusStream reports the current status, then every change', () async {
    final statuses = <ConnectionStatus>[];
    final sub = manager.statusStream.listen(statuses.add);
    await _flush();
    expect(statuses, [ConnectionStatus.offline]);

    await manager.connect();
    sockets.single.emitReserved('connect');
    await _flush();

    expect(statuses, [
      ConnectionStatus.offline,
      ConnectionStatus.connecting,
      ConnectionStatus.connected,
    ]);
    await sub.cancel();
  });

  test('a dropped connection that keeps retrying reports reconnecting, then '
      'connected again once it recovers', () async {
    await manager.connect();
    final socket = sockets.single;
    socket.emitReserved('connect');
    expect(manager.status, ConnectionStatus.connected);

    socket.emitReserved('disconnect', 'transport close');
    expect(manager.status, ConnectionStatus.reconnecting);

    socket.emitReserved('connect');
    expect(manager.status, ConnectionStatus.connected);
  });

  test('a server-initiated disconnect (socket no longer active) goes '
      'straight to offline, not reconnecting', () async {
    await manager.connect();
    final socket = sockets.single;
    socket.emitReserved('connect');

    socket.active_ = false;
    socket.emitReserved('disconnect', 'io server disconnect');

    expect(manager.status, ConnectionStatus.offline);
  });

  test('a connect_error while still retrying reports reconnecting', () async {
    await manager.connect();
    final socket = sockets.single;
    socket.emitReserved('connect');
    socket.emitReserved('disconnect', 'transport close');

    socket.emitReserved('connect_error', 'timeout');

    expect(manager.status, ConnectionStatus.reconnecting);
  });

  test('a connect_error that exhausts retries goes offline', () async {
    await manager.connect();
    final socket = sockets.single;

    socket.active_ = false;
    socket.emitReserved('connect_error', 'refused');

    expect(manager.status, ConnectionStatus.offline);
  });

  test(
    'disconnect() closes the socket and stops reporting its events',
    () async {
      await manager.connect();
      final socket = sockets.single;
      socket.emitReserved('connect');

      manager.disconnect();
      expect(manager.status, ConnectionStatus.offline);

      // A late event from the now-superseded socket must not resurrect it.
      socket.emitReserved('connect');
      expect(manager.status, ConnectionStatus.offline);
    },
  );

  group('app lifecycle', () {
    test('paused, hidden and detached disconnect while authenticated', () {
      for (final state in [
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        manager.setAuthenticated(true);
        expect(manager.status, isNot(ConnectionStatus.offline));

        manager.didChangeAppLifecycleState(state);

        expect(manager.status, ConnectionStatus.offline);
        manager.setAuthenticated(false);
      }
    });

    test('resumed reconnects while authenticated', () {
      manager.setAuthenticated(true);
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(manager.status, ConnectionStatus.offline);

      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(manager.status, ConnectionStatus.connecting);
    });

    test('inactive is ignored', () {
      manager.setAuthenticated(true);
      final statusBefore = manager.status;

      manager.didChangeAppLifecycleState(AppLifecycleState.inactive);

      expect(manager.status, statusBefore);
    });

    test('lifecycle changes do nothing while signed out', () {
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(manager.status, ConnectionStatus.offline);

      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(manager.status, ConnectionStatus.offline);
    });
  });

  group('sessionRevoked (#33)', () {
    test(
      'clears the Session, tells the app, and does not reconnect or refresh',
      () async {
        await manager.connect();
        final socket = sockets.single;
        socket.emitReserved('connect');
        final connectCallsBefore = socket.connectCalls;

        socket.active_ = false;
        socket.emitReserved('sessionRevoked', {});
        await pumpEventQueue();

        expect(manager.status, ConnectionStatus.offline);
        expect(manager.socket, isNull);
        expect(await tokenStore.readAccessToken(), isNull);
        expect(await tokenStore.readRefreshToken(), isNull);
        expect(sessionEndedCalls, 1);
        expect(backend.refreshCalls, 0);
        // No reconnect attempt on this socket, and no new one opened.
        expect(socket.connectCalls, connectCallsBefore);
        expect(sockets, hasLength(1));
      },
    );

    test('keeps the Device ID', () async {
      FlutterSecureStorage.setMockInitialValues({
        'access_token': fakeJwt(secondsFromNow: 3600),
        'refresh_token': 'refresh-1',
        'device_id': 'device-1',
      });
      await manager.connect();
      final socket = sockets.single;
      socket.emitReserved('connect');

      socket.emitReserved('sessionRevoked', {});
      await pumpEventQueue();

      expect(await const FlutterSecureStorage().read(key: 'device_id'), 'device-1');
    });

    test('a late event from an already-superseded socket is ignored', () async {
      await manager.connect();
      final socket = sockets.single;
      socket.emitReserved('connect');
      manager.disconnect();

      socket.emitReserved('sessionRevoked', {});
      await pumpEventQueue();

      expect(sessionEndedCalls, 0);
    });
  });

  group('token freshness on connect (#32)', () {
    test('a token close to expiry is refreshed before connecting', () async {
      await tokenStore.saveTokens(
        accessToken: fakeJwt(secondsFromNow: 30),
        refreshToken: 'refresh-1',
      );

      await manager.connect();

      expect(backend.refreshCalls, 1);
      expect(await tokenStore.readAccessToken(), backend.accessToken);
      expect(sockets, hasLength(1));
    });

    test('an already-fresh token is not refreshed', () async {
      await manager.connect();

      expect(backend.refreshCalls, 0);
    });

    test(
      'a dead refresh token ends the Session instead of opening a socket',
      () async {
        await tokenStore.saveTokens(
          accessToken: fakeJwt(secondsFromNow: 30),
          refreshToken: 'refresh-1',
        );
        backend.refreshStatus = 401;

        await manager.connect();

        expect(manager.status, ConnectionStatus.offline);
        expect(sockets, isEmpty);
        expect(sessionEndedCalls, 1);
      },
    );

    test(
      'a handshake rejected as unauthenticated refreshes once and retries',
      () async {
        await manager.connect();
        final socket = sockets.single;
        socket.active_ = false;

        socket.emitReserved('connect_error', 'unauthenticated');
        await pumpEventQueue();

        expect(backend.refreshCalls, 1);
        expect(socket.connectCalls, 2);

        socket.emitReserved('connect');
        expect(manager.status, ConnectionStatus.connected);
      },
    );

    test(
      'a second unauthenticated rejection on the retry does not loop',
      () async {
        await manager.connect();
        final socket = sockets.single;
        socket.active_ = false;
        socket.emitReserved('connect_error', 'unauthenticated');
        await pumpEventQueue();
        expect(socket.connectCalls, 2);

        socket.active_ = false;
        socket.emitReserved('connect_error', 'unauthenticated');
        await pumpEventQueue();

        expect(backend.refreshCalls, 1);
        expect(socket.connectCalls, 2);
        expect(manager.status, ConnectionStatus.offline);
      },
    );

    test('an unauthenticated rejection with a dead refresh token ends the '
        'Session and stops retrying', () async {
      backend.refreshStatus = 401;
      await manager.connect();
      final socket = sockets.single;
      socket.active_ = false;

      socket.emitReserved('connect_error', 'unauthenticated');
      await pumpEventQueue();

      expect(backend.refreshCalls, 1);
      expect(socket.connectCalls, 1);
      expect(manager.status, ConnectionStatus.offline);
      expect(sessionEndedCalls, 1);
    });
  });
}
