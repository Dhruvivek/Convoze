import 'dart:convert';

import 'package:convoze/app.dart';
import 'package:flutter/widgets.dart';
import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/db/database_provider.dart';
import 'package:convoze/core/models/user.dart';
import 'package:convoze/core/realtime/socket_factory.dart';
import 'package:convoze/features/auth/data/auth_failure.dart';
import 'package:convoze/features/auth/data/auth_repository.dart';
import 'package:convoze/features/auth/presentation/logout_menu.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_socket_factory.dart';

class _FakeAuthRepository implements AuthRepository {
  int logouts = 0;
  AuthFailure? logoutFailure;
  int logoutOthersCalls = 0;
  AuthFailure? logoutOthersFailure;

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

  @override
  Future<void> logoutOthers() async {
    logoutOthersCalls++;
    if (logoutOthersFailure case final failure?) throw failure;
  }
}

/// Cold-starts the real app signed in as [user], with [outboxRows] already
/// seeded in the replica (#54's logout warning reads it before signing out).
Future<(_FakeAuthRepository, AppDatabase)> _launchSignedIn(
  WidgetTester tester,
  User user, {
  int outboxRows = 0,
}) async {
  FlutterSecureStorage.setMockInitialValues({
    'access_token': 'access',
    'refresh_token': 'session.secret',
    'user': jsonEncode(user.toJson()),
    'device_id': 'device-1',
  });
  final repository = _FakeAuthRepository();
  final db = AppDatabase(NativeDatabase.memory());
  for (var i = 0; i < outboxRows; i++) {
    await db.into(db.outbox).insert(
      OutboxCompanion.insert(
        clientMsgId: 'c$i',
        conversationId: 'conv-1',
        content: 'unsent $i',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(repository),
        socketFactoryProvider.overrideWithValue(fakeSocketFactory()),
        // In memory: a widget test signing in triggers a real connect(),
        // which attaches the sync engine (#51) — never touch real disk here.
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const ConvozeApp(),
    ),
  );
  await tester.pumpAndSettle();
  return (repository, db);
}

/// The Chats tab now holds a live drift stream (#52). A test that ends with
/// it still mounted must unmount it (and pump once more) itself, so its
/// debounced stream-close timer (drift: `StreamQueryStore.markAsClosed`)
/// fires inside this test's fake-async zone rather than tripping
/// flutter_test's "pending timer" check — drift's own guidance for exactly
/// this. Not needed when a test already navigates away (e.g. signs out)
/// before it ends, since `pumpAndSettle` there already flushes it.
Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

Future<void> _openMoreMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
}

Future<void> _openSettingsTab(WidgetTester tester) async {
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the display name of the signed-in User on the Settings tab', (
    tester,
  ) async {
    await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: 'Asha'),
    );

    await _openSettingsTab(tester);

    expect(find.text('Asha'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('falls back to the phone number without a display name', (tester) async {
    await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );

    await _openSettingsTab(tester);

    expect(find.text('•••• 4821'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('the overflow menu offers only Log out', (tester) async {
    await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );

    await _openMoreMenu(tester);

    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Log out other devices'), findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('logging out ends the Session and returns to login', (tester) async {
    final (repository, _) = await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );

    await _openMoreMenu(tester);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(repository.logouts, 1);
    expect(find.text('Sign in'), findsOneWidget);
    expect(await const FlutterSecureStorage().readAll(), {'device_id': 'device-1'});
  });

  testWidgets('logging out returns to login even when the server fails', (tester) async {
    final (repository, _) = await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );
    repository.logoutFailure = const AuthNetworkFailure();

    await _openMoreMenu(tester);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('logging out other devices from Settings keeps this Device signed in', (
    tester,
  ) async {
    final (repository, _) = await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );

    await _openSettingsTab(tester);
    await tester.tap(find.text('Log out other devices'));
    await tester.pumpAndSettle();

    expect(repository.logoutOthersCalls, 1);
    expect(repository.logouts, 0);
    expect(find.text('Logged out of your other devices'), findsOneWidget);
    expect(await const FlutterSecureStorage().read(key: 'refresh_token'), 'session.secret');
    await _disposeApp(tester);
  });

  testWidgets('says so when other devices could not be logged out', (tester) async {
    final (repository, _) = await _launchSignedIn(
      tester,
      const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
    );
    repository.logoutOthersFailure = const AuthNetworkFailure();

    await _openSettingsTab(tester);
    await tester.tap(find.text('Log out other devices'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't log out your other devices. Try again."), findsOneWidget);
    await _disposeApp(tester);
  });

  group('logout warning with a pending Outbox (#54)', () {
    testWidgets('warns how many unsent messages will be lost', (tester) async {
      final (repository, _) = await _launchSignedIn(
        tester,
        const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
        outboxRows: 3,
      );

      await _openMoreMenu(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('3 unsent messages will be lost.'), findsOneWidget);
      expect(repository.logouts, 0);
      expect(find.text('Conversations'), findsOneWidget);
      await _disposeApp(tester);
    });

    testWidgets('uses the singular for exactly one', (tester) async {
      await _launchSignedIn(
        tester,
        const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
        outboxRows: 1,
      );

      await _openMoreMenu(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.text('1 unsent message will be lost.'), findsOneWidget);
      await _disposeApp(tester);
    });

    testWidgets('cancelling leaves the Session and the Outbox alone', (tester) async {
      final (repository, db) = await _launchSignedIn(
        tester,
        const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
        outboxRows: 2,
      );

      await _openMoreMenu(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.logouts, 0);
      expect(find.text('Conversations'), findsOneWidget);
      expect(await db.outboxCount(), 2);
      await _disposeApp(tester);
    });

    testWidgets('confirming signs out and wipes the Outbox with everything else', (
      tester,
    ) async {
      final (repository, db) = await _launchSignedIn(
        tester,
        const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
        outboxRows: 2,
      );

      await _openMoreMenu(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(LogoutMenu.confirmLogOutKey));
      await tester.pumpAndSettle();

      expect(repository.logouts, 1);
      expect(find.text('Sign in'), findsOneWidget);
      expect(await db.outboxCount(), 0);
    });

    testWidgets('an empty Outbox skips the warning entirely', (tester) async {
      final (repository, _) = await _launchSignedIn(
        tester,
        const User(id: 'u1', phoneNumber: '+14155554821', displayName: null),
      );

      await _openMoreMenu(tester);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(repository.logouts, 1);
      expect(find.text('Sign in'), findsOneWidget);
    });
  });
}
