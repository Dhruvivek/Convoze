import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/features/conversations/data/conversation_prefs_failure.dart';
import 'package:convoze/features/conversations/data/conversation_prefs_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, or fails the connection,
/// and records the last request's method/path/body for assertions.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter.respond(this._status, [this._body]) : _connectionFails = false;

  final int _status;
  final Object? _body;
  final bool _connectionFails;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
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

Map<String, dynamic> _hydratedRow({
  String id = 'conv-1',
  String? pinnedAt,
  String? archivedAt,
  String? mutedUntil,
  String? hiddenAt,
  String? historyClearedMessageId,
  int unreadCount = 0,
}) => {
  'id': id,
  'type': 'direct',
  'name': null,
  'participants': [],
  'lastMessage': null,
  'unreadCount': unreadCount,
  'readWatermarks': [],
  'deliveryWatermarks': [],
  'left': false,
  'pinnedAt': pinnedAt,
  'archivedAt': archivedAt,
  'mutedUntil': mutedUntil,
  'hiddenAt': hiddenAt,
  'historyClearedMessageId': historyClearedMessageId,
  'users': [],
};

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.conversations).insert(ConversationsCompanion.insert(id: 'conv-1', type: 'direct'));
  });
  tearDown(() => db.close());

  ConversationPrefsRepository repository(_RecordingAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    return ConversationPrefsRepository(dio, db);
  }

  test('pin PATCHes {pinned: true} and upserts the hydrated row', () async {
    final adapter = _RecordingAdapter.respond(
      200,
      _hydratedRow(pinnedAt: '2026-01-01T00:00:00.000Z'),
    );

    await repository(adapter).pin('conv-1');

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/conversations/conv-1/prefs');
    expect(adapter.lastRequest!.data, {'pinned': true});
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.pinnedAt, isNotNull);
  });

  test('mute PATCHes the requested duration code', () async {
    final adapter = _RecordingAdapter.respond(
      200,
      _hydratedRow(mutedUntil: '2026-01-01T08:00:00.000Z'),
    );

    await repository(adapter).mute('conv-1', MuteDuration.eightHours);

    expect(adapter.lastRequest!.data, {'mute': '8h'});
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.mutedUntil, isNotNull);
  });

  test('unmute PATCHes a null mute', () async {
    final adapter = _RecordingAdapter.respond(200, _hydratedRow());

    await repository(adapter).unmute('conv-1');

    expect(adapter.lastRequest!.data, {'mute': null});
  });

  test('clear POSTs to /clear and applies the returned watermark', () async {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'msg-1',
            conversationId: 'conv-1',
            senderId: 'someone',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
    final adapter = _RecordingAdapter.respond(
      200,
      _hydratedRow(historyClearedMessageId: 'msg-1', unreadCount: 0),
    );

    await repository(adapter).clear('conv-1');

    expect(adapter.lastRequest!.method, 'POST');
    expect(adapter.lastRequest!.path, '/conversations/conv-1/clear');
    expect(await db.select(db.messages).get(), isEmpty);
  });

  test('delete POSTs to /delete and applies hiddenAt', () async {
    final adapter = _RecordingAdapter.respond(
      200,
      _hydratedRow(hiddenAt: '2026-01-01T00:00:00.000Z'),
    );

    await repository(adapter).delete('conv-1');

    expect(adapter.lastRequest!.path, '/conversations/conv-1/delete');
    final conversation = await (db.select(
      db.conversations,
    )..where((t) => t.id.equals('conv-1'))).getSingle();
    expect(conversation.hiddenAt, isNotNull);
  });

  final cases = <String, (int, String, Matcher)>{
    'the pin limit is reached': (409, 'pin_limit', isA<PinLimitReached>()),
    'a group has not been left': (409, 'must_leave_group', isA<MustLeaveGroup>()),
    'the caller is not a participant': (404, 'not_found', isA<ConversationPrefsNotFound>()),
    'an unrecognised error': (500, 'internal_error', isA<UnexpectedConversationPrefsFailure>()),
  };
  cases.forEach((name, c) {
    final (status, code, failure) = c;
    test('throws a typed failure for $name', () async {
      await expectLater(
        repository(_RecordingAdapter.respond(status, _error(code))).pin('conv-1'),
        throwsA(failure),
      );
    });
  });
}
