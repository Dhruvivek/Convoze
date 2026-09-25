import 'package:convoze/app.dart';
import 'package:convoze/core/network/dio_provider.dart';
import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart' show sessionIdOf;

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

/// The app's own API client, so calls go through its auth interceptor.
Dio _api(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConvozeApp)))
        .read(dioProvider);

/// A protected call, like any screen would make.
Future<Response<Map<String, dynamic>>> _echo(WidgetTester tester) =>
    _api(tester).get<Map<String, dynamic>>('/__e2e__/echo');

Future<String> _sessionId() async =>
    sessionIdOf((await _storage.read(key: 'access_token'))!);

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

void main() {
  setUpE2e();

  testWidgets('a call after the access token expires succeeds unnoticed', (
    tester,
  ) async {
    await backend.setTokenTtls(accessTokenSeconds: 1);
    await launchApp(tester);
    await _signIn(tester);
    final sessionId = await _sessionId();

    await _wait(const Duration(seconds: 2));
    final res = await _echo(tester);
    await tester.pumpAndSettle();

    expect(res.statusCode, 200);
    expect(res.data!['sessionId'], sessionId);
    expect(await backend.refreshCount(sessionId), 1);
    expect(find.text('Conversations'), findsOneWidget);
  });

  testWidgets('parallel calls after expiry cause exactly one refresh', (
    tester,
  ) async {
    await backend.setTokenTtls(accessTokenSeconds: 1);
    await launchApp(tester);
    await _signIn(tester);
    final sessionId = await _sessionId();

    await _wait(const Duration(seconds: 2));
    final responses = await Future.wait([
      for (var i = 0; i < 5; i++) _echo(tester),
    ]);

    expect(responses.map((r) => r.statusCode), everyElement(200));
    expect(await backend.refreshCount(sessionId), 1);
  });

  testWidgets(
    'once the refresh token has expired, the next call lands on login',
    (tester) async {
      await backend.setTokenTtls(accessTokenSeconds: 1, refreshTokenSeconds: 2);
      await launchApp(tester);
      await _signIn(tester);
      final deviceId = await _storage.read(key: 'device_id');

      await _wait(const Duration(seconds: 3));
      await expectLater(_echo(tester), throwsA(isA<DioException>()));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(await _storage.read(key: 'access_token'), isNull);
      expect(await _storage.read(key: 'refresh_token'), isNull);
      expect(await _storage.read(key: 'device_id'), deviceId);
    },
  );
}
