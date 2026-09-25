import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/sync/wire.dart';
import 'conversation_prefs_failure.dart';

part 'conversation_prefs_repository.g.dart';

/// How long a mute lasts (#45); `'always'` is stored server-side as a
/// far-future sentinel rather than a real "forever" concept.
enum MuteDuration { eightHours, oneWeek, always }

String _muteValue(MuteDuration duration) => switch (duration) {
  MuteDuration.eightHours => '8h',
  MuteDuration.oneWeek => '1w',
  MuteDuration.always => 'always',
};

/// Pin, archive, mute, clear and delete a Conversation (#45) — REST and
/// online-only (not queued in the Outbox, same reasoning as edits in ADR
/// 0009), each upserting the hydrated row it gets back into the replica the
/// same way a live `conversation.prefs` Update would.
class ConversationPrefsRepository {
  ConversationPrefsRepository(this._dio, this._db);

  final Dio _dio;
  final AppDatabase _db;

  Future<void> pin(String conversationId) => _patchPrefs(conversationId, {'pinned': true});

  Future<void> unpin(String conversationId) => _patchPrefs(conversationId, {'pinned': false});

  Future<void> archive(String conversationId) => _patchPrefs(conversationId, {'archived': true});

  Future<void> unarchive(String conversationId) =>
      _patchPrefs(conversationId, {'archived': false});

  Future<void> mute(String conversationId, MuteDuration duration) =>
      _patchPrefs(conversationId, {'mute': _muteValue(duration)});

  Future<void> unmute(String conversationId) => _patchPrefs(conversationId, {'mute': null});

  /// Removes this User's own view of the Conversation's current history;
  /// the Conversation itself stays in the list.
  Future<void> clear(String conversationId) => _post(conversationId, 'clear');

  /// Removes the Conversation from this User's list (and clears its
  /// history); it reappears, with only new Messages, if the other
  /// participant writes again.
  Future<void> delete(String conversationId) => _post(conversationId, 'delete');

  Future<void> _patchPrefs(String conversationId, Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/conversations/$conversationId/prefs',
        data: data,
      );
      await _applyResponse(res.data!);
    } on DioException catch (e) {
      throw ConversationPrefsFailure.fromDioException(e);
    }
  }

  Future<void> _post(String conversationId, String action) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/conversations/$conversationId/$action',
      );
      await _applyResponse(res.data!);
    } on DioException catch (e) {
      throw ConversationPrefsFailure.fromDioException(e);
    }
  }

  Future<void> _applyResponse(Map<String, dynamic> body) async {
    await upsertUsers(_db, (body['users'] as List?) ?? const []);
    await applyConversationPrefs(_db, body);
  }
}

@Riverpod(keepAlive: true)
ConversationPrefsRepository conversationPrefsRepository(Ref ref) =>
    ConversationPrefsRepository(ref.watch(dioProvider), ref.watch(appDatabaseProvider));
