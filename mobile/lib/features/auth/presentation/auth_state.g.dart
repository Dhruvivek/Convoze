// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The one source of truth for whether the app is signed in; the router
/// gates screens on it.

@ProviderFor(AuthState)
final authStateProvider = AuthStateProvider._();

/// The one source of truth for whether the app is signed in; the router
/// gates screens on it.
final class AuthStateProvider extends $NotifierProvider<AuthState, AuthStatus> {
  /// The one source of truth for whether the app is signed in; the router
  /// gates screens on it.
  AuthStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStateHash();

  @$internal
  @override
  AuthState create() => AuthState();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthStatus>(value),
    );
  }
}

String _$authStateHash() => r'd91936c428d0adbbb4b529b27a9ef7158052dc0e';

/// The one source of truth for whether the app is signed in; the router
/// gates screens on it.

abstract class _$AuthState extends $Notifier<AuthStatus> {
  AuthStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AuthStatus, AuthStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AuthStatus, AuthStatus>,
              AuthStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
