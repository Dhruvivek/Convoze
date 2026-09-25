import 'dart:convert';

import 'package:convoze/app.dart';
import 'package:convoze/core/models/user.dart';
import 'package:convoze/features/auth/data/auth_failure.dart';
import 'package:convoze/features/auth/data/auth_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  int logouts = 0;
  AuthFailure? logoutFailure;

  @override
  Future<void> requestOtp(String phoneNumber) async {}

  @override
  Future<SignInResult> verifyOtp(String phoneNumber, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {
    logouts++;
    if (logoutFailure case final failure?) throw failure;
  }
}

/// Cold-starts the real app signed in as [user].
Future<_FakeAuthRepository> _launchSignedIn(
  WidgetTester tester,
  User user,
) async {
  FlutterSecureStorage.setMockInitialValues({
    'access_token': 'access',
    'refresh_token': 'session.secret',
    'user': jsonEncode(user.toJson()),
    'device_id': 'device-1',
  });
  final repository = _FakeAuthRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
      child: const ConvozeApp(),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _openAccountMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Account'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the display name of the signed-in User', (tester) async {
    await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: 'Asha'),
    );

    await _openAccountMenu(tester);

    expect(find.text('Asha'), findsOneWidget);
  });

  testWidgets('falls back to the phone number without a display name', (
    tester,
  ) async {
    await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );

    await _openAccountMenu(tester);

    expect(find.text('•••• 4821'), findsOneWidget);
  });

  testWidgets('logging out ends the Session and returns to login', (
    tester,
  ) async {
    final repository = await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );

    await _openAccountMenu(tester);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(repository.logouts, 1);
    expect(find.text('Sign in'), findsOneWidget);
    expect(await const FlutterSecureStorage().readAll(), {
      'device_id': 'device-1',
    });
  });

  testWidgets('logging out returns to login even when the server fails', (
    tester,
  ) async {
    final repository = await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );
    repository.logoutFailure = const AuthNetworkFailure();

    await _openAccountMenu(tester);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });
}
