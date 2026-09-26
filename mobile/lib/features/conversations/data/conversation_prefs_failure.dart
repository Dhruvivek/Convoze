import 'package:dio/dio.dart';

/// Why a `ConversationPrefsRepository` call couldn't go ahead.
sealed class ConversationPrefsFailure implements Exception {
  const ConversationPrefsFailure();

  factory ConversationPrefsFailure.fromDioException(DioException e) {
    final response = e.response;
    if (response == null) return const ConversationPrefsNetworkFailure();
    return switch (_errorCode(response.data)) {
      'pin_limit' => const PinLimitReached(),
      'must_leave_group' => const MustLeaveGroup(),
      'not_found' => const ConversationPrefsNotFound(),
      _ => const UnexpectedConversationPrefsFailure(),
    };
  }

  static String? _errorCode(Object? body) => switch (body) {
    {'error': {'code': final String code}} => code,
    _ => null,
  };
}

/// The caller already has 5 pinned conversations (#45).
class PinLimitReached extends ConversationPrefsFailure {
  const PinLimitReached();
}

/// A group can only be deleted after leaving it.
class MustLeaveGroup extends ConversationPrefsFailure {
  const MustLeaveGroup();
}

/// Not a current or former Participant of that Conversation.
class ConversationPrefsNotFound extends ConversationPrefsFailure {
  const ConversationPrefsNotFound();
}

/// The backend couldn't be reached at all.
class ConversationPrefsNetworkFailure extends ConversationPrefsFailure {
  const ConversationPrefsNetworkFailure();
}

/// Anything else.
class UnexpectedConversationPrefsFailure extends ConversationPrefsFailure {
  const UnexpectedConversationPrefsFailure();
}
