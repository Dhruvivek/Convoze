import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

const _alice = '+14155550100';
const _bob = '+14155550101';

void main() {
  setUpE2e();

  final others = <OtherDevice>[];
  tearDown(() {
    for (final other in others) {
      other.dispose();
    }
    others.clear();
  });

  testWidgets('after sign-in the app connects', (tester) async {
    await launchApp(tester);
    expect(connection(tester).status, ConnectionStatus.offline);

    await signIn(tester);

    await untilStatus(tester, ConnectionStatus.connected);
    expect(await backend.socketCount(await currentSessionId()), 1);
  });

  testWidgets("an event sent to one of the user's Conversations reaches the "
      'app', (tester) async {
    final conversationId = await backend.seedConversation([_alice, _bob]);
    final bob = await OtherDevice.signIn(_bob);
    others.add(bob);
    final bobSocket = await bob.connectSocket();
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);

    final appReceived = nextEvent(connection(tester).socket!, 'e2e:test');
    final bobReceived = nextEvent(bobSocket, 'e2e:test');
    await backend.emitTestEvent('conversation:$conversationId', {'n': 1});

    expect(await appReceived, {'n': 1});
    expect(await bobReceived, {'n': 1});
  });

  testWidgets('logging out disconnects the app', (tester) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final sessionId = await currentSessionId();

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(connection(tester).status, ConnectionStatus.offline);
    expect(connection(tester).socket, isNull);
    await pumpUntil(
      tester,
      () async => await backend.socketCount(sessionId) == 0,
      reason: 'the server to drop the socket',
    );
  });

  testWidgets(
    'dropping the transport shows the banner, reconnects automatically, '
    'then hides it',
    (tester) async {
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      expect(find.text('Connecting…'), findsNothing);

      await backend.dropTransport(sessionId);

      await pumpUntil(
        tester,
        () async => connection(tester).status == ConnectionStatus.reconnecting,
        reason: 'the app to notice the dropped transport',
      );
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);

      await untilStatus(tester, ConnectionStatus.connected);
      await tester.pump();
      expect(find.text('Connecting…'), findsNothing);
      expect(await backend.socketCount(sessionId), 1);
    },
  );

  testWidgets('backgrounding disconnects and foregrounding reconnects', (
    tester,
  ) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final sessionId = await currentSessionId();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    // An empty Outbox needs no grace (#54), but the disconnect itself is
    // no longer synchronous with the lifecycle callback.
    await untilStatus(tester, ConnectionStatus.offline);
    // A deliberate background disconnect isn't shown as "Connecting…" — the
    // user has no screen to see it on anyway.
    expect(find.text('Connecting…'), findsNothing);
    await pumpUntil(
      tester,
      () async => await backend.socketCount(sessionId) == 0,
      reason: 'the server to drop the backgrounded socket',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await untilStatus(tester, ConnectionStatus.connected);
    expect(await backend.socketCount(sessionId), 1);
  });

  testWidgets("'inactive' keeps the connection", (tester) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final sessionId = await currentSessionId();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(connection(tester).status, ConnectionStatus.connected);
    expect(await backend.socketCount(sessionId), 1);
  });
}
