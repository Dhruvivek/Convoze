import '../data/contacts_failure.dart';

/// The inline message shown when a contacts sync or phone-number lookup fails.
String contactsFailureMessage(Object error) => switch (error) {
  // Exhaustive, so a new ContactsFailure can't silently fall through to the
  // generic message.
  ContactsFailure() => switch (error) {
    ContactsRateLimited() => 'Too many attempts. Try again in a few minutes.',
    ContactsNetworkFailure() =>
      "Couldn't reach Convoze. Check your connection and try again.",
    UnexpectedContactsFailure() => _somethingWentWrong,
  },
  _ => _somethingWentWrong,
};

const _somethingWentWrong = 'Something went wrong. Try again.';
