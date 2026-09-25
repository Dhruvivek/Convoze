import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/core/widgets/connecting_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, ConnectionStatus status) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStatusProvider.overrideWith((ref) => Stream.value(status)),
        ],
        child: const MaterialApp(home: ConnectingBanner()),
      ),
    );

void main() {
  for (final status in [
    ConnectionStatus.connecting,
    ConnectionStatus.reconnecting,
  ]) {
    testWidgets('shows while $status', (tester) async {
      await _pump(tester, status);
      await tester.pump();

      expect(find.text('Connecting…'), findsOneWidget);
    });
  }

  for (final status in [ConnectionStatus.connected, ConnectionStatus.offline]) {
    testWidgets('hides while $status', (tester) async {
      await _pump(tester, status);
      await tester.pump();

      expect(find.text('Connecting…'), findsNothing);
    });
  }
}
