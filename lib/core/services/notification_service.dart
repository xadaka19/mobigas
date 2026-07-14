import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/services/delivery_notification_service.dart';
import 'package:mobigas/core/services/notification_router.dart';
import 'package:mobigas/core/services/permission_sequencer.dart';

// MUST be top-level function for background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await DeliveryNotificationService.initialize();

  // BUG FIX: notifications were only ever shown as ephemeral OS push
  // notifications — nothing was ever recorded anywhere, so the
  // in-app notification bell had no real history to show at all. Now
  // every notification that actually reaches the device gets a
  // persistent record, regardless of which server-side code sent it.
  await _recordNotification(message);

  // If message has a notification block (credit/loan decisions),
  // Android auto-displays it — don't show a duplicate local notification.
  if (message.notification != null) return;

  // Data-only messages — route by type.
  final data = message.data;
  final title = data['notificationTitle'] ?? data['title'] ?? '';
  final body = data['notificationBody'] ?? data['body'] ?? '';
  final type = data['type'] ?? '';

  if (type == 'order_update' || type == 'delivery') {
    await DeliveryNotificationService.showDeliveryProgress(
      vendorName: data['vendorName'] ?? '',
      gasSize: data['gasSize'] ?? '',
      status: body,
    );
  } else {
    // Everything else (credit updates, new orders, payments, etc.)
    // gets a normal notification with the message's own title.
    await DeliveryNotificationService.showGeneralNotification(
      title: title,
      body: body,
      type: type,
    );
  }
}

/// Persists a received notification so the in-app bell/inbox has a
/// real history, independent of whether the OS-level push is still
/// visible or has already been dismissed. Shared by the background
/// handler (top-level function, above) and the foreground listener
/// (inside NotificationService, below).
Future<void> _recordNotification(RemoteMessage message) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = message.data;
    final title = message.notification?.title ??
        data['notificationTitle'] ??
        data['title'] ??
        '';
    final body = message.notification?.body ??
        data['notificationBody'] ??
        data['body'] ??
        '';
    final type = data['type'] ?? '';
    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': uid,
      'title': title,
      'body': body,
      'type': type,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  } catch (e) {
    debugPrint('Failed to record notification: $e');
  }
}

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Guard so the auth listener is only ever wired up once, even if
  /// initialize() is called more than once across a session.
  static bool _authListenerAttached = false;

  static Future<void> initialize() async {
    try {
      // Request permission
      //
      // BUG FIX: routed through PermissionSequencer instead of called
      // directly. This is the actual notification permission dialog
      // (POST_NOTIFICATIONS on Android 13+) — if it fires while the
      // splash screen's own Geolocator.requestPermission() is also
      // in flight, Android may drop this call's callback or skip
      // showing its dialog entirely. The sequencer guarantees this
      // waits its turn instead of racing.
      await PermissionSequencer.run(
        () => _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        ),
      );

      // Set background handler
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      // CORE FIX (#1): the FCM token used to be fetched and saved
      // exactly once, here in initialize(), which runs from main()
      // BEFORE Firebase Auth has finished restoring the session on a
      // cold start. At that moment currentUser is null, so
      // _saveFcmToken() silently returned and the token was NEVER
      // written to Firestore — leaving the server with no address to
      // push to. Notifications then "queued" and never arrived until
      // the user signed out and back in, which happened to fire a
      // token save while authenticated. Listening to authStateChanges
      // guarantees the token is persisted the instant a real user is
      // available, however long auth restore takes.
      if (!_authListenerAttached) {
        _authListenerAttached = true;
        FirebaseAuth.instance.authStateChanges().listen((user) async {
          if (user != null) {
            try {
              final token = await _messaging.getToken();
              if (token != null) await _saveFcmToken(token);
            } catch (e) {
              debugPrint('Token save on auth change failed: $e');
            }
          }
        });
      }

      // Try an immediate fetch too — covers the case where auth is
      // already resolved (anyone who didn't just cold-start).
      final token = await _messaging.getToken();
      debugPrint('FCM Token: $token');
      if (token != null) {
        await _saveFcmToken(token);
      }

      // Refresh token handler
      _messaging.onTokenRefresh.listen((newToken) {
        _saveFcmToken(newToken);
      });

      // Handle foreground messages — show local notification
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground message: ${message.notification?.title}');
        _showForegroundNotification(message);
      });

      // Handle notification tap when app in background
      // (FCM-displayed notifications; local notification taps are
      // handled inside DeliveryNotificationService via payload).
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('Notification tapped: ${message.data}');
        NotificationRouter.navigateForType(message.data['type']);
      });

      // Handle notification tap when app was terminated.
      // Delay so the splash screen finishes auth + its own redirect
      // first; otherwise our navigation gets overwritten by the
      // splash's context.go().
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        Future.delayed(const Duration(seconds: 3), () {
          NotificationRouter.navigateForType(initialMessage.data['type']);
        });
      }
    } catch (e) {
      // Notification setup must NEVER take down app launch. If any of
      // the above fails, the app still runs; notifications simply
      // degrade until the next successful init or token refresh.
      debugPrint('NotificationService.initialize failed (non-fatal): $e');
    }
  }

  /// Public helper so the auth flow (AuthProvider.register / login)
  /// can force a token save at the exact moment it KNOWS the user's
  /// Firestore doc exists — closing the brand-new-signup race where
  /// the doc is created a beat after the credential lands.
  static Future<void> saveTokenForCurrentUser() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) await _saveFcmToken(token);
    } catch (e) {
      debugPrint('saveTokenForCurrentUser failed: $e');
    }
  }

  static Future<void> _saveFcmToken(String token) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Save to users collection (customer)
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (userDoc.exists) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({
          'fcmToken': token,
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      // Save to vendors collection (vendor)
      final vendorDoc = await FirebaseFirestore.instance
          .collection('vendors')
          .doc(uid)
          .get();
      if (vendorDoc.exists) {
        await FirebaseFirestore.instance
            .collection('vendors')
            .doc(uid)
            .update({
          'fcmToken': token,
          'tokenUpdatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Failed to save FCM token: $e');
    }
  }

  static Future<void> _showForegroundNotification(
      RemoteMessage message) async {
    await DeliveryNotificationService.initialize();
    await _recordNotification(message);

    // If the message carries a notification block, the OS/FCM SDK
    // surfaces it (this happens in the foreground on MIUI and some
    // other OEMs, contrary to the "foreground never auto-displays"
    // assumption). Showing our own on top produced duplicate alerts.
    // Record it for the bell (above) but don't display a second one.
    if (message.notification != null) return;

    // In the foreground Android does NOT auto-display FCM notification
    // payloads, so we show one ourselves — using the message's own
    // title/body, whether it arrived as a notification block or data.
    final data = message.data;
    final title = message.notification?.title ??
        data['notificationTitle'] ??
        data['title'] ??
        '';
    final body = message.notification?.body ??
        data['notificationBody'] ??
        data['body'] ??
        '';
    final type = data['type'] ?? '';

    if (type == 'order_update' || type == 'delivery') {
      await DeliveryNotificationService.showDeliveryProgress(
        vendorName: data['vendorName'] ?? '',
        gasSize: data['gasSize'] ?? '',
        status: body,
      );
    } else {
      await DeliveryNotificationService.showGeneralNotification(
        title: title,
        body: body,
        type: type,
      );
    }
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }
}