import 'package:dio/dio.dart';

import '../storage/token_store.dart';

/// Renews the Session's tokens on behalf of anything that needs a fresh
/// access token before it can proceed: the Dio auth interceptor and the
/// realtime connection manager (ADR 0005). Shared rather than duplicated so
/// there is one single-flight refresh and one dead-Session path for both.
class SessionRefresher {
  SessionRefresher({
    required this._refreshDio,
    required this._tokenStore,
    required this._onSessionEnded,
  });

  final Dio _refreshDio;
  final TokenStore _tokenStore;
  final void Function() _onSessionEnded;

  /// The refresh in flight, which every concurrent caller waits on rather
  /// than starting its own: the server treats a second use of one refresh
  /// token as theft.
  Future<bool>? _refreshing;

  /// Refreshes the Session's tokens, unless a refresh is already in flight,
  /// which this waits on instead. True once there's a fresh access token;
  /// false if the refresh failed, whether or not that ended the Session.
  Future<bool> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<bool> _refresh() async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': await _tokenStore.readRefreshToken()},
      );
    } on DioException catch (e) {
      // Only the server saying no ends the Session; being unreachable or
      // failing doesn't, so the next attempt can try again.
      final status = e.response?.statusCode;
      if (status == 400 || status == 401) await _endSession();
      return false;
    }
    await _tokenStore.saveTokens(
      accessToken: res.data!['accessToken'] as String,
      refreshToken: res.data!['refreshToken'] as String,
    );
    return true;
  }

  /// Forgets the Session (the Device ID stays: it names this install) and
  /// tells the app, which sends the user back to login.
  Future<void> _endSession() async {
    await _tokenStore.clearSession();
    _onSessionEnded();
  }
}
