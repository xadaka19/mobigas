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

      // Customer: credit application decisions / info requests
      case 'credit_update':
      case 'credit_application':
        if (FlavorConfig.isCustomer) {
          router.push('/credit-application');
        }
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
