import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';

/// Upserts the `users` side-list (ADR 0009) every batch, snapshot page and
/// message page carries. Shared by the live sync engine and the REST
/// snapshot rebuild — it's the same shape (`USER_SELECT` on the backend)
/// either way.
Future<void> upsertUsers(AppDatabase db, List<dynamic> usersJson) async {
  for (final raw in usersJson) {
    final json = (raw as Map).cast<String, dynamic>();
    await db
        .into(db.users)
        .insertOnConflictUpdate(
          UsersCompanion.insert(
            id: json['id'] as String,
            phoneNumber: json['phoneNumber'] as String,
            displayName: Value(json['displayName'] as String?),
            avatarUrl: Value(json['avatarUrl'] as String?),
          ),
        );
  }
}

/// Applies a `messagePayload()`-shaped JSON object (`backend/src/messaging/messagePayload.js`)
/// — used for `message.new`/`message.edited` Updates, REST history pages,
/// and a Conversation row's `lastMessage`. `messagePayload()` itself can
/// return either the full shape or a bare tombstone (`{id, conversationId,
/// isDeleted: true}`) when the Message was deleted before this hydrated, so
/// both are handled the same way here as an explicit `message.deleted`
/// Update: an UPDATE, never an INSERT, so a payload missing `senderId` (the
/// tombstone shape) never trips the column's NOT NULL constraint, and a
/// delete never leaks previously-stored content past this point either.
Future<void> upsertMessagePayload(AppDatabase db, Map<String, dynamic> payload) async {
  final id = payload['id'] as String;
  final isDeleted = payload['isDeleted'] as bool? ?? false;
  if (isDeleted) {
    await (db.update(db.messages)..where((t) => t.id.equals(id))).write(
      const MessagesCompanion(
        isDeleted: Value(true),
        content: Value(null),
        linkPreview: Value(null),
      ),
    );
    return;
  }

  final linkPreview = payload['linkPreview'];
  await db
      .into(db.messages)
      .insertOnConflictUpdate(
        MessagesCompanion.insert(
          id: id,
          conversationId: payload['conversationId'] as String,
          senderId: payload['senderId'] as String,
          clientMsgId: Value(payload['clientMsgId'] as String?),
          replyToMessageId: Value(payload['replyToMessageId'] as String?),
          linkPreview: Value(linkPreview == null ? null : jsonEncode(linkPreview)),
          type: Value(payload['type'] as String? ?? 'text'),
          content: Value(payload['content'] as String?),
          createdAt: DateTime.parse(payload['createdAt'] as String),
          editedAt: Value(
            payload['editedAt'] == null ? null : DateTime.parse(payload['editedAt'] as String),
          ),
          isDeleted: const Value(false),
          // `reactions` is left absent on purpose: it isn't part of
          // `messagePayload()`, only `reaction.changed` carries it, and
          // `insertOnConflictUpdate` skips absent columns in its UPDATE, so
          // an edit never clobbers reactions already applied.
        ),
      );
}

/// Upserts a Conversation REST row (`GET /conversations`'s per-item shape,
/// also `POST /conversations/direct`'s response minus the fields it doesn't
/// carry) — its own fields, its `lastMessage` if any, and every Participant
/// referenced by it. Shared by the REST snapshot rebuild and
/// `ConversationsRepository.openDirect`, which is the same shape either way.
Future<void> upsertConversationRow(AppDatabase db, Map<String, dynamic> json) async {
  final id = json['id'] as String;
  await db
      .into(db.conversations)
      .insertOnConflictUpdate(
        ConversationsCompanion.insert(
          id: id,
          type: json['type'] as String,
          name: Value(json['name'] as String?),
          unreadCount: Value(json['unreadCount'] as int? ?? 0),
          left: Value(json['left'] as bool? ?? false),
          pinnedAt: Value(_parseNullableDate(json['pinnedAt'])),
          archivedAt: Value(_parseNullableDate(json['archivedAt'])),
          mutedUntil: Value(_parseNullableDate(json['mutedUntil'])),
          hiddenAt: Value(_parseNullableDate(json['hiddenAt'])),
          historyClearedMessageId: Value(json['historyClearedMessageId'] as String?),
        ),
      );

  final lastMessage = json['lastMessage'];
  if (lastMessage != null) {
    await upsertMessagePayload(db, (lastMessage as Map).cast<String, dynamic>());
  }

  final roles = <String, String>{
    for (final p in (json['participants'] as List))
      (p as Map)['userId'] as String: p['role'] as String,
  };
  final readWatermarks = <String, String?>{
    for (final w in (json['readWatermarks'] as List? ?? const []))
      (w as Map)['userId'] as String: w['messageId'] as String?,
  };
  final deliveryWatermarks = <String, String?>{
    for (final w in (json['deliveryWatermarks'] as List? ?? const []))
      (w as Map)['userId'] as String: w['messageId'] as String?,
  };

  for (final userId in roles.keys) {
    await db
        .into(db.participants)
        .insertOnConflictUpdate(
          ParticipantsCompanion.insert(
            conversationId: id,
            userId: userId,
            role: Value(roles[userId]!),
            lastReadMessageId: Value(readWatermarks[userId]),
            lastDeliveredMessageId: Value(deliveryWatermarks[userId]),
          ),
        );
  }
}

DateTime? _parseNullableDate(dynamic value) =>
    value == null ? null : DateTime.parse(value as String);

/// Applies a `conversation.prefs` Update's payload (#45,
/// `hydrateConversationForUser()` on the backend): the five Conversation
/// preference fields (never derived locally, mirrored straight from the
/// caller's own Participant row), plus `unreadCount` when the payload
/// carries one (clearing history can change it). Also used by
/// `ConversationsRepository`/`ConversationPrefsRepository` to apply a REST
/// response the same way a live Update would.
Future<void> applyConversationPrefs(AppDatabase db, Map<String, dynamic> payload) async {
  final id = payload['id'] as String;
  await (db.update(db.conversations)..where((t) => t.id.equals(id))).write(
    ConversationsCompanion(
      pinnedAt: Value(_parseNullableDate(payload['pinnedAt'])),
      archivedAt: Value(_parseNullableDate(payload['archivedAt'])),
      mutedUntil: Value(_parseNullableDate(payload['mutedUntil'])),
      hiddenAt: Value(_parseNullableDate(payload['hiddenAt'])),
      historyClearedMessageId: Value(payload['historyClearedMessageId'] as String?),
      unreadCount: payload.containsKey('unreadCount')
          ? Value(payload['unreadCount'] as int)
          : const Value.absent(),
    ),
  );

  final clearedId = payload['historyClearedMessageId'] as String?;
  if (clearedId != null) {
    // Raw SQL: drift's typed comparators don't do `<=` on a TextColumn, and
    // UUIDv7 ids already sort chronologically as text everywhere else this
    // codebase compares them (mirrors `_incrementUnread`'s use of
    // `customStatement` for the same reason).
    await db.customStatement('DELETE FROM messages WHERE conversation_id = ? AND id <= ?', [
      id,
      clearedId,
    ]);
  }
}
