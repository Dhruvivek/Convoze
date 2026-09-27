import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/realtime/connection_manager.dart';
import '../../../core/sync/wire.dart';
import '../../conversations/data/media_repository.dart';
import 'profile_failure.dart';

part 'profile_repository.g.dart';

/// A signed-in User's own profile and anyone else's public one (#43): reads
/// from the local `users` side-list (ADR 0009 — there's no profile Update
/// kind, so a row only refreshes when explicitly asked for), and writes
/// straight to the backend before upserting its response.
class ProfileRepository {
  ProfileRepository(this._dio, this._db);

  final Dio _dio;
  final AppDatabase _db;

  /// A live view of one User's replica row — `null` until something has
  /// referred to them (a shared Conversation's side-list) or fetched them.
  Stream<LocalUser?> watchUser(String userId) =>
      (_db.select(_db.users)..where((t) => t.id.equals(userId))).watchSingleOrNull();

  /// Refetches the signed-in User's own profile (`GET /users/me`) and
  /// upserts it — called once per reconnect by [ProfileSync], and by the My
  /// profile screen on open, so this Device's own edits made elsewhere show
  /// up here too.
  Future<void> refreshMe() => _refresh('/users/me');

  /// Refetches another User's public profile (`GET /users/:id`) — called
  /// when a profile screen opens, since ADR 0009 accepts staleness between
  /// then.
  Future<void> refreshUser(String userId) => _refresh('/users/$userId');

  Future<void> _refresh(String path) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path);
      await upsertUsers(_db, [res.data!]);
    } on DioException catch (e) {
      throw ProfileFailure.fromDioException(e);
    }
  }

  /// `displayName`/`about`: `null` clears the field, a string sets it. Both
  /// are always sent — the caller always holds the full current field
  /// state (a text field's controller), never a partial patch.
  Future<void> updateMe({required String? displayName, required String? about}) async {
    try {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/users/me',
        data: {'displayName': displayName, 'about': about},
      );
      await upsertUsers(_db, [res.data!]);
    } on DioException catch (e) {
      throw ProfileFailure.fromDioException(e);
    }
  }

  /// Uploads [file] straight to Cloudinary (`MediaRepository.uploadAvatar`,
  /// #40's pattern) then tells the backend to adopt it
  /// (`PUT /users/me/avatar`) — the old avatar, if any, is destroyed there.
  Future<void> setAvatar(MediaRepository mediaRepository, File file) async {
    try {
      final uploaded = await mediaRepository.uploadAvatar(file);
      final res = await _dio.put<Map<String, dynamic>>(
        '/users/me/avatar',
        data: uploaded.toJson(),
      );
      await upsertUsers(_db, [res.data!]);
    } on DioException catch (e) {
      throw ProfileFailure.fromDioException(e);
    }
  }

  Future<void> removeAvatar() async {
    try {
      final res = await _dio.delete<Map<String, dynamic>>('/users/me/avatar');
      await upsertUsers(_db, [res.data!]);
    } on DioException catch (e) {
      throw ProfileFailure.fromDioException(e);
    }
  }
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) =>
    ProfileRepository(ref.watch(dioProvider), ref.watch(appDatabaseProvider));

/// A live view of one User's replica row. Hand-written, not `@riverpod`
/// generated: `riverpod_generator` can't emit code for a provider whose
/// return type is a drift-generated `DataClass` like `LocalUser`
/// (`chat_thread_providers.dart` hit the same `InvalidTypeException` first).
final localUserProvider = StreamProvider.family<LocalUser?, String>(
  (ref, userId) => ref.watch(profileRepositoryProvider).watchUser(userId),
);

/// Refetches the signed-in User's own profile once on every reconnect
/// (`ProfileRepository.refreshMe`), same trigger `OwnDisconnectedAt`
/// (`presence_providers.dart`) uses for its own connect-edge side effect —
/// so this Device's own edits made elsewhere (another Device, or a support
/// tool) show up here without a dedicated profile Update kind (ADR 0009).
@Riverpod(keepAlive: true)
class ProfileSync extends _$ProfileSync {
  @override
  void build() {
    ref.listen(connectionStatusProvider, (previous, next) {
      if (next.value == ConnectionStatus.connected && previous?.value != ConnectionStatus.connected) {
        // Best effort: ADR 0009 already accepts a profile going stale until
        // something refreshes it again, so a failed refresh here (offline,
        // a flaky connection right after "connected" fires, ...) is never
        // worth surfacing — there's no user-facing action to retry it from.
        unawaited(ref.read(profileRepositoryProvider).refreshMe().catchError((_) {}));
      }
    });
  }
}
