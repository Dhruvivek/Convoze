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
}
