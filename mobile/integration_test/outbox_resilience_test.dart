import 'package:convoze/app.dart';
import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/core/router/app_router.dart';
import 'package:convoze/features/auth/presentation/logout_menu.dart';
import 'package:convoze/features/conversations/presentation/chat_thread_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #54: the Outbox drainer's real guarantee — offline queueing and
// in-order delivery, surviving the app being killed, the failed/retry/delete
// path, RATE_LIMITED self-recovery, and the logout warning.

const _bob = '+14155550101';
const _carol = '+14155550102';

// A bare `pump()`, never `pumpAndSettle()`: while disconnected, the
// "Connecting…" banner's indeterminate spinner animates forever and would
// make `pumpAndSettle()` hang until its own timeout (`realtime_connection_test.dart`
// avoids it for the same reason). Callers that need to know the message
// actually rendered use [_untilTextShows] afterwards.
Future<void> _typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(ChatThreadScreen.composerFieldKey), text);
  await tester.tap(find.byKey(ChatThreadScreen.sendButtonKey));
  await tester.pump();
}

Future<void> _untilTextShows(WidgetTester tester, String text) => pumpUntil(
  tester,
  () async => find.text(text).evaluate().isNotEmpty,
  reason: '"$text" to render',
);

Future<String> _directConversationWith(
  WidgetTester tester,
  OtherDevice other,
  String myUserId,
) async {
  final conversationId = await other.createDirectConversationWith(myUserId);
  await pumpUntil(
    tester,
    () async {
      final rows = await (replica(tester).select(
        replica(tester).conversations,
      )..where((t) => t.id.equals(conversationId))).get();
      return rows.isNotEmpty;
    },
    reason: 'conversation.joined to reach the replica',
  );
  return conversationId;
}

GoRouter _router(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ConvozeApp)),
).read(routerProvider);

/// Bare `pump()`s, not `pumpAndSettle()`, after any navigation below — safe
/// to call while the "Connecting…" banner might be showing (`openChat`
/// itself isn't, since every other e2e suite only calls it once connected).
Future<void> _settleOffline(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _openChatOffline(WidgetTester tester, String conversationId) async {
  _router(tester).push('/chat/$conversationId');
  await _settleOffline(tester);
}

Future<void> _closeChat(WidgetTester tester) async {
  _router(tester).pop();
  await _settleOffline(tester);
}

void main() {
  setUpE2e();

  final others = <OtherDevice>[];
  tearDown(() {
    for (final other in others) {
      other.dispose();
    }
    others.clear();
  });

  testWidgets(
    'sending offline across two chats queues in composed order, delivered '
    'once reconnected',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      final carol = await OtherDevice.signIn(_carol);
      others.add(carol);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      final myUserId = await currentUserId();

      final conv1 = await _directConversationWith(tester, bob, myUserId);
      final conv2 = await _directConversationWith(tester, carol, myUserId);

      await backend.dropTransport(sessionId);
      await pumpUntil(
        tester,
        () async => connection(tester).status != ConnectionStatus.connected,
        reason: 'the app to notice the dropped transport',
      );

      await _openChatOffline(tester, conv1);
      await _typeAndSend(tester, 'one');
      await _untilTextShows(tester, 'one');
      await _typeAndSend(tester, 'two');
      await _untilTextShows(tester, 'two');

      await _closeChat(tester);
      await _openChatOffline(tester, conv2);
      await _typeAndSend(tester, 'three');
      await _untilTextShows(tester, 'three');

      // No explicit "restore" step: `dropTransport` only killed the
      // transport, and the library's own reconnection (ADR 0005) picks the
      // connection back up on its own.
      await untilStatus(
        tester,
        ConnectionStatus.connected,
        timeout: const Duration(seconds: 30),
      );
      await pumpUntil(
        tester,
        () async => await replica(tester).outboxCount() == 0,
        reason: 'the Outbox to drain once reconnected',
        timeout: const Duration(seconds: 30),
      );

      final messages = await (replica(tester).select(replica(tester).messages)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();
      expect(messages.map((m) => m.content).toList(), ['one', 'two', 'three']);
    },
  );

  testWidgets(
    'a message sent offline survives the app being killed, and sends on '
    'relaunch',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);

      await backend.dropTransport(sessionId);
      await pumpUntil(
        tester,
        () async => connection(tester).status != ConnectionStatus.connected,
        reason: 'the app to notice the dropped transport',
      );

      await _openChatOffline(tester, conversationId);
      await _typeAndSend(tester, 'still here after restart');
      expect(await replica(tester).outboxCount(), 1);

      // "Killing" the app: `launchApp` cold-starts a fresh ConvozeApp over
      // whatever is already on disk (the replica sqlite file and secure
      // storage survive; only in-memory state is gone), the same way a real
      // kill-and-relaunch would leave them.
      await launchApp(tester);
      await untilStatus(
        tester,
        ConnectionStatus.connected,
        timeout: const Duration(seconds: 30),
      );

      await pumpUntil(
        tester,
        () async => await replica(tester).outboxCount() == 0,
        reason: 'the pending message to drain after relaunch',
        timeout: const Duration(seconds: 30),
      );
      final sent = await (replica(tester).select(
        replica(tester).messages,
      )..where((t) => t.content.equals('still here after restart'))).get();
      expect(sent, hasLength(1));
    },
  );

  testWidgets(
    'an injected INVALID shows failed; retry sends it, discard removes it',
    (tester) async {
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      await openChat(tester, conversationId);

      await backend.failNextSocketEvent('message:send', code: 'INVALID');
      await _typeAndSend(tester, 'will fail');
      await pumpUntil(
        tester,
        () async => find.text('Failed — tap to retry or delete').evaluate().isNotEmpty,
        reason: 'the injected INVALID to mark the row failed',
      );

      await tester.tap(find.text('Failed — tap to retry or delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ChatThreadScreen.retryFailedKey));
      await pumpUntil(
        tester,
        () async => await replica(tester).outboxCount() == 0,
        reason: 'the retried send to be confirmed',
      );
      final sent = await (replica(tester).select(
        replica(tester).messages,
      )..where((t) => t.content.equals('will fail'))).get();
      expect(sent, hasLength(1));

      await backend.failNextSocketEvent('message:send', code: 'INVALID');
      await _typeAndSend(tester, 'will be discarded');
      await pumpUntil(
        tester,
        () async => find.text('Failed — tap to retry or delete').evaluate().isNotEmpty,
        reason: 'the second injected INVALID to mark the row failed',
      );

      await tester.tap(find.text('Failed — tap to retry or delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ChatThreadScreen.discardFailedKey));
      await tester.pumpAndSettle();

      expect(await replica(tester).outboxCount(), 0);
      expect(find.text('will be discarded'), findsNothing);
    },
  );

  testWidgets('an injected RATE_LIMITED retries by itself', (tester) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final myUserId = await currentUserId();
    final bob = await OtherDevice.signIn(_bob);
    others.add(bob);
    final conversationId = await _directConversationWith(tester, bob, myUserId);
    await openChat(tester, conversationId);

    await backend.failNextSocketEvent('message:send', code: 'RATE_LIMITED');
    await _typeAndSend(tester, 'slow down');

    // The drainer backs off (1s, 2s, 4s, ... capped at 30s) and retries the
    // same row without any user action.
    await pumpUntil(
      tester,
      () async => await replica(tester).outboxCount() == 0,
      reason: 'the drainer to retry after the RATE_LIMITED backoff',
      timeout: const Duration(seconds: 15),
    );
    final sent = await (replica(tester).select(
      replica(tester).messages,
    )..where((t) => t.content.equals('slow down'))).get();
    expect(sent, hasLength(1));
  });

  testWidgets(
    'logging out with a pending Outbox warns, then wipes it',
    (tester) async {
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);

      // Seeded directly rather than via a dropped transport: nothing kicks
      // the drainer for a row it doesn't know was just inserted (only
      // `send()`'s own kick and the next reconnect/catch-up do), so this
      // stays put with the connection otherwise untouched — no "Connecting…"
      // banner to race `pumpAndSettle()` against below.
      await replica(tester).into(replica(tester).outbox).insert(
        OutboxCompanion.insert(
          clientMsgId: 'c-never-sent',
          conversationId: 'conv-does-not-matter',
          content: 'never sent',
          createdAt: DateTime.now().toUtc(),
        ),
      );

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('1 unsent message will be lost.'), findsOneWidget);

      await tester.tap(find.byKey(LogoutMenu.confirmLogOutKey));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(await const FlutterSecureStorage().read(key: 'access_token'), isNull);
    },
  );
}
