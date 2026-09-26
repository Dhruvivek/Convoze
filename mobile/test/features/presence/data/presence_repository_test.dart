import 'package:convoze/features/presence/data/presence_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

io.Socket _fakeSocket() =>
    io.Socket(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

void main() {
  late PresenceRepository repository;
  late io.Socket socket;

  setUp(() {
    repository = PresenceRepository();
    socket = _fakeSocket();
    repository.attach(socket);
  });

  test('starts with nothing known', () {
    expect(repository.current, isEmpty);
  });

  test('a snapshot replaces all previously held state', () {
    socket.emitReserved('presenceSnapshot', {
      'users': [
        {'userId': 'u1', 'online': true, 'lastSeenAt': null},
        {'userId': 'u2', 'online': false, 'lastSeenAt': '2026-01-01T00:00:00.000Z'},
      ],
    });

    expect(repository.current['u1']!.online, isTrue);
    expect(repository.current['u1']!.lastSeenAt, isNull);
    expect(repository.current['u2']!.online, isFalse);
    expect(repository.current['u2']!.lastSeenAt, DateTime.parse('2026-01-01T00:00:00.000Z'));

    socket.emitReserved('presenceSnapshot', {
      'users': [
        {'userId': 'u3', 'online': true, 'lastSeenAt': null},
      ],
    });

    expect(repository.current.keys, ['u3']);
  });

  test('userOnline marks that User online, with no lastSeenAt', () {
    socket.emitReserved('userOffline', {
      'userId': 'u1',
      'lastSeenAt': '2026-01-01T00:00:00.000Z',
    });

    socket.emitReserved('userOnline', {'userId': 'u1'});

    expect(repository.current['u1']!.online, isTrue);
    expect(repository.current['u1']!.lastSeenAt, isNull);
  });

  test('userOffline marks that User offline with the given lastSeenAt', () {
    socket.emitReserved('userOffline', {
      'userId': 'u1',
      'lastSeenAt': '2026-01-02T03:04:05.000Z',
    });

    expect(repository.current['u1']!.online, isFalse);
    expect(repository.current['u1']!.lastSeenAt, DateTime.parse('2026-01-02T03:04:05.000Z'));
  });

  test('changes emits current, then every subsequent update', () async {
    final events = <Map<String, RawPresence>>[];
    final sub = repository.changes.listen(events.add);
    await Future<void>.delayed(Duration.zero);

    socket.emitReserved('userOnline', {'userId': 'u1'});
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events.first, isEmpty);
    expect(events.last['u1']!.online, isTrue);
    await sub.cancel();
  });
}
