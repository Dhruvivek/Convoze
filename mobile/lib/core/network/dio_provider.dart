import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/auth_state.dart';
import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';
import 'session_refresher.dart';

part 'dio_provider.g.dart';

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = _apiDio();
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      tokenStore: ref.watch(tokenStoreProvider),
      sessionRefresher: ref.watch(sessionRefresherProvider),
    ),
  );
  return dio;
}

/// Shared by [AuthInterceptor] and the connection manager (ADR 0005), so a
/// Session is refreshed at most once at a time whichever of them needs it.
@Riverpod(keepAlive: true)
SessionRefresher sessionRefresher(Ref ref) => SessionRefresher(
  refreshDio: _apiDio(),
  tokenStore: ref.watch(tokenStoreProvider),
  // Read when it happens, not now: auth state itself depends on Dio.
  onSessionEnded: () => ref.read(authStateProvider.notifier).sessionEnded(),
);

Dio _apiDio() => Dio(
  BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);
