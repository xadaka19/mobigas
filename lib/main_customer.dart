import 'package:flutter/material.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/app.dart';

void main() {
  FlavorConfig.initialize(
    flavor: FlavorType.customer,
    appName: 'MobiGas',
    appTitle: 'MobiGas — Gas on Credit',
  );
  runApp(const MobiGasApp());
}
