// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(profileRepository)
final profileRepositoryProvider = ProfileRepositoryProvider._();

final class ProfileRepositoryProvider
    extends
        $FunctionalProvider<
          ProfileRepository,
          ProfileRepository,
          ProfileRepository
        >
    with $Provider<ProfileRepository> {
  ProfileRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileRepositoryHash();

  @$internal
  @override
  $ProviderElement<ProfileRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ProfileRepository create(Ref ref) {
    return profileRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProfileRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProfileRepository>(value),
    );
  }
}

String _$profileRepositoryHash() => r'25db77daeb469cbd83402a2cb9abd3e472678768';

/// Refetches the signed-in User's own profile once on every reconnect
/// (`ProfileRepository.refreshMe`), same trigger `OwnDisconnectedAt`
/// (`presence_providers.dart`) uses for its own connect-edge side effect —
/// so this Device's own edits made elsewhere (another Device, or a support
/// tool) show up here without a dedicated profile Update kind (ADR 0009).

@ProviderFor(ProfileSync)
final profileSyncProvider = ProfileSyncProvider._();

/// Refetches the signed-in User's own profile once on every reconnect
/// (`ProfileRepository.refreshMe`), same trigger `OwnDisconnectedAt`
/// (`presence_providers.dart`) uses for its own connect-edge side effect —
/// so this Device's own edits made elsewhere (another Device, or a support
/// tool) show up here without a dedicated profile Update kind (ADR 0009).
final class ProfileSyncProvider extends $NotifierProvider<ProfileSync, void> {
  /// Refetches the signed-in User's own profile once on every reconnect
  /// (`ProfileRepository.refreshMe`), same trigger `OwnDisconnectedAt`
  /// (`presence_providers.dart`) uses for its own connect-edge side effect —
  /// so this Device's own edits made elsewhere (another Device, or a support
  /// tool) show up here without a dedicated profile Update kind (ADR 0009).
  ProfileSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileSyncHash();

  @$internal
  @override
  ProfileSync create() => ProfileSync();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$profileSyncHash() => r'8fc40fe3a8642468cc1d52fbd2b7cc5959286c62';

/// Refetches the signed-in User's own profile once on every reconnect
/// (`ProfileRepository.refreshMe`), same trigger `OwnDisconnectedAt`
/// (`presence_providers.dart`) uses for its own connect-edge side effect —
/// so this Device's own edits made elsewhere (another Device, or a support
/// tool) show up here without a dedicated profile Update kind (ADR 0009).

abstract class _$ProfileSync extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
