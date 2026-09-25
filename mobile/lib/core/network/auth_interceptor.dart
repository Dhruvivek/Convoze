import 'package:dio/dio.dart';

import '../storage/token_store.dart';
import 'session_refresher.dart';

/// Signs every API request with the Session's access token, and renews an
/// expired one silently: on a 401 it refreshes the Session and retries the
/// request once (ADR 0003).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this._dio,
    required this._tokenStore,
    required this._sessionRefresher,
  });

  static const _retriedKey = 'authInterceptor.retried';

  final Dio _dio;
  final TokenStore _tokenStore;
  final SessionRefresher _sessionRefresher;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await _tokenStore.readAccessToken();
    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final renewable =
        err.response?.statusCode == 401 &&
        !_isUnprotectedAuthRoute(options.path) &&
        options.extra[_retriedKey] != true;
    if (!renewable || !await _renewSince(options)) {
      handler.next(err);
      return;
    }
    options.extra[_retriedKey] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// The routes that take no access token. A 401 from them is about the
  /// credentials sent to them (a wrong code, a dead refresh token), not about
  /// an expired access token. The other /auth routes (logout) are protected
  /// like any other.
  static const _unprotectedAuthRoutes = {
    '/auth/otp/request',
    '/auth/otp/verify',
    '/auth/refresh',
  };

  static bool _isUnprotectedAuthRoute(String path) =>
      _unprotectedAuthRoutes.contains(path);

  /// Makes sure the stored access token is newer than the one [options] was
  /// sent with, refreshing only if nobody else already has. True when there
  /// is a newer one to retry with.
  Future<bool> _renewSince(RequestOptions options) async {
    final current = await _tokenStore.readAccessToken();
    if (current == null) return false;
    if (options.headers['Authorization'] != 'Bearer $current') return true;
    return _sessionRefresher.refresh();
  }
}
