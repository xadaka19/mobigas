import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DeliveryNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (_) {},
    );
    _initialized = true;
  }

  static Future<void> showDeliveryProgress({
    required String vendorName,
    required String gasSize,
    required String status,
  }) async {
    await initialize();
    final androidDetails = AndroidNotificationDetails(
      'delivery_channel',
      'Delivery Updates',
      channelDescription: 'Live updates on your gas delivery',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      showWhen: false,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFF97316),
      styleInformation: const BigTextStyleInformation(''),
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: 1001,
      title: 'Gas delivery in progress 🔥',
      body: '$gasSize from $vendorName · $status',
      notificationDetails: details,
    );
  }

  static Future<void> cancelDeliveryNotification() async {
    await _plugin.cancel(id: 1001);
  }

  static Future<void> showDeliveryConfirmed({
    required String gasSize,
    required String amount,
  }) async {
    await initialize();
    final androidDetails = AndroidNotificationDetails(
      'delivery_channel',
      'Delivery Updates',
      channelDescription: 'Live updates on your gas delivery',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF22C55E),
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: 1002,
      title: 'Gas delivered! ✅',
      body: '$gasSize delivered · Repay KES $amount within 30 days',
      notificationDetails: details,
    );
  }
}
