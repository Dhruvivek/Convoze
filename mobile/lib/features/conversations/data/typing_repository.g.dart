// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'typing_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(typingRepository)
final typingRepositoryProvider = TypingRepositoryProvider._();

final class TypingRepositoryProvider
    extends
        $FunctionalProvider<
          TypingRepository,
          TypingRepository,
          TypingRepository
        >
    with $Provider<TypingRepository> {
  TypingRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'typingRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$typingRepositoryHash();

  @$internal
  @override
  $ProviderElement<TypingRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TypingRepository create(Ref ref) {
    return typingRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TypingRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TypingRepository>(value),
    );
  }
}

String _$typingRepositoryHash() => r'847879412a1f19b429355e4976d2924cf72fdcec';
