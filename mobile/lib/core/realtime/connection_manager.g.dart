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

String _$connectionManagerHash() => r'3819bf35e6935d9ef9abb6cc7336188dc03199fe';

/// The current status, then every change, for widgets like the "Connecting…"
/// banner to watch.

@ProviderFor(connectionStatus)
final connectionStatusProvider = ConnectionStatusProvider._();

/// The current status, then every change, for widgets like the "Connecting…"
/// banner to watch.

final class ConnectionStatusProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConnectionStatus>,
          ConnectionStatus,
          Stream<ConnectionStatus>
        >
    with $FutureModifier<ConnectionStatus>, $StreamProvider<ConnectionStatus> {
  /// The current status, then every change, for widgets like the "Connecting…"
  /// banner to watch.
  ConnectionStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionStatusHash();

  @$internal
  @override
  $StreamProviderElement<ConnectionStatus> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConnectionStatus> create(Ref ref) {
    return connectionStatus(ref);
  }
}

String _$connectionStatusHash() => r'c6d5803b677a976f203bd66aa34edd9354a6c268';
