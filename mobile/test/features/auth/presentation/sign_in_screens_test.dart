import 'package:convoze/core/models/user.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/auth/data/auth_failure.dart';
import 'package:convoze/features/auth/data/auth_repository.dart';
import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  AuthFailure? requestFailure;
  AuthFailure? verifyFailure;
  int requests = 0;

  @override
  Future<void> requestOtp(String phoneNumber) async {
    requests++;
    if (requestFailure case final failure?) throw failure;
  }

  @override
  Future<SignInResult> verifyOtp(String phoneNumber, String code) async {
    if (verifyFailure case final failure?) throw failure;
    return SignInResult(
      accessToken: 'access',
      refreshToken: 'session.secret',
      user: User(id: 'u1', phoneNumber: phoneNumber, displayName: null),
    );
  }

  @override
  Future<void> logout() async {}
}

const _phoneNumber = '+14155550100';

late _FakeAuthRepository _repository;

Future<void> _pump(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_repository),
        tokenStoreProvider.overrideWithValue(
          TokenStore(const FlutterSecureStorage()),
        ),
      ],
      child: MaterialApp(home: screen),
    ),
  );
}

Future<void> _sendCode(WidgetTester tester) async {
  await _pump(tester, const PhoneEntryScreen());
  await tester.enterText(
    find.byKey(PhoneEntryScreen.numberFieldKey),
    '415 555 0100',
  );
  await tester.tap(find.text('Send code'));
  await tester.pump();
}

Future<void> _enterCode(WidgetTester tester) async {
  await _pump(tester, const OtpEntryScreen(phoneNumber: _phoneNumber));
  await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), '999999');
  await tester.tap(find.text('Verify'));
  await tester.pump();
}

Finder _resendButton() => find.byKey(OtpEntryScreen.resendButtonKey);

bool _resendEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(_resendButton()).onPressed != null;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    _repository = _FakeAuthRepository();
  });

  group('phone entry', () {
    final cases = <AuthFailure, String>{
      const InvalidPhoneNumber():
          "That isn't a valid phone number. Check it and try again.",
      const OtpRateLimited(): 'Too many attempts. Try again later.',
      const OtpProviderUnavailable():
          "Our SMS provider isn't responding. Try again in a few minutes.",
      const AuthNetworkFailure():
          "Couldn't reach Convoze. Check your connection and try again.",
      const UnexpectedAuthFailure(): 'Something went wrong. Try again.',
    };
    cases.forEach((failure, message) {
      testWidgets('shows "$message" for ${failure.runtimeType}', (
        tester,
      ) async {
        _repository.requestFailure = failure;

        await _sendCode(tester);

        expect(find.text(message), findsOneWidget);
      });
    });
  });

  group('code entry', () {
    testWidgets('shows an invalid-code message for a wrong code', (
      tester,
    ) async {
      _repository.verifyFailure = const InvalidOtp();

      await _enterCode(tester);

      expect(find.text('That code is wrong or has expired.'), findsOneWidget);
    });

    testWidgets('shows a provider message when codes cannot be checked', (
      tester,
    ) async {
      _repository.verifyFailure = const OtpProviderUnavailable();

      await _enterCode(tester);

      expect(
        find.text(
          "Our SMS provider isn't responding. Try again in a few minutes.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('keeps "Resend code" disabled for 30 seconds after a send', (
      tester,
    ) async {
      await _pump(tester, const OtpEntryScreen(phoneNumber: _phoneNumber));

      expect(_resendEnabled(tester), isFalse);
      expect(find.text('Resend code in 30s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 29));
      expect(_resendEnabled(tester), isFalse);
      expect(find.text('Resend code in 1s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(_resendEnabled(tester), isTrue);
      expect(find.text('Resend code'), findsOneWidget);
    });

    testWidgets('resending texts a new code and restarts the cooldown', (
      tester,
    ) async {
      await _pump(tester, const OtpEntryScreen(phoneNumber: _phoneNumber));
      await tester.pump(OtpEntryScreen.resendCooldown);

      await tester.tap(_resendButton());
      await tester.pump();

      expect(_repository.requests, 1);
      expect(_resendEnabled(tester), isFalse);
      expect(find.text('We texted you a new code.'), findsOneWidget);
    });

    testWidgets('shows a too-many-attempts message when resending is limited', (
      tester,
    ) async {
      _repository.requestFailure = const OtpRateLimited();
      await _pump(tester, const OtpEntryScreen(phoneNumber: _phoneNumber));
      await tester.pump(OtpEntryScreen.resendCooldown);

      await tester.tap(_resendButton());
      await tester.pump();

      expect(find.text('Too many attempts. Try again later.'), findsOneWidget);
    });
  });
}
