import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/services/delivery_notification_service.dart';

// MUST be top-level function for background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Show local notification when app is in background/terminated
  // Messages are data-only — title/body come from message.data, not
  // message.notification, to avoid Android auto-displaying a duplicate.
  await DeliveryNotificationService.initialize();

  final data = message.data;
  final title = data['title'] ?? 'MobiGas';
  final body = data['body'] ?? '';
  final type = data['type'] ?? '';

  if (type == 'order_update' || type == 'delivery') {
    await DeliveryNotificationService.showDeliveryProgress(
      vendorName: data['vendorName'] ?? '',
      gasSize: data['gasSize'] ?? '',
      status: body,
    );
  } else {
    await DeliveryNotificationService.showDeliveryProgress(
      vendorName: '',
      gasSize: title,
      status: body,
    );
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
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('Notification tapped: ${message.data}');
      _handleNotificationTap(message);
    });

    // Handle notification tap when app terminated
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
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
    final title = message.data['title'] ?? 'MobiGas';
    final body = message.data['body'] ?? '';
    await DeliveryNotificationService.showDeliveryProgress(
      vendorName: '',
      gasSize: title,
      status: body,
    );
  }

  static void _handleNotificationTap(RemoteMessage message) {
    // Navigation handled by app router based on data
    final type = message.data['type'] ?? '';
    debugPrint('Notification type: $type');
    // TODO: use GoRouter to navigate based on type
  }

  static Future<String?> getToken() async {
    return await _messaging.getToken();
  }
}
