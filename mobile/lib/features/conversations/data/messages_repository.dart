import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import '../../../core/db/database.dart';
import '../../../core/db/database_provider.dart';
import '../../auth/presentation/auth_state.dart';
import 'local_chat_message.dart';
import 'media_repository.dart';
import 'message_action_failure.dart';

part 'messages_repository.g.dart';

/// A photo or a document — the two kinds this reduced-scope pass of #40
/// sends (video is out of scope).
enum MediaKind {
  image('image'),
  file('file');

  const MediaKind(this.wireName);

  final String wireName;
}

/// Sending and reading a chat thread's messages: real (unlike the mock
/// `mock_thread.dart` this replaces), but deliberately minimal — no read
/// receipts, no history pagination beyond what `rest_snapshot.dart` already
/// rebuilds, no react wiring. `sendText`/`sendMedia` insert into the
/// `Outbox`; the already-real `SyncEngine.drainOutbox` (#51) does the rest.
/// `editMessage`/`deleteMessage` (#56) go straight over the socket instead.
class MessagesRepository {
  MessagesRepository(this._db);

  final AppDatabase _db;

  Future<void> sendText(String conversationId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return Future.value();
    return _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientMsgId: const Uuid().v4(),
            conversationId: conversationId,
            content: trimmed,
            type: const Value('text'),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Edits [messageId] (the sender's own, still-plain-text Message) via a
  /// direct `message:edit` ack (#56) — not queued in the Outbox, the same
  /// reasoning as `ConversationPrefsRepository`: there's no offline case to
  /// resume, only one to refuse (see `ensureConnected`). The local replica
  /// isn't touched here; the `message.edited` Update this fans out echoes
  /// back and applies through the usual sync path, sender included.
  Future<void> editMessage(
    io.Socket socket, {
    required String messageId,
    required String content,
  }) async {
    final response = await _emitForAck(socket, 'message:edit', {
      'messageId': messageId,
      'content': content.trim(),
    });
    if (response['ok'] != true) {
      throw MessageActionFailure.fromCode(response['code'] as String?);
    }
  }

  /// Deletes [messageId] (the sender's own Message) via a direct
  /// `message:delete` ack (#56) — see [editMessage].
  Future<void> deleteMessage(io.Socket socket, {required String messageId}) async {
    final response = await _emitForAck(socket, 'message:delete', {'messageId': messageId});
    if (response['ok'] != true) {
      throw MessageActionFailure.fromCode(response['code'] as String?);
    }
  }

  Future<Map<String, dynamic>> _emitForAck(
    io.Socket socket,
    String event,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await socket.timeout(15000).emitWithAckAsync(event, data);
      return (response as Map).cast<String, dynamic>();
    } catch (_) {
      throw const MessageActionNetworkFailure();
    }
  }

  Future<void> sendMedia(
    String conversationId, {
    required MediaKind kind,
    required CloudinaryUploadResult upload,
    String? caption,
    String? fileName,
  }) {
    return _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            clientMsgId: const Uuid().v4(),
            conversationId: conversationId,
            content: caption?.trim() ?? '',
            type: Value(kind.wireName),
            media: Value(jsonEncode(upload.toJson(fileName: fileName))),
            createdAt: DateTime.now(),
          ),
        );
  }

  /// Every real Message plus any not-yet-drained Outbox row for
  /// [conversationId], oldest first — a `UNION ALL` (mirroring
  /// `ConversationsRepository.watchList`'s raw-SQL join for the same reason:
  /// this isn't expressible comfortably with drift's type-safe builder) so a
  /// sent message shows immediately, then is replaced by its real row once
  /// the drainer's `message.new` echo lands and deletes the Outbox row.
  /// `json_extract` reads the media fields an Outbox row keeps as JSON.
  Stream<List<LocalChatMessage>> watchMessages(String conversationId, {required String myUserId}) {
    final query = _db.customSelect(
      '''
      SELECT
        m.id AS id, m.client_msg_id AS client_msg_id, m.sender_id AS sender_id,
        m.content AS content, m.type AS type, m.is_deleted AS is_deleted,
        m.created_at AS created_at, m.edited_at AS edited_at,
        m.media_public_id AS media_public_id, m.media_resource_type AS media_resource_type,
        m.media_bytes AS media_bytes, m.media_width AS media_width, m.media_height AS media_height,
        m.media_format AS media_format, m.media_file_name AS media_file_name,
        m.media_url AS media_url, m.media_thumbnail_url AS media_thumbnail_url,
        0 AS is_pending, 0 AS is_failed
      FROM messages m
      WHERE m.conversation_id = ?1
      UNION ALL
      SELECT
        NULL AS id, o.client_msg_id AS client_msg_id, ?2 AS sender_id,
        o.content AS content, o.type AS type, 0 AS is_deleted,
        o.created_at AS created_at, NULL AS edited_at,
        json_extract(o.media, '\$.publicId') AS media_public_id,
        json_extract(o.media, '\$.resourceType') AS media_resource_type,
        json_extract(o.media, '\$.bytes') AS media_bytes,
        json_extract(o.media, '\$.width') AS media_width,
        json_extract(o.media, '\$.height') AS media_height,
        json_extract(o.media, '\$.format') AS media_format,
        json_extract(o.media, '\$.fileName') AS media_file_name,
        NULL AS media_url, NULL AS media_thumbnail_url,
        CASE WHEN o.status = 'failed' THEN 0 ELSE 1 END AS is_pending,
        CASE WHEN o.status = 'failed' THEN 1 ELSE 0 END AS is_failed
      FROM outbox o
      WHERE o.conversation_id = ?1
        AND NOT EXISTS (SELECT 1 FROM messages m2 WHERE m2.client_msg_id = o.client_msg_id)
      ORDER BY created_at ASC
      ''',
      variables: [Variable.withString(conversationId), Variable.withString(myUserId)],
      readsFrom: {_db.messages, _db.outbox},
    );
    return query.watch().map((rows) => rows.map((row) => _toMessage(row, myUserId)).toList());
  }

  LocalChatMessage _toMessage(QueryRow row, String myUserId) {
    final senderId = row.read<String>('sender_id');
    return LocalChatMessage(
      id: row.read<String?>('id'),
      clientMsgId: row.read<String?>('client_msg_id'),
      senderIsMe: senderId == myUserId,
      content: row.read<String?>('content'),
      type: row.read<String>('type'),
      isDeleted: row.read<bool>('is_deleted'),
      createdAt: row.read<DateTime>('created_at'),
      editedAt: row.read<DateTime?>('edited_at'),
      isPending: row.read<bool>('is_pending'),
      isFailed: row.read<bool>('is_failed'),
      mediaPublicId: row.read<String?>('media_public_id'),
      mediaResourceType: row.read<String?>('media_resource_type'),
      mediaBytes: row.read<int?>('media_bytes'),
      mediaWidth: row.read<int?>('media_width'),
      mediaHeight: row.read<int?>('media_height'),
      mediaFormat: row.read<String?>('media_format'),
      mediaFileName: row.read<String?>('media_file_name'),
      mediaUrl: row.read<String?>('media_url'),
      mediaThumbnailUrl: row.read<String?>('media_thumbnail_url'),
    );
  }
}

@Riverpod(keepAlive: true)
MessagesRepository messagesRepository(Ref ref) =>
    MessagesRepository(ref.watch(appDatabaseProvider));

/// The live thread for [conversationId] — empty (rather than an error) while
/// signed out, same reasoning as `conversationList`.
@riverpod
Stream<List<LocalChatMessage>> chatMessages(Ref ref, String conversationId) {
  final authState = ref.watch(authStateProvider);
  if (authState is! Authenticated) return Stream.value(const []);
  return ref
      .watch(messagesRepositoryProvider)
      .watchMessages(conversationId, myUserId: authState.user.id);
}
