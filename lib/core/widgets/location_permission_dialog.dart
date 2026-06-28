import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class LocationPermissionDialog {
  // Show before requesting location - required for Play Store compliance
  static Future<bool> requestWithRationale(
    BuildContext context, {
    bool isBackground = false,
  }) async {
    final status = await Geolocator.checkPermission();
    if (status == LocationPermission.always ||
        (!isBackground && status == LocationPermission.whileInUse)) {
      return true;
    }

    if (!context.mounted) return false;

    // Show rationale dialog
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded,
                  color: AppColors.orange, size: 40),
            ),
            const SizedBox(height: 16),
            Text(
              isBackground
                  ? 'Allow background location'
                  : 'Allow location access',
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isBackground
                  ? 'MobiGas needs your location in the background to share your position with the customer during delivery. This stops automatically after delivery is confirmed.'
                  : 'MobiGas uses your location to find nearby gas vendors and to track delivery progress.',
              style: const TextStyle(
                color: AppColors.gray600,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.orangeLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.orange, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isBackground
                          ? 'Select "Allow all the time" on the next screen'
                          : 'Select "While using the app" on the next screen',
                      style: const TextStyle(
                        color: AppColors.orangeDeep,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now',
                style: TextStyle(color: AppColors.gray600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (agreed != true) return false;

    // Request permission
    final result = isBackground
        ? await Geolocator.requestPermission()
        : await Geolocator.requestPermission();

    return result == LocationPermission.always ||
        result == LocationPermission.whileInUse;
  }
}
