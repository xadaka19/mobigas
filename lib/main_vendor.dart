import 'package:flutter/material.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/app.dart';
import 'package:mobigas/core/services/notification_service.dart';
import 'package:mobigas/core/services/delivery_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  await NotificationService.initialize();
  await DeliveryNotificationService.initialize();
  FlavorConfig.initialize(
    flavor: FlavorType.vendor,
    appName: 'MobiGas Vendor',
    appTitle: 'MobiGas — Deliver gas. Get paid instantly.',
  );
  runApp(const MobiGasApp());
}
