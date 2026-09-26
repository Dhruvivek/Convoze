import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/conversations/data/typing_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

const me = 'user-me';
const other = 'user-other';
const conversationId = 'conv-1';

/// Records every outgoing `emit` (as `(event, conversationId)`, since the
/// full payload Map is otherwise identity-, not value-, compared) instead of
/// touching the network.
class _RecordingSocket extends io.Socket {
  _RecordingSocket()
    : super(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

  final sent = <(String, String)>[];

  @override
  void emit(String event, [dynamic data]) {
    final payload = (data as Map).cast<String, dynamic>();
    sent.add((event, payload['conversationId'] as String));
  }
}

/// `_handleTyping`/`_handleStopTyping` read the stored User asynchronously
/// before mutating state, so a receiving test needs one microtask turn
/// after emitting before checking [TypingRepository.current].
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late TypingRepository repository;
  late _RecordingSocket socket;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'user': '{"id":"$me","phoneNumber":"+14155550100","displayName":"Me"}',
    });
    repository = TypingRepository(
      tokenStore: TokenStore(const FlutterSecureStorage()),
      sendThrottle: const Duration(milliseconds: 60),
      idleTimeout: const Duration(milliseconds: 100),
      receiverTimeout: const Duration(milliseconds: 120),
    );
    socket = _RecordingSocket();
    repository.attach(socket);
  });

  group('sending', () {
    test('a non-empty change sends typing', () {
      repository.composerChanged(conversationId, 'h');

      expect(socket.sent, [('typing', conversationId)]);
    });

    test('further changes within the throttle window send nothing more', () {
      repository.composerChanged(conversationId, 'h');
      repository.composerChanged(conversationId, 'he');
      repository.composerChanged(conversationId, 'hel');

      expect(socket.sent.where((e) => e.$1 == 'typing'), hasLength(1));
    });

    test('a change after the throttle window sends typing again', () async {
      repository.composerChanged(conversationId, 'h');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      repository.composerChanged(conversationId, 'he');

      expect(socket.sent.where((e) => e.$1 == 'typing'), hasLength(2));
    });

    test('an emptied composer sends stopTyping instead of typing', () {
      repository.composerChanged(conversationId, 'h');
      repository.composerChanged(conversationId, '');

      expect(socket.sent.last, ('stopTyping', conversationId));
    });

    test('going idle sends stopTyping on its own', () async {
      repository.composerChanged(conversationId, 'h');

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(socket.sent.last, ('stopTyping', conversationId));
    });

    test('stopTyping() sends it directly (send/leaving-the-chat path)', () {
      repository.composerChanged(conversationId, 'h');
      repository.stopTyping(conversationId);

      expect(socket.sent.last, ('stopTyping', conversationId));
    });

    test("stopTyping() cancels the idle timer, so it doesn't fire again later", () async {
      repository.composerChanged(conversationId, 'h');
      repository.stopTyping(conversationId);
      final countAfterStop = socket.sent.length;

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(socket.sent, hasLength(countAfterStop));
    });
  });

  group('receiving', () {
    test('another User typing appears as a current typer', () async {
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();

      expect(repository.current[conversationId], {other});
    });

    test('our own userId is ignored, even from a second Device', () async {
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': me});
      await settle();

      expect(repository.current[conversationId], isNull);
    });

    test('stopTyping removes that typer at once', () async {
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();
      socket.emitReserved('stopTyping', {'conversationId': conversationId, 'userId': other});
      await settle();

      expect(repository.current[conversationId], isNull);
    });

    test('a typer expires on their own after receiverTimeout', () async {
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();
      expect(repository.current[conversationId], {other});

      await Future<void>.delayed(const Duration(milliseconds: 170));

      expect(repository.current[conversationId], isNull);
    });

    test('a fresh typing event before expiry keeps them listed', () async {
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(repository.current[conversationId], {other});
    });

    test('userOffline removes them from every Conversation', () async {
      socket.emitReserved('typing', {'conversationId': 'conv-1', 'userId': other});
      socket.emitReserved('typing', {'conversationId': 'conv-2', 'userId': other});
      await settle();

      socket.emitReserved('userOffline', {'userId': other, 'lastSeenAt': null});

      expect(repository.current, isEmpty);
    });

    test('changes emits current, then every subsequent update', () async {
      final events = <Map<String, Set<String>>>[];
      final sub = repository.changes.listen(events.add);
      await settle();

      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();

      expect(events, hasLength(2));
      expect(events.first, isEmpty);
      expect(events.last[conversationId], {other});
      await sub.cancel();
    });
  });

  group('clearAll', () {
    test('drops every typer in every Conversation, with no stopTyping sent', () async {
      socket.emitReserved('typing', {'conversationId': 'conv-1', 'userId': other});
      socket.emitReserved('typing', {'conversationId': 'conv-2', 'userId': other});
      await settle();
      final sentBefore = socket.sent.length;

      repository.clearAll();

      expect(repository.current, isEmpty);
      expect(socket.sent, hasLength(sentBefore));
    });

    test('a since-cleared typer does not resurface when its old timer fires', () async {
      socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
      await settle();

      repository.clearAll();
      await Future<void>.delayed(const Duration(milliseconds: 170));

      expect(repository.current, isEmpty);
    });
  });
}
