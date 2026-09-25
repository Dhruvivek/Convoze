import 'package:convoze/app.dart';
import 'package:convoze/core/network/dio_provider.dart';
import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';

const _storage = FlutterSecureStorage();
const _phoneNumber = '+14155550100';

Future<void> _signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(PhoneEntryScreen.countryCodeFieldKey), '1');
  await tester.enterText(
    find.byKey(PhoneEntryScreen.numberFieldKey),
    '415 555 0100',
  );
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), e2eOtpCode);
  await tester.tap(find.text('Verify'));
  await tester.pumpAndSettle();
  expect(find.text('Conversations'), findsOneWidget);
}

Future<void> _tapInAccountMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) fail('$finder did not show');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// A protected call through the app's own API client, like any screen would
/// make.
Future<Response<Map<String, dynamic>>> _echo(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConvozeApp)))
        .read(dioProvider)
        .get<Map<String, dynamic>>('/__e2e__/echo');

void main() {
  setUpE2e();

  final others = <OtherDevice>[];
  tearDown(() {
    for (final other in others) {
      other.dispose();
    }
    others.clear();
  });

  Future<OtherDevice> signInElsewhere() async {
    final other = await OtherDevice.signIn(_phoneNumber);
    others.add(other);
    return other;
  }

  testWidgets(
    '"Log out other devices" ends the other Session and keeps this one',
    (tester) async {
      await launchApp(tester);
      await _signIn(tester);
      final other = await signInElsewhere();

      await _tapInAccountMenu(tester, 'Log out other devices');
      // The call isn't awaited by the tap; its snackbar says it has finished.
      await _pumpUntil(tester, find.text('Logged out of your other devices'));

      expect(await other.echoStatus(), 401);
      expect(await backend.refreshStatus(other.refreshToken), 401);
      expect((await _echo(tester)).statusCode, 200);
      await tester.pumpAndSettle();
      expect(find.text('Conversations'), findsOneWidget);
    },
  );

  testWidgets(
    'when another Device logs this one out, the next call lands on login',
    (tester) async {
      await launchApp(tester);
      await _signIn(tester);
      final deviceId = await _storage.read(key: 'device_id');
      final other = await signInElsewhere();

      expect(await other.logoutOthers(), 204);
      await expectLater(_echo(tester), throwsA(isA<DioException>()));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(await _storage.read(key: 'refresh_token'), isNull);
      expect(await _storage.read(key: 'device_id'), deviceId);
    },
  );

  testWidgets(
    "signing in again on this Device rejects its previous refresh token",
    (tester) async {
      await launchApp(tester);
      await _signIn(tester);
      final previousRefreshToken = (await _storage.read(key: 'refresh_token'))!;
      // The Device loses its Session without the server hearing of it (e.g.
      // its secure storage was wiped), but keeps its Device ID.
      for (final key in ['access_token', 'refresh_token', 'user']) {
        await _storage.delete(key: key);
      }
      await launchApp(tester);

      await _signIn(tester);

      expect(await backend.refreshStatus(previousRefreshToken), 401);
      expect((await _echo(tester)).statusCode, 200);
    },
  );

  testWidgets('the Device ID is unchanged after logout and sign-in', (
    tester,
  ) async {
    await launchApp(tester);
    await _signIn(tester);
    final deviceId = await _storage.read(key: 'device_id');

    await _tapInAccountMenu(tester, 'Log out');
    await _signIn(tester);

    expect(deviceId, isNotNull);
    expect(await _storage.read(key: 'device_id'), deviceId);
  });
}
