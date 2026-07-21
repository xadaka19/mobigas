import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mobigas/core/services/notification_service.dart';
import 'package:mobigas/core/theme/app_theme.dart';

/// Shows whether push notifications are on, and — only when they're
/// not — a toggle to turn them on.
///
/// Signup already asks for this permission once, via
/// NotificationService.initialize() (routed through
/// PermissionSequencer so it doesn't collide with the location
/// prompt). This tile is for the vendor/customer who said no at that
/// point: it's the only in-app way back, short of the OS Settings
/// screen.
///
/// Drop into Edit Profile with `darkMode: true` on the vendor screen
/// (navy background) and `darkMode: false` on the customer screen
/// (light background) to match each screen's existing field styling.
class NotificationPermissionTile extends StatefulWidget {
  final bool darkMode;

  /// Shown under the title only while notifications are OFF — this is
  /// the nudge to turn them on. Once active, this is replaced by
  /// "Active" regardless of what's passed here. Callers should make
  /// this concrete to what the user actually loses by staying off
  /// (e.g. "so you don't miss an order"), not a generic reminder.
  final String inactiveMessage;

  const NotificationPermissionTile({
    super.key,
    this.darkMode = false,
    this.inactiveMessage = 'Turn on to get order and delivery updates',
  });

  @override
  State<NotificationPermissionTile> createState() =>
      _NotificationPermissionTileState();
}

class _NotificationPermissionTileState extends State<NotificationPermissionTile>
    with WidgetsBindingObserver {
  AuthorizationStatus? _status;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Covers the case where the user backgrounds the app to flip the
  // switch in OS Settings (after the "denied" dialog below) and
  // returns — refresh instead of showing a stale toggle.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadStatus();
  }

  Future<void> _loadStatus() async {
    final status = await NotificationService.getAuthorizationStatus();
    if (mounted) setState(() => _status = status);
  }

  // `provisional` (iOS quiet notifications) still counts as on —
  // there's nothing more for the user to grant.
  bool get _isActive =>
      _status == AuthorizationStatus.authorized ||
      _status == AuthorizationStatus.provisional;

  Future<void> _enable() async {
    setState(() => _requesting = true);
    final status = await NotificationService.requestPermission();
    if (!mounted) return;
    setState(() {
      _status = status;
      _requesting = false;
    });

    // Once a user has explicitly denied before, Android 13+/iOS both
    // skip the native dialog entirely on the next request — this call
    // just echoes back `denied` again with nothing shown on screen.
    // System Settings is the only remaining path back in.
    if (status == AuthorizationStatus.denied) {
      _showSettingsPrompt();
    }
  }

  void _showSettingsPrompt() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Notifications are off'),
        content: const Text(
          "Notifications were declined before, so we can't prompt you again "
          "in-app. Turn them on from your phone's Settings to get order and "
          'delivery updates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.darkMode ? AppColors.white : AppColors.navy;
    final subColor = widget.darkMode ? AppColors.gray400 : AppColors.gray600;
    final fillColor = widget.darkMode
        ? AppColors.white.withValues(alpha: 0.05)
        : AppColors.gray100;
    final borderColor = widget.darkMode
        ? AppColors.white.withValues(alpha: 0.2)
        : AppColors.gray200;

    if (_status == null) {
      return Container(
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: const SizedBox(
          height: 18,
          width: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.orange,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_outlined,
            color: AppColors.gray400,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Push notifications',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isActive ? 'Active' : widget.inactiveMessage,
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
              ],
            ),
          ),
          if (_isActive)
            const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 22,
            )
          else if (_requesting)
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.orange,
              ),
            )
          else
            Switch(
              value: false,
              activeThumbColor: AppColors.orange,
              activeTrackColor: AppColors.orange.withOpacity(0.3),
              onChanged: (_) => _enable(),
            ),
        ],
      ),
    );
  }
}
