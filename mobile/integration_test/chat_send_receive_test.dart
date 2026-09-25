import 'dart:async';

import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/conversations/presentation/chat_thread_screen.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #53: opening a chat, sending online, receiving live, and receipts
// moving the delivery/read watermarks. "Other Devices" here are Bob's own
// Device (a second User) and Alice's own second Device (same phone,
// signed in twice) — both raw socket.io clients, not the sync engine, so
// batches they receive are acked manually via [_acceptBatches].

/// Auto-acks every `sync:batch` on [socket] with its highest `seq`
/// (mirroring `SyncEngine.applyBatch`'s ack contract) so its Updates —
/// deliveries and receipts among them — actually land, and completes
/// [onBatch] with each decoded payload as it arrives.
void _acceptBatches(io.Socket socket, void Function(Map<String, dynamic>) onBatch) {
  socket.on('sync:batch', (args) {
    final list = args as List;
    final payload = (list[0] as Map).cast<String, dynamic>();
    final ackFn = list[1] as Function;
    final updates = (payload['updates'] as List).cast<Map>();
    final highestSeq = updates.map((u) => u['seq'] as int).reduce((a, b) => a > b ? a : b);
    ackFn(highestSeq);
    onBatch(payload);
  });
}

void main() {
  setUpE2e();

  testWidgets('send, receive live, and receipts move the ticks', (tester) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final myUserId = await currentUserId();

    final bob = await OtherDevice.signIn('+14155550101');
    final bobSocket = await bob.connectSocket();
    final bobBatches = StreamController<Map<String, dynamic>>.broadcast();
    _acceptBatches(bobSocket, bobBatches.add);

    final aliceDevice2 = await OtherDevice.signIn('+14155550100');
    final aliceDevice2Socket = await aliceDevice2.connectSocket();
    final aliceDevice2Batches = StreamController<Map<String, dynamic>>.broadcast();
    _acceptBatches(aliceDevice2Socket, aliceDevice2Batches.add);

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

    await openChat(tester, conversationId);

    // A message from Bob arrives live.
    final bobSend = await bob.sendMessage(
      bobSocket,
      conversationId: conversationId,
      content: 'hello from Bob',
    );
    expect(bobSend['ok'], isTrue);
    final bobMessageId = bobSend['messageId'] as String;

    await pumpUntil(
      tester,
      () async => find.text('hello from Bob').evaluate().isNotEmpty,
      reason: 'Bob\'s message to appear live',
    );

    // Opening the chat with Bob's message now in it moves Alice's read
    // watermark and clears the unread badge — on this Device's replica...
    await pumpUntil(
      tester,
      () async {
        final conv = await (replica(tester).select(
          replica(tester).conversations,
        )..where((t) => t.id.equals(conversationId))).getSingle();
        return conv.unreadCount == 0;
      },
      reason: 'unreadCount to clear on this Device',
    );
    // ...and, since receipts fan out to every Participant including the
    // mover's own other Devices, on Alice's second Device too.
    final secondDeviceReceipt = await aliceDevice2Batches.stream
        .expand((payload) => (payload['updates'] as List).cast<Map>())
        .firstWhere(
          (u) =>
              u['kind'] == 'conversation.receipts' &&
              (u['payload'] as Map)['conversationId'] == conversationId,
        )
        .timeout(const Duration(seconds: 10));
    expect(secondDeviceReceipt, isNotNull);

    // Alice sends a message online: it appears immediately (the tick
    // progression itself — clock → sent → delivered → read — is covered by
    // `chat_message_view_test.dart`; here it's enough to see it reach
    // "delivered" for real, since "sent" can be too transient to catch
    // reliably against a real backend once Bob's auto-ack is already live).
    await tester.enterText(
      find.byKey(ChatThreadScreen.composerFieldKey),
      'hi Bob',
    );
    await tester.tap(find.byKey(ChatThreadScreen.sendButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('hi Bob'), findsOneWidget);

    // Bob's Device acking the batch that carries it moves the delivery
    // watermark; the app re-renders with two ticks.
    await pumpUntil(
      tester,
      () async => find.byIcon(Icons.done_all).evaluate().isNotEmpty,
      reason: 'the delivery watermark to move (double check)',
    );

    // Bob reading it moves the read watermark, visible on Alice's replica.
    final aliceMessage = await (replica(tester).select(
      replica(tester).messages,
    )..where((t) => t.conversationId.equals(conversationId) & t.senderId.equals(myUserId))).getSingle();
    final readAck = await bobSocket.timeout(5000).emitWithAckAsync('conversation:read', {
      'conversationId': conversationId,
      'messageId': aliceMessage.id,
    });
    expect((readAck as Map)['ok'], isTrue);
    await pumpUntil(
      tester,
      () async {
        final participant = await (replica(tester).select(
          replica(tester).participants,
        )..where(
              (t) =>
                  t.conversationId.equals(conversationId) &
                  t.userId.equals(bob.userId),
            ))
            .getSingle();
        return participant.lastReadMessageId != null &&
            participant.lastReadMessageId!.compareTo(aliceMessage.id) >= 0;
      },
      reason: 'Bob\'s read watermark to reach Alice\'s replica',
    );

    // A message sent from Alice's own second Device appears here too.
    await aliceDevice2.sendMessage(
      aliceDevice2Socket,
      conversationId: conversationId,
      content: 'also from Alice, second device',
    );
    await pumpUntil(
      tester,
      () async => find.text('also from Alice, second device').evaluate().isNotEmpty,
      reason: 'a message from Alice\'s own second Device to appear',
    );

    expect(bobMessageId, isNotEmpty);
    bob.dispose();
    aliceDevice2.dispose();
    await bobBatches.close();
    await aliceDevice2Batches.close();
  });
}
