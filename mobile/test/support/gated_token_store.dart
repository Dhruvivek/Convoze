import 'dart:async';

import 'package:convoze/core/storage/token_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A TokenStore whose refresh-token read finishes only when the test says,
/// to hold the app in its restoring state.
///
/// In a widget test, create it in the test body, not in setUp: the read has
/// to complete inside the test's fake-async zone for pumps to see it.
class GatedTokenStore extends TokenStore {
  GatedTokenStore() : super(const FlutterSecureStorage());

  final refreshTokenRead = Completer<String?>();

  @override
  Future<String?> readRefreshToken() => refreshTokenRead.future;
}
