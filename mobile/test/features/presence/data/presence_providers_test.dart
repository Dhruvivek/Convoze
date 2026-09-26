import 'dart:async';

import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/presence/data/presence_providers.dart';
import 'package:convoze/features/presence/data/presence_repository.dart';
import 'package:convoze/features/presence/data/presence_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

io.Socket _fakeSocket() =>
    io.Socket(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

void main() {
  late StreamController<ConnectionStatus> statusController;
  late PresenceRepository repository;
  late io.Socket socket;
  late ProviderContainer container;

  setUp(() {
    statusController = StreamController<ConnectionStatus>.broadcast();
    repository = PresenceRepository();
    socket = _fakeSocket();
    repository.attach(socket);
    container = ProviderContainer(
      overrides: [
        connectionStatusProvider.overrideWith((ref) => statusController.stream),
        presenceRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(statusController.close);
    // `statusController` is a broadcast stream: an event added before
    // anything has subscribed to `connectionStatusProvider` is lost. This
    // forces that subscription to exist from the start, same as the real
    // provider (backed by `ConnectionManager.statusStream`) always having a
    // listener once the app is running. `presenceMapProvider` needs the same
    // treatment for a different reason: a `StreamProvider` built for the
    // first time inside a bare `container.read` is still `AsyncLoading` —
    // its stream's first value only lands on a later microtask — so a test
    // that emits, then reads once, would otherwise race its own setup.
    container.listen(connectionStatusProvider, (_, _) {});
    container.listen(presenceMapProvider, (_, _) {});
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('unknown for a User nothing has been heard about', () async {
    statusController.add(ConnectionStatus.connected);
    await settle();

    expect(container.read(presenceProvider('u1')), isA<PresenceUnknown>());
  });

  test('online while connected and the server reports them online', () async {
    statusController.add(ConnectionStatus.connected);
    socket.emitReserved('userOnline', {'userId': 'u1'});
    await settle();

    expect(container.read(presenceProvider('u1')), isA<PresenceOnline>());
  });

  test('offline server-side always shows their lastSeenAt, connected or not', () async {
    statusController.add(ConnectionStatus.connected);
    socket.emitReserved('userOffline', {
      'userId': 'u1',
      'lastSeenAt': '2026-01-02T00:00:00.000Z',
    });
    await settle();

    final state = container.read(presenceProvider('u1')) as PresenceLastSeen;
    expect(state.time, DateTime.parse('2026-01-02T00:00:00.000Z'));
  });

  test(
    'downgrades online to lastSeen(moment our own connection dropped) while disconnected',
    () async {
      statusController.add(ConnectionStatus.connected);
      socket.emitReserved('userOnline', {'userId': 'u1'});
      await settle();

      statusController.add(ConnectionStatus.reconnecting);
      await settle();
      final droppedAt = DateTime.now();

      final state = container.read(presenceProvider('u1'));
      expect(state, isA<PresenceLastSeen>());
      expect(
        (state as PresenceLastSeen).time.difference(droppedAt).abs(),
        lessThan(const Duration(seconds: 2)),
      );
    },
  );

  test('the next snapshot restores the real state once reconnected', () async {
    statusController.add(ConnectionStatus.connected);
    socket.emitReserved('userOnline', {'userId': 'u1'});
    await settle();
    statusController.add(ConnectionStatus.reconnecting);
    await settle();
    expect(container.read(presenceProvider('u1')), isA<PresenceLastSeen>());

    statusController.add(ConnectionStatus.connected);
    await settle();
    socket.emitReserved('presenceSnapshot', {
      'users': [
        {'userId': 'u1', 'online': true, 'lastSeenAt': null},
      ],
    });
    await settle();

    expect(container.read(presenceProvider('u1')), isA<PresenceOnline>());
  });
}
