import 'dart:convert';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/db/database_provider.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/core/sync/sync_engine.dart';
import 'package:convoze/features/conversations/data/messages_repository.dart';
import 'package:convoze/features/conversations/data/typing_repository.dart';
import 'package:convoze/features/conversations/presentation/chat_thread_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

/// Records every outgoing `emit` (as `(event, conversationId)`) instead of
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

const me = 'user-me';
const other = 'user-other';
const conversationId = 'conv-1';

/// Answers `GET /conversations/:id/messages` with an always-empty,
/// start-of-history page — enough for the screens that already have local
/// messages (their `ensureInitialPage` skips the fetch entirely) and for
/// the empty-conversation test, which relies on exactly this response.
class _EmptyHistoryAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'messages': <dynamic>[], 'nextBefore': null, 'users': <dynamic>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Drift's watched-query cancellation schedules a zero-duration `Timer`
/// during widget disposal; the test framework's own automatic teardown
/// disposes the tree but never pumps again afterwards, so that timer trips
/// `!timersPending`. Disposing explicitly, then pumping once more, lets it
/// fire before the test ends.
Future<void> _disposeCleanly(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  late AppDatabase db;
  late MessagesRepository repo;
  late TypingRepository typingRepo;
  late _RecordingSocket typingSocket;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'user': '{"id":"$me","phoneNumber":"+14155550100","displayName":"Me"}',
    });
    db = AppDatabase(NativeDatabase.memory());
    final dio = Dio(BaseOptions(baseUrl: 'http://fake'))
      ..httpClientAdapter = _EmptyHistoryAdapter();
    final tokenStore = TokenStore(const FlutterSecureStorage());
    final syncEngine = SyncEngine(db: db, dio: dio, tokenStore: tokenStore);
    repo = MessagesRepository(
      db: db,
      dio: dio,
      tokenStore: tokenStore,
      syncEngine: syncEngine,
      currentSocket: () => null,
    );
    typingSocket = _RecordingSocket();
    typingRepo = TypingRepository(tokenStore: tokenStore)..attach(typingSocket);
  });

  tearDown(() => db.close());

  Future<void> seedConversationWithMessages() async {
    await db
        .into(db.conversations)
        .insert(ConversationsCompanion.insert(id: conversationId, type: 'direct'));
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: other,
            phoneNumber: '+14155550101',
            displayName: const Value('Bob'),
          ),
        );
    await db
        .into(db.participants)
        .insert(ParticipantsCompanion.insert(conversationId: conversationId, userId: me));
    await db
        .into(db.participants)
        .insert(ParticipantsCompanion.insert(conversationId: conversationId, userId: other));
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm1',
            conversationId: conversationId,
            senderId: other,
            type: const Value('text'),
            content: const Value('hi there'),
            createdAt: DateTime.utc(2026, 1, 1, 10),
          ),
        );
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: 'm2',
            conversationId: conversationId,
            senderId: me,
            type: const Value('text'),
            content: const Value('hello!'),
            createdAt: DateTime.utc(2026, 1, 1, 10, 1),
          ),
        );
  }

  Widget buildScreen() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        messagesRepositoryProvider.overrideWithValue(repo),
        typingRepositoryProvider.overrideWithValue(typingRepo),
      ],
      child: const MaterialApp(
        home: ChatThreadScreen(conversationId: conversationId),
      ),
    );
  }

  testWidgets('shows messages grouped by day, with a tick icon on my own message', (
    tester,
  ) async {
    await seedConversationWithMessages();

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('hi there'), findsOneWidget);
    expect(find.text('hello!'), findsOneWidget);
    expect(find.text('Jan 1, 2026'), findsOneWidget);
    // The other participant hasn't delivered/read it yet: a single check.
    expect(find.byIcon(Icons.check), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets('sending queues an Outbox row and clears the composer', (tester) async {
    await seedConversationWithMessages();
    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(ChatThreadScreen.composerFieldKey),
      'new message',
    );
    await tester.tap(find.byKey(ChatThreadScreen.sendButtonKey));
    await tester.pumpAndSettle();

    final outbox = await db.select(db.outbox).get();
    expect(outbox.single.content, 'new message');
    final field = tester.widget<TextField>(find.byKey(ChatThreadScreen.composerFieldKey));
    expect(field.controller!.text, isEmpty);

    await _disposeCleanly(tester);
  });

  group('a failed Outbox row (#54)', () {
    Future<void> seedFailedRow() => db.into(db.outbox).insert(
      OutboxCompanion.insert(
        clientMsgId: 'c1',
        conversationId: conversationId,
        content: 'oops',
        status: const Value('failed'),
        createdAt: DateTime.utc(2026, 1, 1, 10, 2),
      ),
    );

    testWidgets('shows "Failed — tap to retry or delete"', (tester) async {
      await seedConversationWithMessages();
      await seedFailedRow();

      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Failed — tap to retry or delete'), findsOneWidget);
      expect(find.text('oops'), findsOneWidget);

      await _disposeCleanly(tester);
    });

    testWidgets('tapping it then Retry puts the row back to pending', (
      tester,
    ) async {
      await seedConversationWithMessages();
      await seedFailedRow();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Failed — tap to retry or delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ChatThreadScreen.retryFailedKey));
      await tester.pumpAndSettle();

      final row = await db.select(db.outbox).getSingle();
      expect(row.status, 'pending');

      await _disposeCleanly(tester);
    });

    testWidgets('tapping it then Delete removes the row', (tester) async {
      await seedConversationWithMessages();
      await seedFailedRow();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Failed — tap to retry or delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ChatThreadScreen.discardFailedKey));
      await tester.pumpAndSettle();

      expect(await db.select(db.outbox).get(), isEmpty);
      expect(find.text('oops'), findsNothing);

      await _disposeCleanly(tester);
    });
  });

  testWidgets('shows "Beginning of conversation" once an empty chat has been fetched', (
    tester,
  ) async {
    await db
        .into(db.conversations)
        .insert(ConversationsCompanion.insert(id: conversationId, type: 'direct'));

    await tester.pumpWidget(buildScreen());
    await tester.pumpAndSettle();

    expect(find.text('Say hi 👋'), findsOneWidget);

    await _disposeCleanly(tester);
  });

  group('typing (#35)', () {
    testWidgets('typing in the composer sends typing', (tester) async {
      await seedConversationWithMessages();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(ChatThreadScreen.composerFieldKey),
        'h',
      );

      expect(typingSocket.sent, [('typing', conversationId)]);

      await _disposeCleanly(tester);
    });

    testWidgets('sending a message sends stopTyping', (tester) async {
      await seedConversationWithMessages();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ChatThreadScreen.composerFieldKey),
        'new message',
      );

      await tester.tap(find.byKey(ChatThreadScreen.sendButtonKey));
      await tester.pumpAndSettle();

      expect(typingSocket.sent.last, ('stopTyping', conversationId));

      await _disposeCleanly(tester);
    });

    testWidgets('leaving the chat sends stopTyping', (tester) async {
      await seedConversationWithMessages();
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(ChatThreadScreen.composerFieldKey),
        'h',
      );

      await _disposeCleanly(tester);

      expect(typingSocket.sent.last, ('stopTyping', conversationId));
    });
  });
}
