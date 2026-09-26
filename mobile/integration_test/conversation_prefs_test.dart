import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #45's core flows against the real backend: pin sorts to the top
// and the 6th pin hits the limit, mute shows the icon, archive moves a chat
// off the main list (and a new message doesn't bring it back), and delete
// removes a direct chat until the other participant writes again.

const _otherPhoneNumbers = [
  '+14155550101',
  '+14155550102',
  '+14155550103',
  '+14155550104',
  '+14155550105',
  '+14155550106',
];

/// The masked-phone fallback label a seeded contact shows with (no display
/// name is set for e2e-seeded users), per `core/formatting/display_name.dart`.
String _labelFor(String phoneNumber) => '•••• ${phoneNumber.substring(phoneNumber.length - 4)}';

Future<void> _longPressAndTap(WidgetTester tester, String rowLabel, String actionLabel) async {
  await tester.longPress(find.text(rowLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();
}

void main() {
  setUpE2e();

  testWidgets('pinning sorts chats to the top and the 6th hits the pin limit', (tester) async {
    for (final phoneNumber in _otherPhoneNumbers) {
      await backend.seedConversation(['+14155550100', phoneNumber], type: 'direct');
    }

    await launchApp(tester);
    await signIn(tester);
    await pumpUntil(
      tester,
      () async => find.text(_labelFor(_otherPhoneNumbers.last)).evaluate().isNotEmpty,
      reason: 'all seeded conversations to appear',
    );

    for (final phoneNumber in _otherPhoneNumbers.take(5)) {
      await _longPressAndTap(tester, _labelFor(phoneNumber), 'Pin chat');
    }

    await _longPressAndTap(tester, _labelFor(_otherPhoneNumbers.last), 'Pin chat');

    expect(find.text('You can pin up to 5 chats — unpin one first.'), findsOneWidget);
  });

  testWidgets('muting shows the muted icon on the row', (tester) async {
    await backend.seedConversation(['+14155550100', _otherPhoneNumbers[0]], type: 'direct');

    await launchApp(tester);
    await signIn(tester);
    final label = _labelFor(_otherPhoneNumbers[0]);
    await pumpUntil(
      tester,
      () async => find.text(label).evaluate().isNotEmpty,
      reason: 'the seeded conversation to appear',
    );

    await tester.longPress(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.notifications_off), findsWidgets);
  });

  testWidgets('archiving moves a chat off the main list, and a new message keeps it archived', (
    tester,
  ) async {
    final conversationId = await backend.seedConversation([
      '+14155550100',
      _otherPhoneNumbers[0],
    ], type: 'direct');

    await launchApp(tester);
    await signIn(tester);
    final label = _labelFor(_otherPhoneNumbers[0]);
    await pumpUntil(
      tester,
      () async => find.text(label).evaluate().isNotEmpty,
      reason: 'the seeded conversation to appear',
    );

    await _longPressAndTap(tester, label, 'Archive chat');

    expect(find.text(label), findsNothing);
    expect(find.text('Archived'), findsOneWidget);

    final other = await OtherDevice.signIn(_otherPhoneNumbers[0]);
    final socket = await other.connectSocket();
    await other.sendMessage(socket, conversationId: conversationId, content: 'still here');
    other.dispose();

    // Give the live Update a moment to land, then confirm it stayed off the
    // main list (archiving isn't undone by new activity, #45).
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(label), findsNothing);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text(label), findsOneWidget);
  });

  testWidgets('deleting a direct chat hides it until the other participant writes again', (
    tester,
  ) async {
    final conversationId = await backend.seedConversation([
      '+14155550100',
      _otherPhoneNumbers[0],
    ], type: 'direct');

    await launchApp(tester);
    await signIn(tester);
    final label = _labelFor(_otherPhoneNumbers[0]);
    await pumpUntil(
      tester,
      () async => find.text(label).evaluate().isNotEmpty,
      reason: 'the seeded conversation to appear',
    );

    await tester.longPress(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete').last);
    await tester.pumpAndSettle();

    expect(find.text(label), findsNothing);

    final other = await OtherDevice.signIn(_otherPhoneNumbers[0]);
    final socket = await other.connectSocket();
    await other.sendMessage(socket, conversationId: conversationId, content: 'came back');
    other.dispose();

    await pumpUntil(
      tester,
      () async => find.text(label).evaluate().isNotEmpty,
      reason: 'the chat to reappear once the other participant writes again',
    );
    expect(find.text('came back'), findsOneWidget);
  });
}
