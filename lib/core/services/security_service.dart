import 'package:flutter/foundation.dart';
import 'package:safe_device/safe_device.dart';

class SecurityService {
  /// Returns true if device is rooted/jailbroken
  static Future<bool> isDeviceCompromised() async {
    // Skip check in debug mode for development
    if (kDebugMode) return false;

    try {
      final isJailBroken = await SafeDevice.isJailBroken;
      final isDeveloperMode = await SafeDevice.isDevelopmentModeEnable;
      final isRealDevice = await SafeDevice.isRealDevice;
      return isJailBroken || isDeveloperMode || !isRealDevice;
    } catch (_) {
      return false;
    }
  }
}
