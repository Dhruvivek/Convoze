import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'wire.dart';

const _topPrefetchCount = 10;
const _pageSize = 50;

/// Rebuilds the replica from a REST snapshot (ADR 0009's "shallow snapshot",
/// amending ADR 0008): the paged Conversation list in full, then the first
/// message page for the top [_topPrefetchCount] conversations by activity —
/// not "the latest page per conversation" for every one of them, which would
/// cost one request per Conversation before the app is usable. Called for
/// both `sync:reset` and a schema-version bump (the same wipe-and-rebuild
/// path, ADR 0009), always against an already-wiped replica.
Future<void> rebuildSnapshotFromRest({
  required Dio dio,
  required AppDatabase db,
  required int currentSeq,
}) async {
  final conversationIds = <String>[];
  String? cursor;
  do {
    final res = await dio.get<Map<String, dynamic>>(
      '/conversations',
      queryParameters: {'limit': _pageSize, 'cursor': ?cursor},
    );
    final body = res.data!;
    await upsertUsers(db, (body['users'] as List?) ?? const []);
    for (final raw in (body['conversations'] as List)) {
      final json = (raw as Map).cast<String, dynamic>();
      await _upsertConversationRow(db, json);
      conversationIds.add(json['id'] as String);
    }
    cursor = body['nextCursor'] as String?;
  } while (cursor != null);

  for (final conversationId in conversationIds.take(_topPrefetchCount)) {
    final res = await dio.get<Map<String, dynamic>>(
      '/conversations/$conversationId/messages',
      queryParameters: {'limit': _pageSize},
    );
    final body = res.data!;
    await upsertUsers(db, (body['users'] as List?) ?? const []);
    for (final raw in (body['messages'] as List)) {
      await upsertMessagePayload(db, (raw as Map).cast<String, dynamic>());
    }
  }

  await db.writeCursor(currentSeq);
}

Future<void> _upsertConversationRow(AppDatabase db, Map<String, dynamic> json) async {
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
