import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #55: a 100-message conversation loads its first page on open, then
// pages `before` the oldest local message on scroll-to-top, and stops
// offering more (with a visible marker, no further requests) once it's
// exhausted history.

void main() {
  setUpE2e();

  testWidgets('scrolling back pages a long conversation, then reaches the start', (
    tester,
  ) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final myUserId = await currentUserId();

    final bob = await OtherDevice.signIn('+14155550101');
    final conversationId = await bob.createDirectConversationWith(myUserId);
    await pumpUntil(
      tester,
      () async {
        final rows = await (replica(tester).select(
          replica(tester).conversations,
        )..where((t) => t.id.equals(conversationId))).get();
        return rows.isNotEmpty;
      },
      reason: 'conversation.joined to reach Alice\'s replica',
    );

    await backend.seedMessages(conversationId, count: 100, senderId: bob.userId);

    await openChat(tester, conversationId);

    // Opening with nothing local yet fetches the first page (30).
    await pumpUntil(
      tester,
      () async => await _localMessageCount(tester, conversationId) == 30,
      reason: 'the first page (30) to load on open',
    );

    // Scrolling to the top pages in the next 30, then the next 30.
    await _scrollToTop(tester);
    await pumpUntil(
      tester,
      () async => await _localMessageCount(tester, conversationId) == 60,
      reason: 'a second page to load on scroll-to-top',
    );

    await _scrollToTop(tester);
    await pumpUntil(
      tester,
      () async => await _localMessageCount(tester, conversationId) == 90,
      reason: 'a third page to load on scroll-to-top',
    );

    // The last page is short (10): reaching it shows the "beginning of
    // conversation" marker instead of ever offering another page.
    await _scrollToTop(tester);
    await pumpUntil(
      tester,
      () async => await _localMessageCount(tester, conversationId) == 100,
      reason: 'the final short page to load on scroll-to-top',
    );
    await pumpUntil(
      tester,
      () async => find.text('Beginning of conversation').evaluate().isNotEmpty,
      reason: 'the beginning-of-conversation marker to show',
    );

    // One more scroll-to-top attempt must not fetch anything further.
    await _scrollToTop(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(await _localMessageCount(tester, conversationId), 100);

    bob.dispose();
  });
}

Future<int> _localMessageCount(WidgetTester tester, String conversationId) async {
  final rows = await (replica(tester).select(
    replica(tester).messages,
  )..where((t) => t.conversationId.equals(conversationId))).get();
  return rows.length;
}

/// Drags the (reversed) message list toward its top — the scroll-to-top
/// pagination trigger — then lets the resulting fetch settle.
Future<void> _scrollToTop(WidgetTester tester) async {
  final list = find.byType(Scrollable);
  for (var i = 0; i < 6; i++) {
    await tester.drag(list, const Offset(0, 400));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}
