import 'dart:io';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/dio_provider.dart';

part 'media_repository.g.dart';

/// A photo or document, once Cloudinary has actually stored it (#40's
/// reduced photos+documents-only scope) — everything `message:send`'s
/// `media` field needs to prove the upload happened and describe it.
class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.publicId,
    required this.version,
    required this.signature,
    required this.resourceType,
    required this.bytes,
    required this.format,
    this.width,
    this.height,
  });

  factory CloudinaryUploadResult.fromResponse(Map<String, dynamic> json) => CloudinaryUploadResult(
    publicId: json['public_id'] as String,
    version: json['version'].toString(),
    signature: json['signature'] as String,
    resourceType: json['resource_type'] as String,
    bytes: json['bytes'] as int,
    format: json['format'] as String? ?? '',
    width: json['width'] as int?,
    height: json['height'] as int?,
  );

  final String publicId;
  final String version;
  final String signature;

  /// `'image'` or `'raw'` (documents) — Cloudinary's own vocabulary.
  final String resourceType;
  final int bytes;
  final String format;
  final int? width;
  final int? height;

  Map<String, dynamic> toJson({String? fileName}) => {
    'publicId': publicId,
    'version': version,
    'signature': signature,
    'resourceType': resourceType,
    'bytes': bytes,
    'format': format,
    'width': ?width,
    'height': ?height,
    'fileName': ?fileName,
  };
}

/// Uploads a photo or document straight to Cloudinary (ADR 0002: Node never
/// touches the bytes) — a signed upload signature comes from this app's own
/// backend first, then the file goes directly to Cloudinary's API.
class MediaRepository {
  MediaRepository(this._dio);

  final Dio _dio;

  Future<CloudinaryUploadResult> uploadImage(File file) => _upload(file, kind: 'image');

  Future<CloudinaryUploadResult> uploadDocument(File file) => _upload(file, kind: 'file');

  Future<CloudinaryUploadResult> _upload(File file, {required String kind}) async {
    final signatureRes = await _dio.post<Map<String, dynamic>>(
      '/media/upload-signature',
      data: {'kind': kind},
    );
    final signature = signatureRes.data!;

    // Exactly the params `signUpload` signed (`backend/src/media/cloudinarySigner.js`):
    // `{public_id, timestamp, type: 'authenticated'}` — Cloudinary rejects
    // the request if this doesn't match what the signature covers.
    final uploadDio = Dio();
    final response = await uploadDio.post<Map<String, dynamic>>(
      signature['uploadUrl'] as String,
      data: FormData.fromMap({
        'public_id': signature['publicId'],
        'timestamp': signature['timestamp'],
        'type': 'authenticated',
        'api_key': signature['apiKey'],
        'signature': signature['signature'],
        'file': await MultipartFile.fromFile(file.path),
      }),
    );
    return CloudinaryUploadResult.fromResponse(response.data!);
  }
}

@Riverpod(keepAlive: true)
MediaRepository mediaRepository(Ref ref) => MediaRepository(ref.watch(dioProvider));
