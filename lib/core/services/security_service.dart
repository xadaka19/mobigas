import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

class SecurityService {
  /// Returns true if device is rooted/jailbroken
  static Future<bool> isDeviceCompromised() async {
    // Always allow in debug mode for development
    if (kDebugMode) return false;

    try {
      final isJailBroken = await SafeDevice.isJailBroken;

      // Only block on confirmed jailbreak/root
      // Avoid blocking on developer mode alone (too many false positives)
      // isRealDevice can return false on some legitimate devices
      return isJailBroken;
    } catch (_) {
      // If detection fails, allow app to continue
      return false;
    }
  }
}
