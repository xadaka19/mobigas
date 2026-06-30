import 'package:flutter/services.dart';

class ScreenSecurityService {
  static const _channel = MethodChannel('mobigas/screen_security');

  /// Prevents screenshots/screen recording (call on sensitive screens)
  static Future<void> enableSecureMode() async {
    try {
      await _channel.invokeMethod('enableSecure');
    } catch (_) {
      // Silently fail if not implemented on platform
    }
  }

  /// Re-enables screenshots (call in dispose)
  static Future<void> disableSecureMode() async {
    try {
      await _channel.invokeMethod('disableSecure');
    } catch (_) {}
  }
}
