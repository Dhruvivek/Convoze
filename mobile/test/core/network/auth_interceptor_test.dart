import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/network/auth_interceptor.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the backend: one Session whose current tokens it knows,
/// protected routes that answer 401 to anything else, and `/auth/refresh`.
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
    if (rejectAllProtected ||
        options.path.startsWith('/auth/') ||
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late TokenStore tokenStore;
  late Dio dio;
  late int sessionEndedCalls;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'access-1',
      'refresh_token': 'refresh-1',
      'device_id': 'device-1',
    });
    backend = FakeBackend();
    tokenStore = TokenStore(const FlutterSecureStorage());
    sessionEndedCalls = 0;
    dio = Dio()..httpClientAdapter = backend;
    dio.interceptors.add(
      AuthInterceptor(
        dio: dio,
        refreshDio: Dio()..httpClientAdapter = backend,
        tokenStore: tokenStore,
        onSessionEnded: () => sessionEndedCalls++,
      ),
    );
  });

  test('attaches the access token as a bearer token', () async {
    final res = await dio.get<Map<String, dynamic>>('/echo');

    expect(res.statusCode, 200);
    expect(backend.authorizationsSeen, ['Bearer access-1']);
  });

  test('renews an expired access token and retries the request', () async {
    backend.expireAccessToken();

    final res = await dio.get<Map<String, dynamic>>('/echo');

    expect(res.statusCode, 200);
    expect(res.data, {'path': '/echo'});
    expect(backend.refreshCalls, 1);
    expect(await tokenStore.readAccessToken(), backend.accessToken);
    expect(await tokenStore.readRefreshToken(), backend.refreshToken);
  });

  test('concurrent 401s wait on a single refresh', () async {
    backend.expireAccessToken();
    backend.holdRefresh = Completer<void>();

    final calls = [
      for (var i = 0; i < 5; i++) dio.get<Map<String, dynamic>>('/echo/$i'),
    ];
    await pumpEventQueue();
    backend.holdRefresh!.complete();
    final responses = await Future.wait(calls);

    expect(backend.refreshCalls, 1);
    expect(responses.map((r) => r.statusCode), everyElement(200));
  });

  test(
    'a 401 answered after the refresh finished retries without another',
    () async {
      backend.expireAccessToken();
      backend.holdPath['/slow'] = Completer<void>();

      // Both go out signed with the expired token; /slow is answered only
      // once /fast has already been renewed and retried.
      final slow = dio.get<Map<String, dynamic>>('/slow');
      await dio.get<Map<String, dynamic>>('/fast');
      backend.holdPath['/slow']!.complete();
      final res = await slow;

      expect(res.statusCode, 200);
      expect(backend.refreshCalls, 1);
    },
  );

  test('retries only once, even if the retry is rejected too', () async {
    backend.expireAccessToken();
    backend.rejectAllProtected = true;

    final call = dio.get<void>('/echo');

    await expectLater(
      call,
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(backend.refreshCalls, 1);
    expect(backend.authorizationsSeen, hasLength(2));
  });

  test('leaves 401s from /auth routes alone', () async {
    final call = dio.post<void>('/auth/otp/verify');

    await expectLater(call, throwsA(isA<DioException>()));
    expect(backend.refreshCalls, 0);
  });

  test(
    'when the refresh is rejected, ends the Session but keeps the Device ID',
    () async {
      backend.expireAccessToken();
      backend.refreshStatus = 401;

      final call = dio.get<void>('/echo');

      await expectLater(call, throwsA(isA<DioException>()));
      expect(await tokenStore.readAccessToken(), isNull);
      expect(await tokenStore.readRefreshToken(), isNull);
      expect(await tokenStore.deviceId(), 'device-1');
      expect(sessionEndedCalls, 1);
    },
  );

  test(
    'ends the Session once when concurrent 401s share a rejected refresh',
    () async {
      backend.expireAccessToken();
      backend.refreshStatus = 401;

      final calls = [
        for (var i = 0; i < 3; i++)
          dio
              .get<void>('/echo/$i')
              .then<Object?>((_) => null, onError: (Object e) => e),
      ];
      final results = await Future.wait(calls);

      expect(results, everyElement(isA<DioException>()));
      expect(backend.refreshCalls, 1);
      expect(sessionEndedCalls, 1);
    },
  );

  test('keeps the Session when the refresh fails for another reason', () async {
    backend.expireAccessToken();
    backend.refreshStatus = 503;

    final call = dio.get<void>('/echo');

    await expectLater(call, throwsA(isA<DioException>()));
    expect(await tokenStore.readRefreshToken(), 'refresh-1');
    expect(sessionEndedCalls, 0);
  });
}
