import 'package:convoze/app.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/presence/data/presence_providers.dart';
import 'package:convoze/features/presence/data/presence_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #34: presence read through the app's own providers — the same
// public interface the future conversation-list/chat-header screens use —
// while another User comes online, goes offline, and while our own
// connection is the one that's down.

const _bob = '+14155550101';
const _carol = '+14155550102';

PresenceState _presenceOf(WidgetTester tester, String userId) =>
    ProviderScope.containerOf(
      tester.element(find.byType(ConvozeApp)),
    ).read(presenceProvider(userId));

Future<void> _waitForConversationInReplica(
  WidgetTester tester,
  String conversationId,
) => pumpUntil(
  tester,
  () async {
    final rows = await (replica(tester).select(
      replica(tester).conversations,
    )..where((t) => t.id.equals(conversationId))).get();
    return rows.isNotEmpty;
  },
  reason: 'conversation.joined to reach the replica',
);

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
    'another user coming online, then going offline, updates presence',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await bob.createDirectConversationWith(myUserId);
      await _waitForConversationInReplica(tester, conversationId);

      final bobSocket = await bob.connectSocket();
      await pumpUntil(
        tester,
        () async => _presenceOf(tester, bob.userId) is PresenceOnline,
        reason: 'Bob to appear online once his socket connects',
      );

      bobSocket.dispose();
      await pumpUntil(
        tester,
        () async => _presenceOf(tester, bob.userId) is PresenceLastSeen,
        reason: 'Bob to appear last-seen once his socket disconnects',
      );
    },
  );

  testWidgets(
    'while our own transport is dropped, a previously online user reads as '
    "lastSeen, never offline; reconnecting restores the truth",
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      final myUserId = await currentUserId();
      final conversationId = await bob.createDirectConversationWith(myUserId);
      await _waitForConversationInReplica(tester, conversationId);

      final bobSocket = await bob.connectSocket();
      await pumpUntil(
        tester,
        () async => _presenceOf(tester, bob.userId) is PresenceOnline,
        reason: 'Bob to appear online once his socket connects',
      );

      await backend.dropTransport(sessionId);
      await pumpUntil(
        tester,
        () async => connection(tester).status != ConnectionStatus.connected,
        reason: 'the app to notice its own dropped transport',
      );

      // Bob never actually went offline — this is only ever `lastSeen`,
      // never a confident "offline" (`CONTEXT.md` **Presence**).
      expect(_presenceOf(tester, bob.userId), isA<PresenceLastSeen>());

      await untilStatus(
        tester,
        ConnectionStatus.connected,
        timeout: const Duration(seconds: 30),
      );
      await pumpUntil(
        tester,
        () async => _presenceOf(tester, bob.userId) is PresenceOnline,
        reason: 'the reconnect snapshot to restore the true state',
      );

      bobSocket.dispose();
    },
  );

  testWidgets('a user with no shared Conversation never appears', (
    tester,
  ) async {
    final carol = await OtherDevice.signIn(_carol);
    others.add(carol);
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);

    await carol.connectSocket();
    // No conversation.joined ever reaches this app for Carol, so nothing
    // should ever flip her out of `unknown` — settle a moment, then assert.
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(_presenceOf(tester, carol.userId), isA<PresenceUnknown>());
  });
}
