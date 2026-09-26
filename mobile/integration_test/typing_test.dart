import 'package:convoze/app.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/conversations/data/typers_providers.dart';
import 'package:convoze/features/conversations/presentation/chat_thread_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #35: another User's typing shows up, clears on stopTyping/idle
// timeout/their userOffline, our own second Device's typing is ignored, our
// own dropped transport clears every typer, and outgoing typing/stopTyping
// actually reach the wire.

const _bob = '+14155550101';
const _alice = '+14155550100';

Set<String> _typersOf(WidgetTester tester, String conversationId) =>
    ProviderScope.containerOf(
      tester.element(find.byType(ConvozeApp)),
    ).read(typersProvider(conversationId));

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
    "another user's typing appears, and clears on stopTyping",
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      bobSocket.emit('typing', {'conversationId': conversationId});
      await pumpUntil(
        tester,
        () async => _typersOf(tester, conversationId).contains(bob.userId),
        reason: "Bob's typing to appear",
      );

      bobSocket.emit('stopTyping', {'conversationId': conversationId});
      await pumpUntil(
        tester,
        () async => !_typersOf(tester, conversationId).contains(bob.userId),
        reason: "Bob's stopTyping to clear it",
      );
    },
  );

  testWidgets(
    'typing clears on its own after about 6s of silence',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      bobSocket.emit('typing', {'conversationId': conversationId});
      await pumpUntil(
        tester,
        () async => _typersOf(tester, conversationId).contains(bob.userId),
        reason: "Bob's typing to appear",
      );

      await pumpUntil(
        tester,
        () async => !_typersOf(tester, conversationId).contains(bob.userId),
        reason: 'the 6s receiver timeout to clear it on its own',
        timeout: const Duration(seconds: 10),
      );
    },
  );

  testWidgets(
    'typing clears when the typer goes offline',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      bobSocket.emit('typing', {'conversationId': conversationId});
      await pumpUntil(
        tester,
        () async => _typersOf(tester, conversationId).contains(bob.userId),
        reason: "Bob's typing to appear",
      );

      bobSocket.dispose();
      await pumpUntil(
        tester,
        () async => !_typersOf(tester, conversationId).contains(bob.userId),
        reason: "Bob's userOffline to clear his typing",
      );
    },
  );

  testWidgets("typing from our own second Device is ignored", (tester) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final myUserId = await currentUserId();
    final bob = await OtherDevice.signIn(_bob);
    others.add(bob);
    final conversationId = await _directConversationWith(tester, bob, myUserId);
    await openChat(tester, conversationId);

    final aliceDevice2 = await OtherDevice.signIn(_alice);
    others.add(aliceDevice2);
    final aliceDevice2Socket = await aliceDevice2.connectSocket();
    aliceDevice2Socket.emit('typing', {'conversationId': conversationId});

    // No specific event to wait for (nothing should happen) — settle a
    // moment, then assert it never showed up.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(_typersOf(tester, conversationId), isEmpty);
  });

  testWidgets(
    'all typers clear when our own transport drops',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      bobSocket.emit('typing', {'conversationId': conversationId});
      await pumpUntil(
        tester,
        () async => _typersOf(tester, conversationId).contains(bob.userId),
        reason: "Bob's typing to appear",
      );

      await backend.dropTransport(sessionId);
      await pumpUntil(
        tester,
        () async => _typersOf(tester, conversationId).isEmpty,
        reason: 'every typer to clear once our own transport drops',
      );
    },
  );

  testWidgets(
    'outgoing typing reaches the other participant, and stopTyping is sent on send',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      final bobSawTyping = nextEvent(bobSocket, 'typing');
      await tester.enterText(
        find.byKey(ChatThreadScreen.composerFieldKey),
        'h',
      );
      await tester.pump();

      expect(await bobSawTyping, {'conversationId': conversationId, 'userId': myUserId});

      final bobSawStopTyping = nextEvent(bobSocket, 'stopTyping');
      await tester.tap(find.byKey(ChatThreadScreen.sendButtonKey));
      await tester.pump();

      expect(
        await bobSawStopTyping,
        {'conversationId': conversationId, 'userId': myUserId},
      );
    },
  );

  testWidgets(
    'outgoing typing is throttled to at most one per ~3s',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      var typingCount = 0;
      bobSocket.on('typing', (_) => typingCount++);

      // Three keystrokes in quick succession, all well inside the 3s
      // throttle window.
      await tester.enterText(find.byKey(ChatThreadScreen.composerFieldKey), 'h');
      await tester.pump();
      await tester.enterText(find.byKey(ChatThreadScreen.composerFieldKey), 'he');
      await tester.pump();
      await tester.enterText(
        find.byKey(ChatThreadScreen.composerFieldKey),
        'hel',
      );
      await tester.pump();

      // Time for the one allowed `typing` to actually arrive, well short of
      // the 3s throttle window the next one would need to wait out.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(typingCount, 1);
    },
  );

  testWidgets(
    'stopTyping is sent on its own after ~5s idle, without sending',
    (tester) async {
      final bob = await OtherDevice.signIn(_bob);
      others.add(bob);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final myUserId = await currentUserId();
      final conversationId = await _directConversationWith(tester, bob, myUserId);
      final bobSocket = await bob.connectSocket();
      await openChat(tester, conversationId);

      final bobSawStopTyping = nextEvent(
        bobSocket,
        'stopTyping',
        timeout: const Duration(seconds: 10),
      );
      await tester.enterText(
        find.byKey(ChatThreadScreen.composerFieldKey),
        'h',
      );
      await tester.pump();

      expect(
        await bobSawStopTyping,
        {'conversationId': conversationId, 'userId': myUserId},
      );
    },
  );
}
