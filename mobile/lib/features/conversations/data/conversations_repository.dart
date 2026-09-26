import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/formatting/display_name.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/sync/wire.dart';
import '../../auth/presentation/auth_state.dart';
import 'conversation_list_item.dart';
import 'conversations_failure.dart';

part 'conversations_repository.g.dart';

/// The conversation list (#52): reads only from the Local replica (#51), so
/// it shows immediately, even offline, and starts a direct chat over REST.
class ConversationsRepository {
  ConversationsRepository(this._dio, this._db);

  final Dio _dio;
  final AppDatabase _db;

  /// Returns the caller's existing direct Conversation with [userId], or
  /// creates one (`POST /conversations/direct`, #50). Upserts the result
  /// into the replica before returning its id, so the chat screen it opens
  /// can read it straight from the replica like everything else.
  ///
  /// Throws a [ConversationsFailure] when it can't.
  Future<String> openDirect(String userId) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/conversations/direct',
        data: {'userId': userId},
      );
      final body = res.data!;
      await upsertUsers(_db, (body['users'] as List?) ?? const []);
      await upsertConversationRow(_db, body);
      return body['id'] as String;
    } on DioException catch (e) {
      throw ConversationsFailure.fromDioException(e);
    }
  }

  /// A live, joined view of the caller's direct conversations: each row's
  /// other participant, a preview of the latest Message, and this User's own
  /// preferences (#45) — everything the list screen needs, without a second
  /// round trip per row. [archived] switches between the main list and the
  /// Archived screen; hidden (deleted, #45) conversations never show in
  /// either. Ordering is left to the caller (pin/activity is a display
  /// concern, not something baked into the query).
  Stream<List<ConversationListItem>> watchList({
    required String myUserId,
    bool archived = false,
  }) {
    final archivedClause = archived ? 'c.archived_at IS NOT NULL' : 'c.archived_at IS NULL';
    final query = _db.customSelect(
      '''
      SELECT
        c.id AS c_id,
        c.type AS c_type,
        c.unread_count AS c_unread_count,
        c.left AS c_left,
        c.pinned_at AS c_pinned_at,
        c.archived_at AS c_archived_at,
        c.muted_until AS c_muted_until,
        c.hidden_at AS c_hidden_at,
        other.id AS other_id,
        other.display_name AS other_display_name,
        other.phone_number AS other_phone_number,
        lm.sender_id AS lm_sender_id,
        lm.content AS lm_content,
        lm.is_deleted AS lm_is_deleted,
        lm.created_at AS lm_created_at
      FROM conversations c
      JOIN participants me ON me.conversation_id = c.id AND me.user_id = ?
      LEFT JOIN participants op ON op.conversation_id = c.id AND op.user_id != ?
      LEFT JOIN users other ON other.id = op.user_id
      LEFT JOIN messages lm ON lm.id = (
        SELECT m.id FROM messages m WHERE m.conversation_id = c.id ORDER BY m.id DESC LIMIT 1
      )
      WHERE c.type = 'direct' AND c.hidden_at IS NULL AND $archivedClause
      ''',
      variables: [Variable.withString(myUserId), Variable.withString(myUserId)],
      readsFrom: {_db.conversations, _db.participants, _db.users, _db.messages},
    );
    return query.watch().map((rows) {
      final items = rows.map((row) => _toItem(row, myUserId)).toList()..sort(_byPinThenActivity);
      return items;
    });
  }

  ConversationListItem _toItem(QueryRow row, String myUserId) {
    final senderId = row.read<String?>('lm_sender_id');
    final content = row.read<String?>('lm_content');
    final isDeleted = row.read<bool?>('lm_is_deleted') ?? false;
    final preview = switch (senderId) {
      null => '',
      _ when isDeleted => 'This message was deleted',
      _ when senderId == myUserId => 'You: ${content ?? ''}',
      _ => content ?? '',
    };

    return ConversationListItem(
      id: row.read<String>('c_id'),
      type: row.read<String>('c_type'),
      otherUserId: row.read<String?>('other_id'),
      title: displayName(
        displayName: row.read<String?>('other_display_name'),
        phoneNumber: row.read<String?>('other_phone_number') ?? '',
      ),
      avatarSeed: row.read<String?>('other_id') ?? row.read<String>('c_id'),
      previewText: preview,
      lastMessageAt: row.read<DateTime?>('lm_created_at'),
      unreadCount: row.read<int>('c_unread_count'),
      left: row.read<bool>('c_left'),
      pinnedAt: row.read<DateTime?>('c_pinned_at'),
      archivedAt: row.read<DateTime?>('c_archived_at'),
      mutedUntil: row.read<DateTime?>('c_muted_until'),
      hiddenAt: row.read<DateTime?>('c_hidden_at'),
    );
  }

  static int _byPinThenActivity(ConversationListItem a, ConversationListItem b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    if (a.pinned) return b.pinnedAt!.compareTo(a.pinnedAt!);
    final aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }
}

@Riverpod(keepAlive: true)
ConversationsRepository conversationsRepository(Ref ref) =>
    ConversationsRepository(ref.watch(dioProvider), ref.watch(appDatabaseProvider));

/// The live conversation list for the signed-in User — empty (rather than an
/// error) while signed out, since nothing should ever try to read it then.
@riverpod
Stream<List<ConversationListItem>> conversationList(Ref ref, {bool archived = false}) {
  final authState = ref.watch(authStateProvider);
  if (authState is! Authenticated) return Stream.value(const []);
  return ref
      .watch(conversationsRepositoryProvider)
      .watchList(myUserId: authState.user.id, archived: archived);
}
