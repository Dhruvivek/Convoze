// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection_manager.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Connected while signed in, and disconnected and disposed on sign-out.

@ProviderFor(connectionManager)
final connectionManagerProvider = ConnectionManagerProvider._();

/// Connected while signed in, and disconnected and disposed on sign-out.

final class ConnectionManagerProvider
    extends
        $FunctionalProvider<
          ConnectionManager,
          ConnectionManager,
          ConnectionManager
        >
    with $Provider<ConnectionManager> {
  /// Connected while signed in, and disconnected and disposed on sign-out.
  ConnectionManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionManagerHash();

  @$internal
  @override
  $ProviderElement<ConnectionManager> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectionManager create(Ref ref) {
    return connectionManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionManager>(value),
    );
  }
}

String _$connectionManagerHash() => r'2726001cfe00bc9d1d3a87c0e6b81c4674b9ba10';
