import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #51: expiring a User's Update log (simulating the retention job,
// #50) then reconnecting sends the Device down the `sync:reset` path, which
// rebuilds the local replica from a REST snapshot and resumes at
// `currentSeq`. Asserted directly against the replica (`AppDatabase`), since
// no chat screen reads it yet (#52/#53).

void main() {
  setUpE2e();

  testWidgets(
    'expiring the Update log then reconnecting rebuilds the replica from a '
    'snapshot and resumes from currentSeq',
    (tester) async {
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      final myUserId = await currentUserId();

      // A Conversation created through the e2e seed path (unlike a real
      // `POST /conversations/direct`) writes no Update — Alice's replica can
      // only ever learn about it through a REST snapshot, which is exactly
      // what this test exercises.
      final conversationId = await backend.seedConversation([
        '+14155550100',
        '+14155550101',
      ], type: 'direct');

      // Drop Alice's transport before Bob sends anything, so her live pump
      // never delivers it — only a `sync:reset` snapshot will.
      await backend.dropTransport(sessionId);
      await pumpUntil(
        tester,
        () async => connection(tester).status != ConnectionStatus.connected,
        reason: 'the dropped transport to be noticed',
      );

      final bob = await OtherDevice.signIn('+14155550101');
      final sendResult = await bob.sendMessage(
        await bob.connectSocket(),
        conversationId: conversationId,
        content: 'hello from Bob',
      );
      expect(sendResult['ok'], isTrue);
      bob.dispose();

      // Simulates the retention job (#50) having pruned Alice's whole log —
      // her stored `since` (still at whatever it was before the drop) is now
      // older than anything retained, which is what forces `sync:reset`
      // rather than an ordinary resumed drain.
      await backend.expireUpdateLog(myUserId);

      await untilStatus(tester, ConnectionStatus.connected);
      await pumpUntil(
        tester,
        () async => await replica(tester).readCursor() != null,
        reason: 'the reset snapshot to land',
      );

      final db = replica(tester);
      final conversation = await (db.select(
        db.conversations,
      )..where((t) => t.id.equals(conversationId))).getSingle();
      expect(conversation.unreadCount, 1);

      final messages = await (db.select(
        db.messages,
      )..where((t) => t.conversationId.equals(conversationId))).get();
      expect(messages, hasLength(1));
      expect(messages.single.content, 'hello from Bob');

      // Resumed at `currentSeq`, not 0: Bob's message bumped Alice's
      // UserSeq counter even though the Update row itself was expired.
      expect(await db.readCursor(), greaterThanOrEqualTo(1));
    },
  );
}
