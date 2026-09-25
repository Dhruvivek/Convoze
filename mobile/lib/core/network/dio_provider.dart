import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/auth_state.dart';
import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'auth_interceptor.dart';

part 'dio_provider.g.dart';

@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  final dio = _apiDio();
  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      refreshDio: _apiDio(),
      tokenStore: ref.watch(tokenStoreProvider),
      // Read when it happens, not now: auth state itself depends on Dio.
      onSessionEnded: () =>
          ref.read(authStateProvider.notifier).sessionEnded(),
    ),
  );
  return dio;
}

Dio _apiDio() => Dio(
  BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);
