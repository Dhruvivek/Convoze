/// Why a `MessagesRepository.editMessage`/`deleteMessage` call was refused
/// (#56) — the ack codes `editMessage.js`/`deleteMessage.js` answer with.
sealed class MessageActionFailure implements Exception {
  const MessageActionFailure();

  factory MessageActionFailure.fromCode(String? code) => switch (code) {
    'NOT_FOUND' => const MessageActionNotFound(),
    'FORBIDDEN' => const MessageActionForbidden(),
    'TOO_LARGE' => const MessageActionTooLarge(),
    'RATE_LIMITED' => const MessageActionRateLimited(),
    _ => const UnexpectedMessageActionFailure(),
  };
}

/// The Message was deleted, or the Conversation left, before this landed.
class MessageActionNotFound extends MessageActionFailure {
  const MessageActionNotFound();
}

/// Not this Message's sender, or it isn't (or isn't any longer) a plain
/// text Message.
class MessageActionForbidden extends MessageActionFailure {
  const MessageActionForbidden();
}

/// An edit's content is over the 4096-byte limit.
class MessageActionTooLarge extends MessageActionFailure {
  const MessageActionTooLarge();
}

class MessageActionRateLimited extends MessageActionFailure {
  const MessageActionRateLimited();
}

/// The ack never arrived — a dropped socket or a timed-out send, the same
/// case the Outbox drainer stops and waits out (ADR 0009); neither call is
/// queued, so this is a dead end for now rather than something to retry.
class MessageActionNetworkFailure extends MessageActionFailure {
  const MessageActionNetworkFailure();
}

class UnexpectedMessageActionFailure extends MessageActionFailure {
  const UnexpectedMessageActionFailure();
}
