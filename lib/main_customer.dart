import 'package:flutter/material.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  FlavorConfig.initialize(
    flavor: FlavorType.customer,
    appName: 'MobiGas',
    appTitle: 'MobiGas — Cook now, pay later',
  );
  runApp(const MobiGasApp());
}
