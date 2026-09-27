import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/conversations/data/conversations_repository.dart';
import 'package:convoze/features/presence/data/presence_providers.dart';
import 'package:convoze/features/profile/data/profile_repository.dart';
import 'package:convoze/features/profile/presentation/user_profile_screen.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const otherUserId = 'user-other';

class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this._body);

  final Map<String, dynamic> _body;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(_body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _disposeCleanly(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  Widget buildScreen({
    required ProfileRepository profileRepository,
    required ConversationsRepository conversationsRepository,
  }) {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (context, state) => const UserProfileScreen(userId: otherUserId)),
        GoRoute(
          path: '/thread/:id',
          builder: (context, state) => Text('Thread ${state.pathParameters['id']}'),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        profileRepositoryProvider.overrideWithValue(profileRepository),
        conversationsRepositoryProvider.overrideWithValue(conversationsRepository),
        presenceMapProvider.overrideWith((ref) => Stream.value(const {})),
        connectionStatusProvider.overrideWith((ref) => Stream.value(ConnectionStatus.connected)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets('shows the fetched profile: name, about and phone number', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
      ..httpClientAdapter = _FixedAdapter({
        'id': otherUserId,
        'phoneNumber': '+14155550199',
        'displayName': 'Bob',
        'about': 'Out for lunch',
        'avatarUrl': null,
      });
    final profileRepo = ProfileRepository(dio, db);
    final conversationsRepo = ConversationsRepository(dio, db);

    await tester.pumpWidget(buildScreen(profileRepository: profileRepo, conversationsRepository: conversationsRepo));
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Out for lunch'), findsOneWidget);
    expect(find.text('+14155550199'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Message'), findsOneWidget);

    await _disposeCleanly(tester);
  });

  testWidgets('Message opens (or creates) the direct chat and navigates to it', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final profileDio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
      ..httpClientAdapter = _FixedAdapter({
        'id': otherUserId,
        'phoneNumber': '+14155550199',
        'displayName': 'Bob',
        'about': null,
        'avatarUrl': null,
      });
    final profileRepo = ProfileRepository(profileDio, db);

    final conversationsDio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
      ..httpClientAdapter = _FixedAdapter({
        'id': 'conv-1',
        'type': 'direct',
        'name': null,
        'unreadCount': 0,
        'left': false,
        'participants': [
          {'userId': otherUserId, 'role': 'member'},
        ],
        'lastMessage': null,
        'readWatermarks': <dynamic>[],
        'deliveryWatermarks': <dynamic>[],
        'users': <dynamic>[],
      });
    final conversationsRepo = ConversationsRepository(conversationsDio, db);

    await tester.pumpWidget(buildScreen(profileRepository: profileRepo, conversationsRepository: conversationsRepo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Message'));
    await tester.pumpAndSettle();

    expect(find.text('Thread conv-1'), findsOneWidget);

    await _disposeCleanly(tester);
  });
}
