import 'dart:async';
import 'dart:convert';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/core/sync/sync_engine.dart';
import 'package:convoze/features/conversations/data/media_repository.dart';
import 'package:convoze/features/conversations/data/message_action_failure.dart';
import 'package:convoze/features/conversations/data/messages_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../support/fake_ack_socket.dart';

/// Answers `GET /conversations/:id/messages` with a canned page, recording
/// the query parameters it was called with.
class _FakeHistoryBackend implements HttpClientAdapter {
  Map<String, dynamic> nextResponse = {
    'messages': <dynamic>[],
    'nextBefore': null,
    'users': <dynamic>[],
  };
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.queryParameters);
    return ResponseBody.fromString(
      jsonEncode(nextResponse),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const me = 'user-me';
const other = 'user-other';

Map<String, dynamic> wireMessage({
  required String id,
  required String senderId,
  String content = 'hi',
  String createdAt = '2026-01-01T00:00:00.000Z',
}) => {
  'id': id,
  'conversationId': 'conv-1',
  'senderId': senderId,
  'clientMsgId': null,
  'replyToMessageId': null,
  'linkPreview': null,
  'type': 'text',
  'content': content,
  'createdAt': createdAt,
  'editedAt': null,
  'isDeleted': false,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Dio dio;
  late _FakeHistoryBackend backend;
  late SyncEngine engine;
  late MessagesRepository repo;

  MessagesRepository repoWithSocket(io.Socket? Function() currentSocket) => MessagesRepository(
    db: db,
    dio: dio,
    tokenStore: TokenStore(const FlutterSecureStorage()),
    syncEngine: engine,
    currentSocket: currentSocket,
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'user': '{"id":"$me","phoneNumber":"+14155550100","displayName":"Me"}',
    });
    db = AppDatabase(NativeDatabase.memory());
    backend = _FakeHistoryBackend();
    dio = Dio(BaseOptions(baseUrl: 'http://fake'))
      ..httpClientAdapter = backend;
    final tokenStore = TokenStore(const FlutterSecureStorage());
    engine = SyncEngine(db: db, dio: dio, tokenStore: tokenStore);
    repo = repoWithSocket(() => null);
    await db
        .into(db.conversations)
        .insert(ConversationsCompanion.insert(id: 'conv-1', type: 'direct', unreadCount: const Value(3)));
  });

  tearDown(() => db.close());

  group('send', () {
    test('queues an Outbox row and leaves it queued while offline', () async {
      await repo.send('conv-1', '  hello  ');

      final row = await db.select(db.outbox).getSingle();
      expect(row.content, 'hello');
      expect(row.conversationId, 'conv-1');
      expect(row.status, 'pending');
    });

    test('does nothing for blank text', () async {
      await repo.send('conv-1', '   ');
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('carries replyToMessageId and linkPreview through to the Outbox row', () async {
      await repo.send(
        'conv-1',
        'check this out',
        replyToMessageId: 'm-quoted',
        linkPreview: {'url': 'https://example.com', 'title': 'Example'},
      );

      final row = await db.select(db.outbox).getSingle();
      expect(row.replyToMessageId, 'm-quoted');
      expect(
        jsonDecode(row.linkPreview!),
        {'url': 'https://example.com', 'title': 'Example'},
      );
    });

    test('kicks an immediate drain when a socket is live', () async {
      final socket = FakeAckSocket({'ok': true, 'messageId': 'm1'});
      final onlineRepo = repoWithSocket(() => socket);

      await onlineRepo.send('conv-1', 'hello');
      await pumpEventQueue();

      expect(socket.sentEvents, ['message:send']);
      expect(await db.select(db.outbox).get(), isEmpty);
    });
  });

  group('sendMedia', () {
    test('inserts an Outbox row carrying the encoded upload reference', () async {
      const upload = CloudinaryUploadResult(
        publicId: 'u/me-1/abc',
        version: '123',
        signature: 'sig',
        resourceType: 'image',
        bytes: 2048,
        format: 'jpg',
        width: 800,
        height: 600,
      );

      await repo.sendMedia(
        'conv-1',
        kind: MediaKind.image,
        upload: upload,
        caption: 'nice view',
      );

      final row = await db.select(db.outbox).getSingle();
      expect(row.type, 'image');
      expect(row.content, 'nice view');
      final media = jsonDecode(row.media!) as Map<String, dynamic>;
      expect(media['publicId'], 'u/me-1/abc');
      expect(media['resourceType'], 'image');
      expect(media['width'], 800);
    });

    test('a file message carries its file name', () async {
      const upload = CloudinaryUploadResult(
        publicId: 'u/me-1/doc',
        version: '1',
        signature: 'sig',
        resourceType: 'raw',
        bytes: 4096,
        format: 'pdf',
      );

      await repo.sendMedia(
        'conv-1',
        kind: MediaKind.file,
        upload: upload,
        fileName: 'invoice.pdf',
      );

      final row = await db.select(db.outbox).getSingle();
      final media = jsonDecode(row.media!) as Map<String, dynamic>;
      expect(media['fileName'], 'invoice.pdf');
    });

    test('kicks an immediate drain when a socket is live', () async {
      const upload = CloudinaryUploadResult(
        publicId: 'u/me-1/abc',
        version: '123',
        signature: 'sig',
        resourceType: 'image',
        bytes: 2048,
        format: 'jpg',
      );
      final socket = FakeAckSocket({'ok': true, 'messageId': 'm1'});
      final onlineRepo = repoWithSocket(() => socket);

      await onlineRepo.sendMedia('conv-1', kind: MediaKind.image, upload: upload);
      await pumpEventQueue();

      expect(socket.sentEvents, ['message:send']);
      expect(await db.select(db.outbox).get(), isEmpty);
    });
  });

  group('editMessage', () {
    test('sends the trimmed content over message:edit', () async {
      final socket = FakeAckSocket({'ok': true});
      final onlineRepo = repoWithSocket(() => socket);

      await onlineRepo.editMessage('msg-1', '  hi  ');

      expect(socket.sentEvents, ['message:edit']);
      expect(socket.sentPayloads.single, {'messageId': 'msg-1', 'content': 'hi'});
    });

    test('throws the failure the ack names when it refuses', () async {
      final socket = FakeAckSocket({'ok': false, 'code': 'FORBIDDEN'});
      final onlineRepo = repoWithSocket(() => socket);

      expect(
        () => onlineRepo.editMessage('msg-1', 'hi'),
        throwsA(isA<MessageActionForbidden>()),
      );
    });

    test('throws MessageActionNetworkFailure when the ack never lands', () async {
      final socket = TimingOutSocket();
      final onlineRepo = repoWithSocket(() => socket);

      expect(
        () => onlineRepo.editMessage('msg-1', 'hi'),
        throwsA(isA<MessageActionNetworkFailure>()),
      );
    });

    test('throws MessageActionNetworkFailure with no live socket', () async {
      expect(
        () => repo.editMessage('msg-1', 'hi'),
        throwsA(isA<MessageActionNetworkFailure>()),
      );
    });
  });

  group('deleteMessage', () {
    test('sends the messageId over message:delete', () async {
      final socket = FakeAckSocket({'ok': true});
      final onlineRepo = repoWithSocket(() => socket);

      await onlineRepo.deleteMessage('msg-1');

      expect(socket.sentEvents, ['message:delete']);
      expect(socket.sentPayloads.single, {'messageId': 'msg-1'});
    });

    test('throws the failure the ack names when it refuses', () async {
      final socket = FakeAckSocket({'ok': false, 'code': 'NOT_FOUND'});
      final onlineRepo = repoWithSocket(() => socket);

      expect(
        () => onlineRepo.deleteMessage('msg-1'),
        throwsA(isA<MessageActionNotFound>()),
      );
    });
  });

  group('retry', () {
    test('puts a failed row back to pending', () async {
      await db.into(db.outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c1',
          conversationId: 'conv-1',
          content: 'hi',
          status: const Value('failed'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      await repo.retry('c1');

      final row = await db.select(db.outbox).getSingle();
      expect(row.status, 'pending');
    });

    test('kicks an immediate drain when a socket is live', () async {
      await db.into(db.outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c1',
          conversationId: 'conv-1',
          content: 'hi',
          status: const Value('failed'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final socket = FakeAckSocket({'ok': true, 'messageId': 'm1', 'createdAt': '2026-01-01T00:00:00.000Z'});
      final onlineRepo = repoWithSocket(() => socket);

      await onlineRepo.retry('c1');
      await pumpEventQueue();

      expect(socket.sentEvents, ['message:send']);
      expect(await db.select(db.outbox).get(), isEmpty);
    });

    test('is a no-op once the row is already gone', () async {
      await repo.retry('does-not-exist');
      expect(await db.select(db.outbox).get(), isEmpty);
    });
  });

  group('discard', () {
    test('deletes the Outbox row', () async {
      await db.into(db.outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c1',
          conversationId: 'conv-1',
          content: 'hi',
          status: const Value('failed'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );

      await repo.discard('c1');

      expect(await db.select(db.outbox).get(), isEmpty);
    });
  });

  group('markRead', () {
    test('does nothing without any local messages', () async {
      await repo.markRead('conv-1');
      expect(await db.select(db.pendingReads).get(), isEmpty);
    });

    test('moves my watermark, zeroes unread, and queues a pending read', () async {
      await db.into(db.messages).insert(
        MessagesCompanion.insert(
          id: 'm1',
          conversationId: 'conv-1',
          senderId: other,
          type: const Value('text'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await db.into(db.participants).insert(
        ParticipantsCompanion.insert(conversationId: 'conv-1', userId: me),
      );

      await repo.markRead('conv-1');

      final participant = await (db.select(db.participants)
            ..where((t) => t.conversationId.equals('conv-1') & t.userId.equals(me)))
          .getSingle();
      expect(participant.lastReadMessageId, 'm1');
      expect(participant.lastDeliveredMessageId, 'm1');

      final conversation = await (db.select(db.conversations)..where((t) => t.id.equals('conv-1')))
          .getSingle();
      expect(conversation.unreadCount, 0);

      final pending = await db.select(db.pendingReads).getSingle();
      expect(pending.conversationId, 'conv-1');
      expect(pending.messageId, 'm1');
    });

    test('is a no-op once already caught up to the latest message', () async {
      await db.into(db.messages).insert(
        MessagesCompanion.insert(
          id: 'm1',
          conversationId: 'conv-1',
          senderId: other,
          type: const Value('text'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await db.into(db.participants).insert(
        ParticipantsCompanion.insert(
          conversationId: 'conv-1',
          userId: me,
          lastReadMessageId: const Value('m1'),
        ),
      );

      await repo.markRead('conv-1');

      expect(await db.select(db.pendingReads).get(), isEmpty);
    });

    test('kicks an immediate flush when a socket is live', () async {
      await db.into(db.messages).insert(
        MessagesCompanion.insert(
          id: 'm1',
          conversationId: 'conv-1',
          senderId: other,
          type: const Value('text'),
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await db.into(db.participants).insert(
        ParticipantsCompanion.insert(conversationId: 'conv-1', userId: me),
      );
      final socket = FakeAckSocket({'ok': true});
      final onlineRepo = repoWithSocket(() => socket);

      await onlineRepo.markRead('conv-1');
      await pumpEventQueue();

      expect(socket.sentEvents, ['conversation:read']);
      expect(await db.select(db.pendingReads).get(), isEmpty);
    });
  });

  group('loadOlder', () {
    test('fetches the first page with no `before` when nothing is local', () async {
      backend.nextResponse = {
        'messages': [wireMessage(id: 'm2', senderId: other), wireMessage(id: 'm1', senderId: other)],
        'nextBefore': null,
        'users': [
          {'id': other, 'phoneNumber': '+14155550101', 'displayName': null, 'avatarUrl': null},
        ],
      };

      final result = await repo.loadOlder('conv-1');

      expect(backend.requests.single.containsKey('before'), isFalse);
      expect(result.fetchedCount, 2);
      expect(result.reachedStart, isTrue);
      final stored = await db.select(db.messages).get();
      expect(stored.map((m) => m.id).toSet(), {'m1', 'm2'});
      final users = await db.select(db.users).get();
      expect(users.single.id, other);
    });

    test('pages `before` the oldest local message and reports reachedStart from nextBefore', () async {
      await db.into(db.messages).insert(
        MessagesCompanion.insert(
          id: 'm5',
          conversationId: 'conv-1',
          senderId: other,
          type: const Value('text'),
          createdAt: DateTime.utc(2026, 1, 5),
        ),
      );
      backend.nextResponse = {
        'messages': [wireMessage(id: 'm4', senderId: other)],
        'nextBefore': 'm4',
        'users': <dynamic>[],
      };

      final result = await repo.loadOlder('conv-1');

      expect(backend.requests.single['before'], 'm5');
      expect(result.reachedStart, isFalse);
    });
  });
}
