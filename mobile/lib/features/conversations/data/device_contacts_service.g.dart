// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_contacts_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deviceContactsService)
final deviceContactsServiceProvider = DeviceContactsServiceProvider._();

final class DeviceContactsServiceProvider
    extends
        $FunctionalProvider<
          DeviceContactsService,
          DeviceContactsService,
          DeviceContactsService
        >
    with $Provider<DeviceContactsService> {
  DeviceContactsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceContactsServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceContactsServiceHash();

  @$internal
  @override
  $ProviderElement<DeviceContactsService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeviceContactsService create(Ref ref) {
    return deviceContactsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeviceContactsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeviceContactsService>(value),
    );
  }
}

String _$deviceContactsServiceHash() =>
    r'05a03367d2bf204c7d664bb0d73296033de588f7';
