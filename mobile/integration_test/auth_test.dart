import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';

Future<void> _sendCode(WidgetTester tester, String number) async {
  await tester.enterText(find.byKey(PhoneEntryScreen.countryCodeFieldKey), '1');
  await tester.enterText(find.byKey(PhoneEntryScreen.numberFieldKey), number);
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

Future<void> _signIn(WidgetTester tester) async {
  await _sendCode(tester, '415 555 0100');
  await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), e2eOtpCode);
  await tester.tap(find.text('Verify'));
  await tester.pumpAndSettle();
}

void main() {
  setUpE2e();

  testWidgets('a launch with empty storage lands on the login screen', (
    tester,
  ) async {
    await launchApp(tester);

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('a restart after signing in goes straight to conversations', (
    tester,
  ) async {
    await launchApp(tester);
    await _signIn(tester);
    expect(find.text('Conversations'), findsOneWidget);

    await launchAppUntil(
      tester,
      find.text('Conversations'),
      mustNotShow: find.text('Sign in'),
    );
  });

  testWidgets('signing in with phone and code lands on conversations', (
    tester,
  ) async {
    await launchApp(tester);

    await _sendCode(tester, '415 555 0100');

    expect(find.text('We texted a code to +14155550100.'), findsOneWidget);
    await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), e2eOtpCode);
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Conversations'), findsOneWidget);
  });

  testWidgets('an invalid phone number shows an invalid-number error', (
    tester,
  ) async {
    await launchApp(tester);

    await _sendCode(tester, '555');

    expect(
      find.text("That isn't a valid phone number. Check it and try again."),
      findsOneWidget,
    );
  });

  testWidgets('a fourth code request within 15 minutes is rate limited', (
    tester,
  ) async {
    for (var i = 0; i < 3; i++) {
      await backend.requestOtp('+14155550100');
    }
    await launchApp(tester);

    await _sendCode(tester, '415 555 0100');

    expect(find.text('Too many attempts. Try again later.'), findsOneWidget);
  });

  testWidgets('a wrong code shows an invalid-code error', (tester) async {
    await launchApp(tester);
    await _sendCode(tester, '415 555 0100');

    final wrongCode = e2eOtpCode == '999999' ? '111111' : '999999';
    await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), wrongCode);
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('That code is wrong or has expired.'), findsOneWidget);
  });

  testWidgets('an SMS provider outage shows a provider-unavailable error', (
    tester,
  ) async {
    await backend.failNext(
      'POST',
      '/auth/otp/request',
      status: 502,
      code: 'otp_provider_unavailable',
    );
    await launchApp(tester);

    await _sendCode(tester, '415 555 0100');

    expect(
      find.text(
        "Our SMS provider isn't responding. Try again in a few minutes.",
      ),
      findsOneWidget,
    );
  });
}
