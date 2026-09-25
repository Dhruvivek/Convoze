import 'dart:async';

import 'package:convoze/core/network/auth_interceptor.dart';
import 'package:convoze/core/network/session_refresher.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_backend.dart';

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
        tokenStore: tokenStore,
        sessionRefresher: SessionRefresher(
          refreshDio: Dio()..httpClientAdapter = backend,
          tokenStore: tokenStore,
          onSessionEnded: () => sessionEndedCalls++,
        ),
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
    'renews an expired access token for a logout, which needs one',
    () async {
      backend.expireAccessToken();

      final res = await dio.post<Map<String, dynamic>>('/auth/logout');

      expect(res.statusCode, 200);
      expect(backend.refreshCalls, 1);
    },
  );

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
