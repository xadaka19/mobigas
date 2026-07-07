import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/services/delivery_notification_service.dart';
import 'package:mobigas/core/services/notification_router.dart';

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

  static Future<void> initialize() async {
    // Request permission
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Set background handler
    FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler);

    // Get FCM token and save to Firestore
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