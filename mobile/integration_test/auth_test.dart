import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';

void main() {
  setUpE2e();

  testWidgets('an unauthenticated launch lands on the login screen', (
    tester,
  ) async {
    await launchApp(tester);

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('signing in with phone and code lands on conversations', (
    tester,
  ) async {
    await launchApp(tester);

    await tester.enterText(
      find.byKey(PhoneEntryScreen.countryCodeFieldKey),
      '1',
    );
    await tester.enterText(
      find.byKey(PhoneEntryScreen.numberFieldKey),
      '415 555 0100',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(find.text('We texted a code to +14155550100.'), findsOneWidget);
    await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), e2eOtpCode);
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Conversations'), findsOneWidget);
  });
}
