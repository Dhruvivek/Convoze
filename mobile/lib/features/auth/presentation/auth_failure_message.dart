import '../data/auth_failure.dart';

/// The inline message a sign-in screen shows when a step fails.
String authFailureMessage(Object error) => switch (error) {
  // Exhaustive, so a new AuthFailure can't silently fall through to the
  // generic message.
  AuthFailure() => switch (error) {
    InvalidPhoneNumber() =>
      "That isn't a valid phone number. Check it and try again.",
    OtpRateLimited() => 'Too many attempts. Try again later.',
    InvalidOtp() => 'That code is wrong or has expired.',
    OtpProviderUnavailable() =>
      "Our SMS provider isn't responding. Try again in a few minutes.",
    AuthNetworkFailure() =>
      "Couldn't reach Convoze. Check your connection and try again.",
    UnexpectedAuthFailure() => _somethingWentWrong,
  },
  _ => _somethingWentWrong,
};

const _somethingWentWrong = 'Something went wrong. Try again.';
