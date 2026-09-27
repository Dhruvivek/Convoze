import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/profile/data/profile_repository.dart';
import 'package:convoze/features/profile/presentation/profile_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const me = 'user-me';

/// Answers a `GET`/`PATCH`/`PUT`/`DELETE` on `/users/me...` with whatever
/// [respond] returns for that method — the screen's own initial `GET
/// /users/me` (via `refreshMe` on open) and a later `PATCH` need different
/// bodies, unlike the other repository tests' single fixed response.
class _MethodAwareAdapter implements HttpClientAdapter {
  _MethodAwareAdapter(this.respond);

  final Map<String, dynamic> Function(String method) respond;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(respond(options.method)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _profile({String? displayName, String? about}) => {
  'id': me,
  'phoneNumber': '+14155550100',
  'displayName': displayName,
  'about': about,
  'avatarUrl': null,
};

/// Drift's watched-query cancellation schedules a zero-duration `Timer`
/// during widget disposal; the test framework's own automatic teardown
/// disposes the tree but never pumps again afterwards, so that timer trips
/// `!timersPending`. Disposing explicitly, then pumping once more, lets it
/// fire before the test ends (same helper `chat_thread_screen_test.dart` uses).
Future<void> _disposeCleanly(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'refresh_token': 'rt',
      'user': '{"id":"$me","phoneNumber":"+14155550100","displayName":"Old name"}',
    });
  });

  Widget buildScreen(ProfileRepository repo, {ConnectionStatus status = ConnectionStatus.connected}) {
    return ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        connectionStatusProvider.overrideWith((ref) => Stream.value(status)),
      ],
      child: const MaterialApp(
        home: Scaffold(body: ProfileScreen(embedded: true)),
      ),
    );
  }

  testWidgets('shows the replica\'s current name/about, edits and saves both', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = _MethodAwareAdapter(
      (method) => method == 'PATCH'
          ? _profile(displayName: 'New name', about: 'New about')
          : _profile(displayName: 'Old name', about: 'Old about'),
    );
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    final repo = ProfileRepository(dio, db);

    await tester.pumpWidget(buildScreen(repo));
    await tester.pumpAndSettle();

    expect(find.text('Old name'), findsOneWidget);
    expect(find.text('Old about'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Display name'), 'New name');
    await tester.enterText(find.widgetWithText(TextField, 'About'), 'New about');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/users/me');
    expect(adapter.lastRequest!.data, {'displayName': 'New name', 'about': 'New about'});
    expect(find.text('Profile updated'), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets('disables editing and shows a hint while offline', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final adapter = _MethodAwareAdapter((_) => _profile(displayName: 'Old name'));
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    final repo = ProfileRepository(dio, db);

    await tester.pumpWidget(buildScreen(repo, status: ConnectionStatus.offline));
    await tester.pumpAndSettle();

    expect(find.text('Needs a connection to save changes.'), findsOneWidget);
    final nameField = tester.widget<TextField>(find.widgetWithText(TextField, 'Display name'));
    expect(nameField.enabled, false);
    final saveButton = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(saveButton.onPressed, isNull);

    await _disposeCleanly(tester);
  });
}
