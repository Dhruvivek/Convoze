import 'package:dio/dio.dart';

/// Why `POST /users/match` or `GET /users/lookup` couldn't go ahead. Mirrors
/// `ConversationsFailure`'s shape: the backend's errors all look like
/// `{ "error": { "code", "message" } }`.
sealed class ContactsFailure implements Exception {
  const ContactsFailure();

  factory ContactsFailure.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) return const ContactsNetworkFailure();
    return switch (_errorCode(response.data)) {
      'rate_limited' => const ContactsRateLimited(),
      _ => const UnexpectedContactsFailure(),
    };
  }

  static String? _errorCode(Object? body) => switch (body) {
    {'error': {'code': final String code}} => code,
    _ => null,
  };
}

/// Too many contact syncs / lookups in a short window.
class ContactsRateLimited extends ContactsFailure {
  const ContactsRateLimited();
}

/// The backend couldn't be reached at all.
class ContactsNetworkFailure extends ContactsFailure {
  const ContactsNetworkFailure();
}

/// Anything else.
class UnexpectedContactsFailure extends ContactsFailure {
  const UnexpectedContactsFailure();
}
