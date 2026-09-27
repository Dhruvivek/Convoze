import 'package:dio/dio.dart';

/// Why a profile edit (name/about/avatar, #43) couldn't go ahead. Mirrors
/// `ConversationsFailure`'s shape: the backend's errors all look like
/// `{ "error": { "code", "message" } }`.
sealed class ProfileFailure implements Exception {
  const ProfileFailure();

  factory ProfileFailure.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) return const ProfileNetworkFailure();
    return switch (_errorCode(response.data)) {
      'invalid_request' => const ProfileValidationFailure(),
      'too_large' => const ProfileTooLarge(),
      'rate_limited' => const ProfileRateLimited(),
      _ => const UnexpectedProfileFailure(),
    };
  }

  static String? _errorCode(Object? body) => switch (body) {
    {'error': {'code': final String code}} => code,
    _ => null,
  };
}

/// The backend couldn't be reached at all — the caller should say this
/// needs a connection, not show a generic error (#43's "needs a connection" hint).
class ProfileNetworkFailure extends ProfileFailure {
  const ProfileNetworkFailure();
}

/// The name/about didn't meet the length or character rules.
class ProfileValidationFailure extends ProfileFailure {
  const ProfileValidationFailure();
}

/// The picked avatar is over Cloudinary's size limit.
class ProfileTooLarge extends ProfileFailure {
  const ProfileTooLarge();
}

class ProfileRateLimited extends ProfileFailure {
  const ProfileRateLimited();
}

class UnexpectedProfileFailure extends ProfileFailure {
  const UnexpectedProfileFailure();
}
