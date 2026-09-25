import 'dart:convert';

/// A JWT-shaped string carrying only an `exp` claim [secondsFromNow] away —
/// enough for `jwtExpiry` to read. Its signature is meaningless; nothing
/// here verifies it, matching how the client only ever reads its own token's
/// claims for scheduling, never for trust.
String fakeJwt({required int secondsFromNow}) {
  String segment(Object payload) =>
      base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '');
  final exp =
      DateTime.now()
          .toUtc()
          .add(Duration(seconds: secondsFromNow))
          .millisecondsSinceEpoch ~/
      1000;
  return '${segment({'alg': 'none'})}.${segment({'exp': exp})}.sig';
}
