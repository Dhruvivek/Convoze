import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/user.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/storage/token_store.dart';
import 'auth_failure.dart';

part 'auth_repository.g.dart';

/// What a successful verify hands back: a new Session's tokens and its User.
class SignInResult {
  const SignInResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final User user;
}

class AuthRepository {
  AuthRepository(this._dio, this._tokenStore);

  final Dio _dio;
  final TokenStore _tokenStore;

  /// Asks the backend to text a code to [phoneNumber] (with its +country code).
  ///
  /// Throws an [AuthFailure] when it can't.
  Future<void> requestOtp(String phoneNumber) async {
    await _post<void>('/auth/otp/request', {'phoneNumber': phoneNumber});
  }

  /// Exchanges the texted [code] for a Session on this Device.
  ///
  /// Throws an [AuthFailure] when it can't.
  Future<SignInResult> verifyOtp(String phoneNumber, String code) async {
    final res = await _post<Map<String, dynamic>>('/auth/otp/verify', {
      'phoneNumber': phoneNumber,
      'code': code,
      'deviceId': await _tokenStore.deviceId(),
      'platform': _platform,
    });
    final body = res.data!;
    return SignInResult(
      accessToken: body['accessToken'] as String,
      refreshToken: body['refreshToken'] as String,
      user: User.fromJson(body['user'] as Map<String, dynamic>),
    );
  }

  /// Ends this Device's Session on the server, so its tokens stop working
  /// at once.
  ///
  /// Throws an [AuthFailure] when it can't.
  Future<void> logout() async {
    await _post<void>('/auth/logout');
  }

  /// Ends every other Session of the signed-in User, leaving this Device's
  /// working.
  ///
  /// Throws an [AuthFailure] when it can't.
  Future<void> logoutOthers() async {
    await _post<void>('/auth/sessions/logout-others');
  }

  Future<Response<T>> _post<T>(String path, [Object? data]) async {
    try {
      return await _dio.post<T>(path, data: data);
    } on DioException catch (e) {
      throw AuthFailure.fromDioException(e);
    }
  }

  static String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    AuthRepository(ref.watch(dioProvider), ref.watch(tokenStoreProvider));
