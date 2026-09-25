import 'package:dio/dio.dart';

/// Why a sign-in step couldn't go ahead. The auth repository throws these in
/// place of raw [DioException]s, so screens can say exactly what went wrong.
sealed class AuthFailure implements Exception {
  const AuthFailure();

  /// Maps a failed call to the backend, whose errors all look like
  /// `{ "error": { "code", "message" } }`, to its failure.
  factory AuthFailure.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) return const AuthNetworkFailure();
    return switch (_errorCode(response.data)) {
      'invalid_phone_number' => const InvalidPhoneNumber(),
      'otp_rate_limited' => const OtpRateLimited(),
      'invalid_otp' => const InvalidOtp(),
      'otp_provider_unavailable' => const OtpProviderUnavailable(),
      _ => const UnexpectedAuthFailure(),
    };
  }

  static String? _errorCode(Object? body) => switch (body) {
    {'error': {'code': final String code}} => code,
    _ => null,
  };
}

/// The phone number isn't a valid number.
class InvalidPhoneNumber extends AuthFailure {
  const InvalidPhoneNumber();
}

/// Too many codes were requested for this number recently.
class OtpRateLimited extends AuthFailure {
  const OtpRateLimited();
}

/// The code is wrong or has expired.
class InvalidOtp extends AuthFailure {
  const InvalidOtp();
}

/// The SMS provider couldn't send or check a code.
class OtpProviderUnavailable extends AuthFailure {
  const OtpProviderUnavailable();
}

/// The backend couldn't be reached at all.
class AuthNetworkFailure extends AuthFailure {
  const AuthNetworkFailure();
}

/// Anything else: a bug on one side or the other, not something the User
/// can fix.
class UnexpectedAuthFailure extends AuthFailure {
  const UnexpectedAuthFailure();
}
