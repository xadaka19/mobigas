import 'package:flutter/foundation.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';

class SecurityService {
  /// Returns true if device is rooted/jailbroken
  static Future<bool> isDeviceCompromised() async {
    // Skip check in debug mode for development
    if (kDebugMode) return false;

    try {
      final isJailbroken = await FlutterJailbreakDetection.jailbroken;
      final isDeveloperMode = await FlutterJailbreakDetection.developerMode;
      return isJailbroken || isDeveloperMode;
    } catch (_) {
      // If detection fails, allow app to continue (fail open for UX)
      return false;
    }
  }
}
