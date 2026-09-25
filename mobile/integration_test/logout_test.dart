import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';

const _storage = FlutterSecureStorage();

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

Future<void> _openAccountMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Account'));
  await tester.pumpAndSettle();
}

Future<void> _logOut(WidgetTester tester) async {
  await _openAccountMenu(tester);
  await tester.tap(find.text('Log out'));
  await tester.pumpAndSettle();
}

void main() {
  setUpE2e();

  testWidgets('logging out returns to login and ends the Session', (
    tester,
  ) async {
    await launchApp(tester);
    await _signIn(tester);
    final refreshToken = (await _storage.read(key: 'refresh_token'))!;
    final deviceId = await _storage.read(key: 'device_id');

    await _logOut(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(await backend.refreshStatus(refreshToken), 401);
    expect(await _storage.read(key: 'access_token'), isNull);
    expect(await _storage.read(key: 'refresh_token'), isNull);
    expect(await _storage.read(key: 'device_id'), deviceId);
  });

  testWidgets('logging out returns to login even when the server fails', (
    tester,
  ) async {
    await launchApp(tester);
    await _signIn(tester);
    final deviceId = await _storage.read(key: 'device_id');
    await backend.failNext('POST', '/auth/logout');

    await _logOut(tester);

    expect(find.text('Sign in'), findsOneWidget);
    expect(await _storage.read(key: 'access_token'), isNull);
    expect(await _storage.read(key: 'refresh_token'), isNull);
    expect(await _storage.read(key: 'device_id'), deviceId);
  });

  testWidgets('a new user sees their phone number in the account menu', (
    tester,
  ) async {
    await launchApp(tester);
    await _signIn(tester);

    await _openAccountMenu(tester);

    expect(find.text('•••• 0100'), findsOneWidget);
  });
}
