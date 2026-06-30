import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

class DeviceFingerprintService {
  /// Returns a SHA-256 hashed device fingerprint.
  /// Uses Android's stable per-device ID — never stores or sends the raw ID.
  static Future<String?> getFingerprint() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;

      // Combine multiple stable device attributes for a more robust fingerprint
      final raw =
          '${androidInfo.id}-${androidInfo.model}-${androidInfo.brand}-${androidInfo.fingerprint}';

      final bytes = utf8.encode(raw);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (_) {
      return null;
    }
  }
}
