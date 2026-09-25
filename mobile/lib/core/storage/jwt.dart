import 'dart:convert';

/// A JWT's claims, read from its payload segment without verifying its
/// signature: for the client's own judgement (when to refresh, which
/// Session it holds), never for trusting the token (the server is what
/// actually verifies it).
Map<String, dynamic> jwtClaims(String token) => jsonDecode(
  utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
) as Map<String, dynamic>;

/// The `exp` claim of a JWT [token], in UTC, or null if it can't be read.
DateTime? jwtExpiry(String token) {
  try {
    final exp = jwtClaims(token)['exp'] as num;
    return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
  } catch (_) {
    return null;
  }
}
