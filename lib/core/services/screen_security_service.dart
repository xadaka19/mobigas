import 'package:flutter/services.dart';

class ScreenSecurityService {
  static const _channel = MethodChannel('mobigas/screen_security');

  /// Prevents screenshots/screen recording (call on sensitive screens)
  static Future<void> enableSecureMode() async {
    try {
      await _channel.invokeMethod('enableSecure');
    } catch (_) {}
  }

  /// Re-enables screenshots (call in dispose)
  static Future<void> disableSecureMode() async {
    try {
      await _channel.invokeMethod('disableSecure');
    } catch (_) {}
  }

  /// Verifies the running app's signing certificate matches MobiGas's
  /// official release signature. Returns false if the APK has been
  /// repackaged/re-signed by someone other than MobiGas.
  static Future<bool> verifyAppSignature() async {
    try {
      final result = await _channel.invokeMethod<bool>('verifySignature');
      return result ?? false;
    } catch (_) {
      // Fail closed in release builds — if we can't verify, assume compromised
      return false;
    }
  }
}
