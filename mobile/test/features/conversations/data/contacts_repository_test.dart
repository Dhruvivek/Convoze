import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/features/conversations/data/contacts_failure.dart';
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

  group('matchContacts', () {
    test('returns every matched User from the response', () async {
      final users = await repository(
        _StubAdapter.respond(200, {
          'users': [
            {'id': 'u1', 'displayName': 'Priya', 'avatarUrl': null, 'phoneNumber': '+14155550100'},
            {'id': 'u2', 'displayName': null, 'avatarUrl': null, 'phoneNumber': '+14155550101'},
          ],
        }),
      ).matchContacts(['+14155550100', '+14155550101']);

      expect(users, hasLength(2));
      expect(users[0].id, 'u1');
      expect(users[0].displayName, 'Priya');
      expect(users[1].displayName, isNull);
      expect(users[1].phoneNumber, '+14155550101');
    });

    test('returns an empty list when none of the contacts are on Convoze', () async {
      final users = await repository(
        _StubAdapter.respond(200, {'users': []}),
      ).matchContacts(['+14155550100']);

      expect(users, isEmpty);
    });

    test('throws ContactsNetworkFailure when the backend is unreachable', () async {
      await expectLater(
        repository(_StubAdapter.connectionFails()).matchContacts(['+14155550100']),
        throwsA(isA<ContactsNetworkFailure>()),
      );
    });

    test('throws ContactsRateLimited on a 429', () async {
      await expectLater(
        repository(
          _StubAdapter.respond(429, {
            'error': {'code': 'rate_limited', 'message': 'Too many contact syncs'},
          }),
        ).matchContacts(['+14155550100']),
        throwsA(isA<ContactsRateLimited>()),
      );
    });
  });

  group('lookupByPhoneNumber', () {
    test('returns the matched User', () async {
      final user = await repository(
        _StubAdapter.respond(200, {
          'user': {'id': 'u1', 'displayName': 'Priya', 'avatarUrl': null, 'phoneNumber': '+14155550100'},
        }),
      ).lookupByPhoneNumber('+14155550100');

      expect(user, isNotNull);
      expect(user!.id, 'u1');
    });

    test('returns null when nobody has that number', () async {
      final user = await repository(
        _StubAdapter.respond(200, {'user': null}),
      ).lookupByPhoneNumber('+15555550199');

      expect(user, isNull);
    });

    test('throws ContactsNetworkFailure when the backend is unreachable', () async {
      await expectLater(
        repository(_StubAdapter.connectionFails()).lookupByPhoneNumber('+14155550100'),
        throwsA(isA<ContactsNetworkFailure>()),
      );
    });
  });
}
