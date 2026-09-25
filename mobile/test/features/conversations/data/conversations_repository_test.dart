import 'dart:convert';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/features/conversations/data/conversations_failure.dart';
import 'package:convoze/features/conversations/data/conversations_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, or fails the connection.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter.respond(this._status, [this._body]) : _connectionFails = false;
  _StubAdapter.connectionFails()
    : _status = 0,
      _body = null,
      _connectionFails = true;

  final int _status;
  final Object? _body;
  final bool _connectionFails;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_connectionFails) {
      throw DioException.connectionError(requestOptions: options, reason: 'Connection refused');
    }
    return ResponseBody.fromString(
      _body == null ? '' : jsonEncode(_body),
      _status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> _error(String code) => {
  'error': {'code': code, 'message': 'irrelevant'},
};

const me = 'me-1';
const other = 'other-1';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ConversationsRepository repository(_StubAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    return ConversationsRepository(dio, db);
  }

  group('openDirect', () {
    test('upserts the conversation, its participants and users, and returns its id', () async {
      final id = await repository(
        _StubAdapter.respond(201, {
          'id': 'conv-1',
          'type': 'direct',
          'name': null,
          'createdAt': '2026-01-01T00:00:00.000Z',
          'participants': [
            {'userId': me, 'role': 'member'},
            {'userId': other, 'role': 'member'},
          ],
          'users': [
            {'id': me, 'displayName': 'Me', 'avatarUrl': null, 'phoneNumber': '+14155550100'},
            {'id': other, 'displayName': 'Other', 'avatarUrl': null, 'phoneNumber': '+14155550101'},
          ],
        }),
      ).openDirect(other);

      expect(id, 'conv-1');
      final conversation = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals('conv-1'))).getSingle();
      expect(conversation.type, 'direct');
      final participants = await (db.select(
        db.participants,
      )..where((t) => t.conversationId.equals('conv-1'))).get();
      expect(participants.map((p) => p.userId).toSet(), {me, other});
      final user = await (db.select(db.users)..where((t) => t.id.equals(other))).getSingle();
      expect(user.displayName, 'Other');
    });

    final cases = <String, (int, String, Matcher)>{
      'the target user does not exist': (404, 'not_found', isA<ConversationNotFound>()),
      'starting a conversation with oneself': (400, 'invalid_request', isA<SelfConversation>()),
      'an unrecognised error': (500, 'internal_error', isA<UnexpectedConversationsFailure>()),
    };
    cases.forEach((name, c) {
      final (status, code, failure) = c;
      test('throws a typed failure for $name', () async {
        await expectLater(
          repository(_StubAdapter.respond(status, _error(code))).openDirect(other),
          throwsA(failure),
        );
      });
    });

    test('throws ConversationsNetworkFailure when the backend is unreachable', () async {
      await expectLater(
        repository(_StubAdapter.connectionFails()).openDirect(other),
        throwsA(isA<ConversationsNetworkFailure>()),
      );
    });
  });

  group('watchList', () {
    Future<void> seedConversation({
      required String id,
      required String otherUserId,
      String otherDisplayName = 'Other',
      int unreadCount = 0,
      bool left = false,
      DateTime? pinnedAt,
      DateTime? archivedAt,
    }) async {
      await db
          .into(db.users)
          .insertOnConflictUpdate(
            UsersCompanion.insert(id: me, phoneNumber: '+14155550100'),
          );
      await db
          .into(db.users)
          .insertOnConflictUpdate(
            UsersCompanion.insert(
              id: otherUserId,
              phoneNumber: '+14155550101',
              displayName: Value(otherDisplayName),
            ),
          );
      await db
          .into(db.conversations)
          .insert(
            ConversationsCompanion.insert(
              id: id,
              type: 'direct',
              unreadCount: Value(unreadCount),
              left: Value(left),
              pinnedAt: Value(pinnedAt),
              archivedAt: Value(archivedAt),
            ),
          );
      await db
          .into(db.participants)
          .insert(ParticipantsCompanion.insert(conversationId: id, userId: me));
      await db
          .into(db.participants)
          .insert(ParticipantsCompanion.insert(conversationId: id, userId: otherUserId));
    }

    Future<void> seedMessage({
      required String id,
      required String conversationId,
      required String senderId,
      String? content = 'hi',
      bool isDeleted = false,
      required DateTime createdAt,
    }) => db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: id,
            conversationId: conversationId,
            senderId: senderId,
            content: Value(content),
            isDeleted: Value(isDeleted),
            createdAt: createdAt,
          ),
        );

    test('shows the other participant, a preview, and the unread badge', () async {
      await seedConversation(id: 'conv-1', otherUserId: other, unreadCount: 2);
      await seedMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: other,
        content: 'hey there',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final items = await repository(
        _StubAdapter.respond(200),
      ).watchList(myUserId: me).first;

      expect(items, hasLength(1));
      expect(items.single.otherUserId, other);
      expect(items.single.title, 'Other');
      expect(items.single.previewText, 'hey there');
      expect(items.single.unreadCount, 2);
    });

    test('prefixes the sender\'s own last message with "You: "', () async {
      await seedConversation(id: 'conv-1', otherUserId: other);
      await seedMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: me,
        content: 'see you at 6',
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final items = await repository(
        _StubAdapter.respond(200),
      ).watchList(myUserId: me).first;

      expect(items.single.previewText, 'You: see you at 6');
    });

    test('shows a deleted last message distinctly', () async {
      await seedConversation(id: 'conv-1', otherUserId: other);
      await seedMessage(
        id: 'msg-1',
        conversationId: 'conv-1',
        senderId: other,
        content: null,
        isDeleted: true,
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final items = await repository(
        _StubAdapter.respond(200),
      ).watchList(myUserId: me).first;

      expect(items.single.previewText, 'This message was deleted');
    });

    test('sorts pinned conversations first, then by last activity', () async {
      await seedConversation(id: 'conv-old', otherUserId: 'u-old');
      await seedMessage(
        id: 'msg-old',
        conversationId: 'conv-old',
        senderId: 'u-old',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await seedConversation(id: 'conv-new', otherUserId: 'u-new');
      await seedMessage(
        id: 'msg-new',
        conversationId: 'conv-new',
        senderId: 'u-new',
        createdAt: DateTime.utc(2026, 1, 2),
      );
      await seedConversation(
        id: 'conv-pinned',
        otherUserId: 'u-pinned',
        pinnedAt: DateTime.utc(2025, 1, 1),
      );

      final items = await repository(
        _StubAdapter.respond(200),
      ).watchList(myUserId: me).first;

      expect(items.map((i) => i.id), ['conv-pinned', 'conv-new', 'conv-old']);
    });

    test('excludes archived conversations from the main list, includes them in archived', () async {
      await seedConversation(
        id: 'conv-archived',
        otherUserId: other,
        archivedAt: DateTime.utc(2026, 1, 1),
      );
      await seedConversation(id: 'conv-active', otherUserId: 'u-active');

      final main = await repository(_StubAdapter.respond(200)).watchList(myUserId: me).first;
      final archived = await repository(
        _StubAdapter.respond(200),
      ).watchList(myUserId: me, archived: true).first;

      expect(main.map((i) => i.id), ['conv-active']);
      expect(archived.map((i) => i.id), ['conv-archived']);
    });

    test('shows a left conversation rather than filtering it out', () async {
      await seedConversation(id: 'conv-1', otherUserId: other, left: true);

      final items = await repository(_StubAdapter.respond(200)).watchList(myUserId: me).first;

      expect(items.single.left, isTrue);
    });
  });
}
