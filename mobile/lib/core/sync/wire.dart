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
