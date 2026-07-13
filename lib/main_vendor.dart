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

  // BUG FIX: see main_customer.dart. Notification init prompts the
  // notification permission dialog; VendorSplashScreen prompts its
  // own location permission dialog a couple seconds later. Android
  // only resolves one native permission-request callback at a time,
  // so firing both close together could starve one of its callback
  // and hang that await forever — freezing the vendor splash right
  // after the vendor answered the notification dialog. The splash
  // now has a timeout guard as a backstop, but delaying this call
  // avoids the collision in the first place.
  Future.delayed(const Duration(milliseconds: 2500), () {
    unawaited(_initNotifications());
  });
}

Future<void> _initNotifications() async {
  try {
    await NotificationService.initialize();
    await DeliveryNotificationService.initialize();
  } catch (e) {
    debugPrint('Notification init failed (non-fatal): $e');
  }
}