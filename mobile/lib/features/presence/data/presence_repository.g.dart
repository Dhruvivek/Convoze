// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(presenceRepository)
final presenceRepositoryProvider = PresenceRepositoryProvider._();

final class PresenceRepositoryProvider
    extends
        $FunctionalProvider<
          PresenceRepository,
          PresenceRepository,
          PresenceRepository
        >
    with $Provider<PresenceRepository> {
  PresenceRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'presenceRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$presenceRepositoryHash();

  @$internal
  @override
  $ProviderElement<PresenceRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PresenceRepository create(Ref ref) {
    return presenceRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PresenceRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PresenceRepository>(value),
    );
  }
}

String _$presenceRepositoryHash() =>
    r'ecab33ebd435d30b09ff71a3234bb1d6105017e3';
