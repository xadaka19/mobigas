import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:mobigas/app.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobigas/core/services/notification_service.dart'
    show NotificationService, firebaseMessagingBackgroundHandler;
import 'package:mobigas/core/services/delivery_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FirebaseService.initialize();

  // See main_customer.dart — App Check gates reads, so it blocks
  // runApp; notifications stay deferred.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
    );
  } catch (e) {
    debugPrint('AppCheck activate failed (non-fatal): $e');
  }

  FlavorConfig.initialize(
    flavor: FlavorType.vendor,
    appName: 'MobiGas Vendor',
    appTitle: 'MobiGas — Deliver gas. Get paid instantly.',
  );

  runApp(const MobiGasApp());

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  unawaited(_initNotifications());
}

Future<void> _initNotifications() async {
  try {
    await NotificationService.initialize();
    await DeliveryNotificationService.initialize();
  } catch (e) {
    debugPrint('Notification init failed (non-fatal): $e');
  }
}