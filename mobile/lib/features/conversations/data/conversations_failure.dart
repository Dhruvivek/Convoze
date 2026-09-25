import 'package:dio/dio.dart';

/// Why `ConversationsRepository.openDirect` couldn't go ahead. Mirrors
/// `AuthFailure`'s shape: the backend's errors all look like `{ "error":
/// { "code", "message" } }`.
sealed class ConversationsFailure implements Exception {
  const ConversationsFailure();

  factory ConversationsFailure.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) return const ConversationsNetworkFailure();
    return switch (_errorCode(response.data)) {
      'not_found' => const ConversationNotFound(),
      'invalid_request' => const SelfConversation(),
      _ => const UnexpectedConversationsFailure(),
    };
  }

  static String? _errorCode(Object? body) => switch (body) {
    {'error': {'code': final String code}} => code,
    _ => null,
  };
}

/// The target User doesn't exist.
class ConversationNotFound extends ConversationsFailure {
  const ConversationNotFound();
}

/// Tried to start a direct Conversation with oneself.
class SelfConversation extends ConversationsFailure {
  const SelfConversation();
}

/// The backend couldn't be reached at all.
class ConversationsNetworkFailure extends ConversationsFailure {
  const ConversationsNetworkFailure();
}

/// Anything else.
class UnexpectedConversationsFailure extends ConversationsFailure {
  const UnexpectedConversationsFailure();
}
