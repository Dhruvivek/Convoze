// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The moment this Device's own connection was last seen leaving `connected`
/// — null while connected, or if it never has dropped. The anchor
/// [presence]'s `lastSeen` downgrade uses while our own socket is down
/// (#34, `CONTEXT.md` **Presence**), since nothing more recent than that can
/// be vouched for.

@ProviderFor(OwnDisconnectedAt)
final ownDisconnectedAtProvider = OwnDisconnectedAtProvider._();

/// The moment this Device's own connection was last seen leaving `connected`
/// — null while connected, or if it never has dropped. The anchor
/// [presence]'s `lastSeen` downgrade uses while our own socket is down
/// (#34, `CONTEXT.md` **Presence**), since nothing more recent than that can
/// be vouched for.
final class OwnDisconnectedAtProvider
    extends $NotifierProvider<OwnDisconnectedAt, DateTime?> {
  /// The moment this Device's own connection was last seen leaving `connected`
  /// — null while connected, or if it never has dropped. The anchor
  /// [presence]'s `lastSeen` downgrade uses while our own socket is down
  /// (#34, `CONTEXT.md` **Presence**), since nothing more recent than that can
  /// be vouched for.
  OwnDisconnectedAtProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownDisconnectedAtProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownDisconnectedAtHash();

  @$internal
  @override
  OwnDisconnectedAt create() => OwnDisconnectedAt();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DateTime? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DateTime?>(value),
    );
  }
}

String _$ownDisconnectedAtHash() => r'99be16185b2c2151e355324d80011ca2b83878da';

/// The moment this Device's own connection was last seen leaving `connected`
/// — null while connected, or if it never has dropped. The anchor
/// [presence]'s `lastSeen` downgrade uses while our own socket is down
/// (#34, `CONTEXT.md` **Presence**), since nothing more recent than that can
/// be vouched for.

abstract class _$OwnDisconnectedAt extends $Notifier<DateTime?> {
  DateTime? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<DateTime?, DateTime?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<DateTime?, DateTime?>,
              DateTime?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// [PresenceRepository.current], then every change — a plain
/// `Map<String, RawPresence>` rather than the repository object itself, so
/// [presence] rebuilds on every emission rather than once per new instance.

@ProviderFor(presenceMap)
final presenceMapProvider = PresenceMapProvider._();

/// [PresenceRepository.current], then every change — a plain
/// `Map<String, RawPresence>` rather than the repository object itself, so
/// [presence] rebuilds on every emission rather than once per new instance.

final class PresenceMapProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, RawPresence>>,
          Map<String, RawPresence>,
          Stream<Map<String, RawPresence>>
        >
    with
        $FutureModifier<Map<String, RawPresence>>,
        $StreamProvider<Map<String, RawPresence>> {
  /// [PresenceRepository.current], then every change — a plain
  /// `Map<String, RawPresence>` rather than the repository object itself, so
  /// [presence] rebuilds on every emission rather than once per new instance.
  PresenceMapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'presenceMapProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$presenceMapHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, RawPresence>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, RawPresence>> create(Ref ref) {
    return presenceMap(ref);
  }
}

String _$presenceMapHash() => r'c0ccf660a8437d74c8fed5dc39a0ed47665726eb';

/// One User's presence as this Device should show it right now (#34):
/// `online`/`lastSeen`/`unknown`, already downgraded for our own connection
/// being down. The conversation list and chat header just watch this.

@ProviderFor(presence)
final presenceProvider = PresenceFamily._();

/// One User's presence as this Device should show it right now (#34):
/// `online`/`lastSeen`/`unknown`, already downgraded for our own connection
/// being down. The conversation list and chat header just watch this.

final class PresenceProvider
    extends $FunctionalProvider<PresenceState, PresenceState, PresenceState>
    with $Provider<PresenceState> {
  /// One User's presence as this Device should show it right now (#34):
  /// `online`/`lastSeen`/`unknown`, already downgraded for our own connection
  /// being down. The conversation list and chat header just watch this.
  PresenceProvider._({
    required PresenceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'presenceProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$presenceHash();

  @override
  String toString() {
    return r'presenceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<PresenceState> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PresenceState create(Ref ref) {
    final argument = this.argument as String;
    return presence(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PresenceState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PresenceState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PresenceProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$presenceHash() => r'774a63f3cad494a82a075d4a8764c36b929e6e47';

/// One User's presence as this Device should show it right now (#34):
/// `online`/`lastSeen`/`unknown`, already downgraded for our own connection
/// being down. The conversation list and chat header just watch this.

final class PresenceFamily extends $Family
    with $FunctionalFamilyOverride<PresenceState, String> {
  PresenceFamily._()
    : super(
        retry: null,
        name: r'presenceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One User's presence as this Device should show it right now (#34):
  /// `online`/`lastSeen`/`unknown`, already downgraded for our own connection
  /// being down. The conversation list and chat header just watch this.

  PresenceProvider call(String userId) =>
      PresenceProvider._(argument: userId, from: this);

  @override
  String toString() => r'presenceProvider';
}
