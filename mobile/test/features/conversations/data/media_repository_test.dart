import 'package:convoze/features/conversations/data/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CloudinaryUploadResult.fromResponse', () {
    // Cloudinary's `image` uploads include a `format` field.
    test('uses the response format when present', () {
      final result = CloudinaryUploadResult.fromResponse({
        'public_id': 'u/1/abc',
        'version': 42,
        'signature': 'sig',
        'resource_type': 'image',
        'bytes': 123,
        'format': 'png',
      }, fallbackFormat: 'jpg');

      expect(result.format, 'png');
    });

    // Cloudinary's `raw` (document) uploads never include a `format` field —
    // confirmed directly against the real API. Without a fallback this used
    // to become '', which `validateMedia` on the backend rejects
    // unconditionally, failing every document send (#40 regression).
    test('falls back to the picked file\'s extension when the response omits format', () {
      final result = CloudinaryUploadResult.fromResponse({
        'public_id': 'u/1/abc.pdf',
        'version': 42,
        'signature': 'sig',
        'resource_type': 'raw',
        'bytes': 123,
      }, fallbackFormat: 'pdf');

      expect(result.format, 'pdf');
    });

    test('is empty when neither the response nor a fallback has a format', () {
      final result = CloudinaryUploadResult.fromResponse({
        'public_id': 'u/1/abc',
        'version': 42,
        'signature': 'sig',
        'resource_type': 'raw',
        'bytes': 123,
      });

      expect(result.format, '');
    });
  });
}
