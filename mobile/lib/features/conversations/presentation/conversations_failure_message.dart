import '../data/conversations_failure.dart';

/// The inline message shown when starting a Conversation fails.
String conversationsFailureMessage(Object error) => switch (error) {
  // Exhaustive, so a new ConversationsFailure can't silently fall through to
  // the generic message.
  ConversationsFailure() => switch (error) {
    ConversationNotFound() => "That person doesn't exist anymore.",
    SelfConversation() => "Can't start a conversation with yourself.",
    ConversationsNetworkFailure() =>
      "Couldn't reach Convoze. Check your connection and try again.",
    UnexpectedConversationsFailure() => _somethingWentWrong,
  },
  _ => _somethingWentWrong,
};

const _somethingWentWrong = 'Something went wrong. Try again.';
