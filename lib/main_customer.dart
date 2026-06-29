import 'package:flutter/material.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/app.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mobigas/core/services/notification_service.dart' show NotificationService, firebaseMessagingBackgroundHandler;
import 'package:mobigas/core/services/delivery_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await NotificationService.initialize();
  await DeliveryNotificationService.initialize();
  FlavorConfig.initialize(
    flavor: FlavorType.customer,
    appName: 'MobiGas',
    appTitle: 'MobiGas — Cook now, pay later',
  );
  runApp(const MobiGasApp());
}
