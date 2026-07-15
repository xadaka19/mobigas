import 'package:flutter/material.dart';
import 'package:mobigas/core/router/app_router.dart';
import 'package:mobigas/flavors/flavor_config.dart';

/// Routes notification taps to the right screen based on the
/// notification's `type`. Used by both FCM notification taps
/// (NotificationService) and local notification taps
/// (DeliveryNotificationService), so keep all routing logic here.
class NotificationRouter {
  static void navigateForType(String? type) {
    final t = type ?? '';
    debugPrint('Notification tap routing, type: $t');
    final router = AppRouter.router;

    switch (t) {
      // Delivery / order status updates
      case 'order_update':
      case 'delivery':
        if (FlavorConfig.isCustomer) {
          router.push('/order-tracking');
        } else {
          router.go('/vendor-home'); // vendor sees orders on home
        }
        break;

      // Vendor: new incoming order
      case 'new_order':
        router.go(FlavorConfig.isCustomer ? '/home' : '/vendor-home');
        break;

      // The vendor couldn't fulfil the customer's order. Land them on
      // home rather than the dead order — home already lists the
      // online vendors near them, so the next tap is a new order
      // instead of a dead end. Sent as type 'order_cancelled' by
      // notifyOrderStatusChange only when the VENDOR cancelled; a
      // customer cancelling their own order gets no push.
      case 'order_cancelled':
        router.go(FlavorConfig.isCustomer ? '/home' : '/vendor-home');
        break;

      // Support chat reply
      case 'support':
        router.push(
            FlavorConfig.isCustomer ? '/support' : '/vendor-support');
        break;

      default:
        // Unknown or missing type — just open the app normally.
        break;
    }
  }
}