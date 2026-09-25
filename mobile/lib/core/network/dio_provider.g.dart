// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dio_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dio)
final dioProvider = DioProvider._();

final class DioProvider extends $FunctionalProvider<Dio, Dio, Dio>
    with $Provider<Dio> {
  DioProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dioProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dioHash();

  @$internal
  @override
  $ProviderElement<Dio> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Dio create(Ref ref) {
    return dio(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Dio value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Dio>(value),
    );
  }
}

String _$dioHash() => r'ea6d850a5c119bb8745b19815a898ce4e8794a61';

/// Shared by [AuthInterceptor] and the connection manager (ADR 0005), so a
/// Session is refreshed at most once at a time whichever of them needs it.

@ProviderFor(sessionRefresher)
final sessionRefresherProvider = SessionRefresherProvider._();

/// Shared by [AuthInterceptor] and the connection manager (ADR 0005), so a
/// Session is refreshed at most once at a time whichever of them needs it.

final class SessionRefresherProvider
    extends
        $FunctionalProvider<
          SessionRefresher,
          SessionRefresher,
          SessionRefresher
        >
    with $Provider<SessionRefresher> {
  /// Shared by [AuthInterceptor] and the connection manager (ADR 0005), so a
  /// Session is refreshed at most once at a time whichever of them needs it.
  SessionRefresherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionRefresherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionRefresherHash();

  @$internal
  @override
  $ProviderElement<SessionRefresher> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SessionRefresher create(Ref ref) {
    return sessionRefresher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SessionRefresher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SessionRefresher>(value),
    );
  }
}

String _$sessionRefresherHash() => r'7a6e27204f6423462dd12fd7d5e79c71302f9a06';
