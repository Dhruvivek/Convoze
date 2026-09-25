import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Stands in for the backend: one Session whose current tokens it knows,
/// protected routes that answer 401 to anything else, and `/auth/refresh`.
/// Shared by the Dio auth interceptor and connection manager tests, since
/// both exercise the same single-flight refresh (#32).
class FakeBackend implements HttpClientAdapter {
  String accessToken = 'access-1';
  String refreshToken = 'refresh-1';
  int refreshCalls = 0;

  /// When set, `/auth/refresh` waits for it, so tests can pile up 401s
  /// while a refresh is in flight.
  Completer<void>? holdRefresh;

  /// When set, `/auth/refresh` answers with this status instead.
  int? refreshStatus;

  /// Protected routes whose answer waits on the completer, e.g. to have a
  /// 401 arrive after a refresh has already finished.
  final Map<String, Completer<void>> holdPath = {};

  final List<String?> authorizationsSeen = [];

  /// When set, protected routes answer 401 whatever the token.
  bool rejectAllProtected = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == '/auth/refresh') {
      refreshCalls++;
      await holdRefresh?.future;
      if (refreshStatus != null) {
        return _json(refreshStatus!, {
          'error': {'code': 'invalid_refresh_token', 'message': 'no'},
        });
      }
      final sent = (options.data as Map)['refreshToken'];
      if (sent != refreshToken) {
        return _json(401, {
          'error': {'code': 'invalid_refresh_token', 'message': 'no'},
        });
      }
      accessToken = 'access-${refreshCalls + 1}';
      refreshToken = 'refresh-${refreshCalls + 1}';
      return _json(200, {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
      });
    }

    await holdPath[options.path]?.future;
    final authorization = options.headers['Authorization'] as String?;
    authorizationsSeen.add(authorization);
    // Of the /auth routes only logout is protected; the rest answer 401 to
    // the credentials in their body, which the fake never accepts.
    final unprotectedAuthRoute =
        options.path.startsWith('/auth/') && options.path != '/auth/logout';
    if (rejectAllProtected ||
        unprotectedAuthRoute ||
        authorization != 'Bearer $accessToken') {
      return _json(401, {
        'error': {'code': 'unauthenticated', 'message': 'no'},
      });
    }
    return _json(200, {'path': options.path});
  }

  /// Expires the current access token, as 15 minutes passing would.
  void expireAccessToken() => accessToken = 'access-expired';

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
