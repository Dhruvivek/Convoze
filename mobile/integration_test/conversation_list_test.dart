import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #52's own acceptance criterion: signing in with seeded
// conversations shows the list with correct previews and unread counts.
// Bob's message is sent before Alice ever signs in, so her replica can only
// learn about it through the `sync:reset` REST snapshot every fresh install
// goes through (no stored cursor yet) — the same seeding recipe as
// `sync_engine_test.dart`.

void main() {
  setUpE2e();

  testWidgets(
    'signing in shows a seeded conversation with its last message preview and unread count',
    (tester) async {
      final conversationId = await backend.seedConversation([
        '+14155550100',
        '+14155550101',
      ], type: 'direct');

      final bob = await OtherDevice.signIn('+14155550101');
      final socket = await bob.connectSocket();
      final sendResult = await bob.sendMessage(
        socket,
        conversationId: conversationId,
        content: 'hello from Bob',
      );
      expect(sendResult['ok'], isTrue);
      bob.dispose();

      await launchApp(tester);
      await signIn(tester);

      // No display name was set for Bob, so the row falls back to the
      // masked last-4-digits form (`core/formatting/display_name.dart`).
      await pumpUntil(
        tester,
        () async => find.text('•••• 0101').evaluate().isNotEmpty,
        reason: 'the seeded conversation to appear in the list',
      );

      expect(find.text('hello from Bob'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // the unread badge
    },
  );
}
