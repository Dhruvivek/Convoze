import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/auth/data/auth_failure.dart';
import 'package:convoze/features/auth/data/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Connection refused',
      );
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

AuthRepository _repository(_StubAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
    ..httpClientAdapter = adapter;
  return AuthRepository(dio, TokenStore(const FlutterSecureStorage()));
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('requestOtp', () {
    Future<void> request(_StubAdapter adapter) =>
        _repository(adapter).requestOtp('+14155550100');

    test('completes when the backend accepts the request', () async {
      await request(_StubAdapter.respond(202));
    });

    final cases = <String, (int, String, Matcher)>{
      'an invalid number': (
        400,
        'invalid_phone_number',
        isA<InvalidPhoneNumber>(),
      ),
      'too many requests': (429, 'otp_rate_limited', isA<OtpRateLimited>()),
      'a provider outage': (
        502,
        'otp_provider_unavailable',
        isA<OtpProviderUnavailable>(),
      ),
      'an unrecognised error': (
        500,
        'internal_error',
        isA<UnexpectedAuthFailure>(),
      ),
    };
    cases.forEach((name, c) {
      final (status, code, failure) = c;
      test('throws a typed failure for $name', () async {
        await expectLater(
          request(_StubAdapter.respond(status, _error(code))),
          throwsA(failure),
        );
      });
    });

    test(
      'throws UnexpectedAuthFailure for an error without the error shape',
      () async {
        await expectLater(
          request(_StubAdapter.respond(503, 'Service Unavailable')),
          throwsA(isA<UnexpectedAuthFailure>()),
        );
      },
    );

    test('throws AuthNetworkFailure when the backend is unreachable', () async {
      await expectLater(
        request(_StubAdapter.connectionFails()),
        throwsA(isA<AuthNetworkFailure>()),
      );
    });
  });

  group('verifyOtp', () {
    Future<SignInResult> verify(_StubAdapter adapter) =>
        _repository(adapter).verifyOtp('+14155550100', '123456');

    test('returns the Session tokens and User', () async {
      final result = await verify(
        _StubAdapter.respond(200, {
          'accessToken': 'access',
          'refreshToken': 'session.secret',
          'user': {
            'id': 'u1',
            'phoneNumber': '+14155550100',
            'displayName': null,
          },
        }),
      );

      expect(result.accessToken, 'access');
      expect(result.refreshToken, 'session.secret');
      expect(result.user.id, 'u1');
    });

    test('throws InvalidOtp for a wrong or expired code', () async {
      await expectLater(
        verify(_StubAdapter.respond(401, _error('invalid_otp'))),
        throwsA(isA<InvalidOtp>()),
      );
    });

    test('throws OtpProviderUnavailable when the provider is down', () async {
      await expectLater(
        verify(_StubAdapter.respond(502, _error('otp_provider_unavailable'))),
        throwsA(isA<OtpProviderUnavailable>()),
      );
    });

    test('throws UnexpectedAuthFailure for a malformed request', () async {
      await expectLater(
        verify(_StubAdapter.respond(400, _error('invalid_request'))),
        throwsA(isA<UnexpectedAuthFailure>()),
      );
    });
  });
}
