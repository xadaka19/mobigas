import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mobigas/core/services/notification_router.dart';

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
      onDidReceiveNotificationResponse: (response) {
        // Local notification tapped — route by the type we stored
        // as the payload when showing it.
        NotificationRouter.navigateForType(response.payload);
      },
    );
    _initialized = true;
  }

  /// Generic notification — for all non-delivery pushes
  /// (credit updates, new orders, payments, announcements).
  /// Title and body come from the FCM message, never hardcoded.
  /// [type] is stored as the tap payload for navigation.
  static Future<void> showGeneralNotification({
    required String title,
    required String body,
    String type = '',
  }) async {
    if (title.isEmpty && body.isEmpty) return;
    await initialize();
    final androidDetails = AndroidNotificationDetails(
      'general_channel',
      'MobiGas Updates',
      channelDescription: 'Account, credit and order updates',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFFF97316),
      styleInformation: BigTextStyleInformation(body),
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      // Unique ID per message so notifications stack instead of
      // overwriting each other.
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title.isNotEmpty ? title : 'MobiGas',
      body: body,
      notificationDetails: details,
      payload: type,
    );
  }

  /// Ongoing "delivery in progress" notification.
  /// Only for actual delivery tracking (order out for delivery).
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
    final from = vendorName.isNotEmpty ? ' from $vendorName' : '';
    await _plugin.show(
      id: 1001,
      title: 'Gas delivery in progress 🔥',
      body: '$gasSize$from · $status',
      notificationDetails: details,
      payload: 'delivery',
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
      payload: 'order_update',
    );
  }
}