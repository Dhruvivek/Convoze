import 'dart:convert';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/features/profile/data/profile_failure.dart';
import 'package:convoze/features/profile/data/profile_repository.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, or fails the connection,
/// and records the last request's method/path/body for assertions.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter.respond(this._status, [this._body]) : _connectionFails = false;
  _RecordingAdapter.connectionFailure() : _status = 0, _body = null, _connectionFails = true;

  final int _status;
  final Object? _body;
  final bool _connectionFails;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (_connectionFails) {
      throw DioException.connectionError(requestOptions: options, reason: 'Connection refused');
    }
    return ResponseBody.fromString(
      _body == null ? '' : jsonEncode(_body),
      _status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> _error(String code) => {
  'error': {'code': code, 'message': 'irrelevant'},
};

Map<String, dynamic> _profile({
  String id = 'user-1',
  String phoneNumber = '+14155550100',
  String? displayName,
  String? about,
  String? avatarUrl,
}) => {
  'id': id,
  'phoneNumber': phoneNumber,
  'displayName': displayName,
  'about': about,
  'avatarUrl': avatarUrl,
};

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  ProfileRepository repository(_RecordingAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    return ProfileRepository(dio, db);
  }

  test('refreshMe GETs /users/me and upserts the row into the replica', () async {
    final adapter = _RecordingAdapter.respond(
      200,
      _profile(displayName: 'Alice', about: 'At work'),
    );

    await repository(adapter).refreshMe();

    expect(adapter.lastRequest!.method, 'GET');
    expect(adapter.lastRequest!.path, '/users/me');
    final row = await (db.select(db.users)..where((t) => t.id.equals('user-1'))).getSingle();
    expect(row.displayName, 'Alice');
    expect(row.about, 'At work');
  });

  test('refreshUser GETs /users/:id', () async {
    final adapter = _RecordingAdapter.respond(200, _profile(id: 'user-2'));

    await repository(adapter).refreshUser('user-2');

    expect(adapter.lastRequest!.path, '/users/user-2');
  });

  test('updateMe PATCHes both fields and upserts the response', () async {
    final adapter = _RecordingAdapter.respond(
      200,
      _profile(displayName: 'New name', about: null),
    );

    await repository(adapter).updateMe(displayName: 'New name', about: null);

    expect(adapter.lastRequest!.method, 'PATCH');
    expect(adapter.lastRequest!.path, '/users/me');
    expect(adapter.lastRequest!.data, {'displayName': 'New name', 'about': null});
    final row = await (db.select(db.users)..where((t) => t.id.equals('user-1'))).getSingle();
    expect(row.displayName, 'New name');
    expect(row.about, null);
  });

  test('removeAvatar DELETEs /users/me/avatar and clears the replica row', () async {
    await db
        .into(db.users)
        .insertOnConflictUpdate(
          UsersCompanion.insert(
            id: 'user-1',
            phoneNumber: '+14155550100',
            avatarUrl: const Value('https://old.example/avatar.png'),
          ),
        );
    final adapter = _RecordingAdapter.respond(200, _profile());

    await repository(adapter).removeAvatar();

    expect(adapter.lastRequest!.method, 'DELETE');
    expect(adapter.lastRequest!.path, '/users/me/avatar');
    final row = await (db.select(db.users)..where((t) => t.id.equals('user-1'))).getSingle();
    expect(row.avatarUrl, null);
  });

  test('a connection failure surfaces as ProfileNetworkFailure', () async {
    await expectLater(
      repository(_RecordingAdapter.connectionFailure()).refreshMe(),
      throwsA(isA<ProfileNetworkFailure>()),
    );
  });

  final cases = <String, (int, String, Matcher)>{
    'invalid_request': (400, 'invalid_request', isA<ProfileValidationFailure>()),
    'too_large': (400, 'too_large', isA<ProfileTooLarge>()),
    'rate_limited': (429, 'rate_limited', isA<ProfileRateLimited>()),
    'an unrecognised error': (500, 'internal_error', isA<UnexpectedProfileFailure>()),
  };
  cases.forEach((name, c) {
    final (status, code, failure) = c;
    test('maps "$code" to the right failure', () async {
      await expectLater(
        repository(_RecordingAdapter.respond(status, _error(code))).refreshMe(),
        throwsA(failure),
      );
    });
  });
}
