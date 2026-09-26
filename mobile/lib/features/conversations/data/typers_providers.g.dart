// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'typers_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(typersMap)
final typersMapProvider = TypersMapProvider._();

final class TypersMapProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, Set<String>>>,
          Map<String, Set<String>>,
          Stream<Map<String, Set<String>>>
        >
    with
        $FutureModifier<Map<String, Set<String>>>,
        $StreamProvider<Map<String, Set<String>>> {
  TypersMapProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'typersMapProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$typersMapHash();

  @$internal
  @override
  $StreamProviderElement<Map<String, Set<String>>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<Map<String, Set<String>>> create(Ref ref) {
    return typersMap(ref);
  }
}

String _$typersMapHash() => r'f95e3f83f3a34d58b995df6c5048a4227604d8c1';

/// Who is currently typing in [conversationId] (#35) — the future chat
/// screen's header/message list just watches this; rendering it is out of
/// scope here.

@ProviderFor(typers)
final typersProvider = TypersFamily._();

/// Who is currently typing in [conversationId] (#35) — the future chat
/// screen's header/message list just watches this; rendering it is out of
/// scope here.

final class TypersProvider
    extends $FunctionalProvider<Set<String>, Set<String>, Set<String>>
    with $Provider<Set<String>> {
  /// Who is currently typing in [conversationId] (#35) — the future chat
  /// screen's header/message list just watches this; rendering it is out of
  /// scope here.
  TypersProvider._({
    required TypersFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'typersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$typersHash();

  @override
  String toString() {
    return r'typersProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<Set<String>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Set<String> create(Ref ref) {
    final argument = this.argument as String;
    return typers(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TypersProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$typersHash() => r'f76640303f2b8f853793302f2414236b5b50d9dd';

/// Who is currently typing in [conversationId] (#35) — the future chat
/// screen's header/message list just watches this; rendering it is out of
/// scope here.

final class TypersFamily extends $Family
    with $FunctionalFamilyOverride<Set<String>, String> {
  TypersFamily._()
    : super(
        retry: null,
        name: r'typersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Who is currently typing in [conversationId] (#35) — the future chat
  /// screen's header/message list just watches this; rendering it is out of
  /// scope here.

  TypersProvider call(String conversationId) =>
      TypersProvider._(argument: conversationId, from: this);

  @override
  String toString() => r'typersProvider';
}
