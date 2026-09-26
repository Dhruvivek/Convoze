import 'dart:convert';

import 'package:convoze/app.dart';
import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/db/database_provider.dart';
import 'package:convoze/core/models/user.dart';
import 'package:convoze/core/realtime/socket_factory.dart';
import 'package:convoze/features/auth/data/auth_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_socket_factory.dart';

const me = 'me-1';

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<void> requestOtp(String phoneNumber) async {}

  @override
  Future<SignInResult> verifyOtp(String phoneNumber, String code) =>
      throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> logoutOthers() async {}
}

/// Cold-starts the real app signed in as [me], over an in-memory replica
/// this test can seed directly.
Future<AppDatabase> _launchSignedIn(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({
    'access_token': 'access',
    'refresh_token': 'session.secret',
    'user': jsonEncode(
      const User(id: me, phoneNumber: '+14155550100', displayName: 'Me').toJson(),
    ),
    'device_id': 'device-1',
  });
  final db = AppDatabase(NativeDatabase.memory());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        socketFactoryProvider.overrideWithValue(fakeSocketFactory()),
        appDatabaseProvider.overrideWithValue(db),
      ],
      child: const ConvozeApp(),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

Future<void> _seedConversation(
  AppDatabase db, {
  required String id,
  required String otherUserId,
  required String otherDisplayName,
  int unreadCount = 0,
  bool left = false,
  DateTime? pinnedAt,
  String? lastMessage,
  String? lastSenderId,
  DateTime? lastMessageAt,
}) async {
  await db
      .into(db.users)
      .insertOnConflictUpdate(UsersCompanion.insert(id: me, phoneNumber: '+14155550100'));
  await db
      .into(db.users)
      .insertOnConflictUpdate(
        UsersCompanion.insert(
          id: otherUserId,
          phoneNumber: '+14155550101',
          displayName: Value(otherDisplayName),
        ),
      );
  await db
      .into(db.conversations)
      .insert(
        ConversationsCompanion.insert(
          id: id,
          type: 'direct',
          unreadCount: Value(unreadCount),
          left: Value(left),
          pinnedAt: Value(pinnedAt),
        ),
      );
  await db.into(db.participants).insert(ParticipantsCompanion.insert(conversationId: id, userId: me));
  await db
      .into(db.participants)
      .insert(ParticipantsCompanion.insert(conversationId: id, userId: otherUserId));
  if (lastMessage != null) {
    await db
        .into(db.messages)
        .insert(
          MessagesCompanion.insert(
            id: '$id-msg',
            conversationId: id,
            senderId: lastSenderId ?? otherUserId,
            content: Value(lastMessage),
            createdAt: lastMessageAt ?? DateTime.utc(2026, 1, 1),
          ),
        );
  }
}

void main() {
  testWidgets('shows "No chats yet" with a New chat button when there are none', (tester) async {
    await _launchSignedIn(tester);

    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New chat'), findsOneWidget);
    await _disposeApp(tester);
  });

  testWidgets('shows pinned conversations first, then by last activity, and dims a left one', (
    tester,
  ) async {
    final db = await _launchSignedIn(tester);

    await _seedConversation(
      db,
      id: 'conv-old',
      otherUserId: 'u-old',
      otherDisplayName: 'Old Chat',
      lastMessage: 'ages ago',
      lastMessageAt: DateTime.utc(2026, 1, 1),
    );
    await _seedConversation(
      db,
      id: 'conv-new',
      otherUserId: 'u-new',
      otherDisplayName: 'New Chat',
      unreadCount: 3,
      lastMessage: 'just now',
      lastMessageAt: DateTime.utc(2026, 1, 2),
    );
    await _seedConversation(
      db,
      id: 'conv-pinned',
      otherUserId: 'u-pinned',
      otherDisplayName: 'Pinned Chat',
      pinnedAt: DateTime.utc(2025, 1, 1),
      lastMessage: 'pinned message',
      lastMessageAt: DateTime.utc(2025, 6, 1),
    );
    await _seedConversation(
      db,
      id: 'conv-left',
      otherUserId: 'u-left',
      otherDisplayName: 'Left Chat',
      left: true,
      lastMessage: 'they left',
      lastMessageAt: DateTime.utc(2025, 12, 1),
    );
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<Text>(find.descendant(of: find.byType(ListView), matching: find.byType(Text)))
        .map((t) => t.data)
        .whereType<String>()
        .where((text) => text.endsWith(' Chat'))
        .toList();
    expect(titles, ['Pinned Chat', 'New Chat', 'Old Chat', 'Left Chat']);

    final dimmed = tester.widget<Opacity>(
      find.ancestor(of: find.text('Left Chat'), matching: find.byType(Opacity)).first,
    );
    expect(dimmed.opacity, 0.5);

    await _disposeApp(tester);
  });
}
