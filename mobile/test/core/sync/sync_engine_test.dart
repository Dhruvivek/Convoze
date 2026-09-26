import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/core/sync/sync_engine.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_ack_socket.dart';

const me = 'user-me';
const other = 'user-other';

Map<String, dynamic> messagePayload({
  required String id,
  required String conversationId,
  required String senderId,
  String content = 'hi',
  String? clientMsgId,
  bool isDeleted = false,
}) => {
  'id': id,
  'conversationId': conversationId,
  'senderId': senderId,
  'clientMsgId': clientMsgId,
  'replyToMessageId': null,
  'linkPreview': null,
  'type': 'text',
  'content': content,
  'createdAt': '2026-01-01T00:00:00.000Z',
  'editedAt': null,
  'isDeleted': isDeleted,
};

Map<String, dynamic> update({
  required int seq,
  required String kind,
  required Map<String, dynamic> payload,
}) => {
  'id': 'update-$seq',
  'userId': me,
  'seq': seq,
  'kind': kind,
  'createdAt': null,
  'payload': payload,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SyncEngine engine;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'user': '{"id":"$me","phoneNumber":"+14155550100","displayName":"Me"}',
    });
    db = AppDatabase(NativeDatabase.memory());
    engine = SyncEngine(db: db, dio: Dio(), tokenStore: TokenStore(const FlutterSecureStorage()));
    await db
        .into(db.conversations)
        .insert(ConversationsCompanion.insert(id: 'conv-1', type: 'direct'));
  });

  tearDown(() => db.close());

  test('applies a message.new from someone else and increments unreadCount', () async {
    final ackedSeq = await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-1', conversationId: 'conv-1', senderId: other),
        ),
      ],
    });

    expect(ackedSeq, 1);
    final message = await (db.select(db.messages)..where((t) => t.id.equals('msg-1'))).getSingle();
    expect(message.content, 'hi');
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.unreadCount, 1);
    expect(await db.readCursor(), 1);
  });

  test('a message.new from me does not increment unreadCount', () async {
    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-1', conversationId: 'conv-1', senderId: me),
        ),
      ],
    });

    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.unreadCount, 0);
  });

  test('a message.new whose clientMsgId matches an Outbox row clears it', () async {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientMsgId: 'client-1',
            conversationId: 'conv-1',
            content: 'hi',
            createdAt: DateTime.now(),
          ),
        );

    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'message.new',
          payload: messagePayload(
            id: 'msg-1',
            conversationId: 'conv-1',
            senderId: me,
            clientMsgId: 'client-1',
          ),
        ),
      ],
    });

    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('skips updates at or below the stored cursor (replay dedupe)', () async {
    await db.writeCursor(5);

    final ackedSeq = await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 5,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-old', conversationId: 'conv-1', senderId: other),
        ),
        update(
          seq: 6,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-new', conversationId: 'conv-1', senderId: other),
        ),
      ],
    });

    expect(ackedSeq, 6);
    final oldMessage = await (db.select(
      db.messages,
    )..where((t) => t.id.equals('msg-old'))).getSingleOrNull();
    expect(oldMessage, isNull);
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.unreadCount, 1);
  });

  test('message.deleted tombstones an existing message, clearing content', () async {
    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-1', conversationId: 'conv-1', senderId: other),
        ),
      ],
    });

    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 2,
          kind: 'message.deleted',
          payload: {'id': 'msg-1', 'conversationId': 'conv-1', 'isDeleted': true},
        ),
      ],
    });

    final message = await (db.select(db.messages)..where((t) => t.id.equals('msg-1'))).getSingle();
    expect(message.isDeleted, isTrue);
    expect(message.content, isNull);
  });

  test('reaction.changed updates a message\'s reactions', () async {
    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-1', conversationId: 'conv-1', senderId: other),
        ),
      ],
    });

    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 2,
          kind: 'reaction.changed',
          payload: {
            'messageId': 'msg-1',
            'conversationId': 'conv-1',
            'reactions': [
              {'userId': me, 'emoji': '👍'},
            ],
          },
        ),
      ],
    });

    final message = await (db.select(db.messages)..where((t) => t.id.equals('msg-1'))).getSingle();
    expect(message.reactions, '[{"userId":"$me","emoji":"👍"}]');
  });

  test('conversation.receipts sets watermarks and the absolute unreadCount', () async {
    await db
        .into(db.participants)
        .insert(ParticipantsCompanion.insert(conversationId: 'conv-1', userId: me));
    await db
        .into(db.conversations)
        .insertOnConflictUpdate(
          ConversationsCompanion.insert(id: 'conv-1', type: 'direct', unreadCount: Value(9)),
        );

    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'conversation.receipts',
          payload: {
            'conversationId': 'conv-1',
            'participants': [
              {'userId': me, 'lastReadMessageId': 'msg-5', 'lastDeliveredMessageId': 'msg-5'},
            ],
            'unreadCount': 0,
          },
        ),
      ],
    });

    final participant = await (db.select(
      db.participants,
    )..where((t) => t.conversationId.equals('conv-1') & t.userId.equals(me))).getSingle();
    expect(participant.lastReadMessageId, 'msg-5');
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.unreadCount, 0);
  });

  test('conversation.joined creates a direct Conversation and both Participants', () async {
    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'conversation.joined',
          payload: {
            'id': 'conv-2',
            'type': 'direct',
            'name': null,
            'directKey': '$me:$other',
            'createdById': other,
            'createdAt': '2026-01-01T00:00:00.000Z',
          },
        ),
      ],
    });

    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-2'))).getSingle();
    expect(conversation.unreadCount, 0);
    final participants = await (db.select(
      db.participants,
    )..where((t) => t.conversationId.equals('conv-2'))).get();
    expect(participants.map((p) => p.userId).toSet(), {me, other});
  });

  test('conversation.prefs upserts the preference fields', () async {
    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'conversation.prefs',
          payload: {
            'id': 'conv-1',
            'pinnedAt': '2026-01-02T00:00:00.000Z',
            'archivedAt': null,
            'mutedUntil': '2026-01-03T00:00:00.000Z',
            'hiddenAt': null,
            'historyClearedMessageId': null,
            'unreadCount': 3,
          },
        ),
      ],
    });

    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(
      conversation.pinnedAt!.isAtSameMomentAs(DateTime.parse('2026-01-02T00:00:00.000Z')),
      isTrue,
    );
    expect(
      conversation.mutedUntil!.isAtSameMomentAs(DateTime.parse('2026-01-03T00:00:00.000Z')),
      isTrue,
    );
    expect(conversation.archivedAt, isNull);
    expect(conversation.unreadCount, 3);
  });

  test('conversation.prefs deletes local messages at or before the cleared watermark', () async {
    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 1,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-1', conversationId: 'conv-1', senderId: other),
        ),
        update(
          seq: 2,
          kind: 'message.new',
          payload: messagePayload(id: 'msg-2', conversationId: 'conv-1', senderId: other),
        ),
      ],
    });

    await engine.applyBatch({
      'users': [],
      'updates': [
        update(
          seq: 3,
          kind: 'conversation.prefs',
          payload: {
            'id': 'conv-1',
            'pinnedAt': null,
            'archivedAt': null,
            'mutedUntil': null,
            'hiddenAt': null,
            'historyClearedMessageId': 'msg-1',
          },
        ),
      ],
    });

    final remaining = await (db.select(
      db.messages,
    )..where((t) => t.conversationId.equals('conv-1'))).get();
    expect(remaining.map((m) => m.id), ['msg-2']);
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.historyClearedMessageId, 'msg-1');
  });

  test('the Outbox drainer sends a queued message and removes it on success', () async {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientMsgId: 'client-1',
            conversationId: 'conv-1',
            content: 'hi',
            createdAt: DateTime.now(),
          ),
        );
    final socket = FakeAckSocket({'ok': true, 'messageId': 'msg-1'});

    await engine.drainOutbox(socket);

    expect(socket.sentEvents, ['message:send']);
    expect(await db.select(db.outbox).get(), isEmpty);
  });

  test('the Outbox drainer marks a non-retryable failure as failed', () async {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientMsgId: 'client-1',
            conversationId: 'conv-1',
            content: 'hi',
            createdAt: DateTime.now(),
          ),
        );
    final socket = FakeAckSocket({'ok': false, 'code': 'NOT_PARTICIPANT'});

    await engine.drainOutbox(socket);

    final row = await db.select(db.outbox).getSingle();
    expect(row.status, 'failed');
  });
}
