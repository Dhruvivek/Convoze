import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../models/user.dart';

part 'token_store.g.dart';

/// Keeps the Session's tokens, the User it signed in, and this install's
/// Device ID in the platform's secure storage (Keychain / Keystore).
class TokenStore {
  TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userKey = 'user';
  static const _deviceIdKey = 'device_id';

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  /// The User as they were at sign-in, so a restart can show who is signed
  /// in without a network call. Null when none is stored or it can't be
  /// read back.
  ///
  /// Stands in until the Local replica holds profiles (ADR 0009).
  Future<User?> readUser() async {
    final json = await _storage.read(key: _userKey);
    if (json == null) return null;
    try {
      return User.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveUser(User user) =>
      _storage.write(key: _userKey, value: jsonEncode(user.toJson()));

  /// Forgets the Session: its tokens and its User. The Device ID survives: it
  /// names this install, not the login.
  Future<void> clearSession() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userKey);
  }

  /// This install's Device ID, generated on first use and kept from then on.
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceIdKey);
    if (existing != null) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: _deviceIdKey, value: created);
    return created;
  }
}

@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => TokenStore(const FlutterSecureStorage());
