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

  // Firebase core must be ready before anything else touches Firebase.
  await FirebaseService.initialize();

  // App Check is the gate for every Firestore/Storage read under
  // enforcement, so it MUST finish before runApp — otherwise a cold
  // first read (auth gate, profile load) could race ahead of an
  // active attestation and get permission-denied. It's a fast call;
  // it was getToken()/notification setup that made startup slow, and
  // those stay deferred below. Wrapped so a failure can't crash launch.
  try {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
    );
  } catch (e) {
    debugPrint('AppCheck activate failed (non-fatal): $e');
  }

  FlavorConfig.initialize(
    flavor: FlavorType.customer,
    appName: 'MobiGas',
    appTitle: 'MobiGas — Gas delivered in minutes',
  );

  runApp(const MobiGasApp());

  // Cheap, synchronous — safe before the deferred block.
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // BUG FIX: notification init (which prompts the notification
  // permission dialog via _messaging.requestPermission()) used to
  // fire immediately here, right after runApp(). But SplashScreen
  // also requests its own permission (location) a couple seconds
  // into its splash delay. Android only resolves one native
  // permission-request callback at a time — firing two plugin
  // permission requests (firebase_messaging here, geolocator in the
  // splash) close together let one of them win the callback slot
  // and silently starve the other, whose await then hung forever
  // and froze the splash right after the user answered the first
  // dialog. Splash now has a timeout guard as a backstop, but the
  // real fix is not colliding in the first place: delay this call
  // until comfortably after the splash's own permission request
  // window has passed.
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