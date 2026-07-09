import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// Explicit contentType for every image we upload.
///
/// storage.rules gates writes on:
///   request.resource.contentType.matches('image/.*')
///
/// putFile(file) with no metadata leaves contentType to the native
/// SDK's guess. When it can't infer one it sends
/// 'application/octet-stream', the rule fails, and the upload returns
/// firebase_storage/unauthorized — which reads like a permissions
/// problem but is really a missing header.
///
/// image_picker re-encodes to JPEG whenever imageQuality < 100, so
/// jpeg is the right default when the extension is missing or odd.
SettableMetadata imageMetadata(File file) {
  const byExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'gif': 'image/gif',
  };
  final parts = file.path.split('.');
  final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
  return SettableMetadata(contentType: byExtension[ext] ?? 'image/jpeg');
}
