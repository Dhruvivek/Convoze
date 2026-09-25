// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'socket_factory.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Overridable, so a test can hand the app a socket of its own.

@ProviderFor(socketFactory)
final socketFactoryProvider = SocketFactoryProvider._();

/// Overridable, so a test can hand the app a socket of its own.

final class SocketFactoryProvider
    extends $FunctionalProvider<SocketFactory, SocketFactory, SocketFactory>
    with $Provider<SocketFactory> {
  /// Overridable, so a test can hand the app a socket of its own.
  SocketFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'socketFactoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$socketFactoryHash();

  @$internal
  @override
  $ProviderElement<SocketFactory> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SocketFactory create(Ref ref) {
    return socketFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SocketFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SocketFactory>(value),
    );
  }
}

String _$socketFactoryHash() => r'19af36ca6c17e57ed2036cf6ccc988168dec5005';
