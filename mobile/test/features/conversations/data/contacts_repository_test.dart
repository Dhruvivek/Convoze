import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/features/conversations/data/contacts_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, or fails the connection.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter.respond(this._status, [this._body]) : _connectionFails = false;
  _StubAdapter.connectionFails()
    : _status = 0,
      _body = null,
      _connectionFails = true;

  final int _status;
  final Object? _body;
  final bool _connectionFails;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
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

void main() {
  ContactsRepository repository(_StubAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    return ContactsRepository(dio);
  }

  group('fetchContacts', () {
    test('returns every User from the response', () async {
      final users = await repository(
        _StubAdapter.respond(200, {
          'users': [
            {'id': 'u1', 'displayName': 'Priya', 'avatarUrl': null, 'phoneNumber': '+14155550100'},
            {'id': 'u2', 'displayName': null, 'avatarUrl': null, 'phoneNumber': '+14155550101'},
          ],
        }),
      ).fetchContacts();

      expect(users, hasLength(2));
      expect(users[0].id, 'u1');
      expect(users[0].displayName, 'Priya');
      expect(users[1].displayName, isNull);
      expect(users[1].phoneNumber, '+14155550101');
    });

    test('returns an empty list when there are no other Users', () async {
      final users = await repository(
        _StubAdapter.respond(200, {'users': []}),
      ).fetchContacts();

      expect(users, isEmpty);
    });

    test('propagates a DioException when the backend is unreachable', () async {
      await expectLater(
        repository(_StubAdapter.connectionFails()).fetchContacts(),
        throwsA(isA<DioException>()),
      );
    });
  });
}
