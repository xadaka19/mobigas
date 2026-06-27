import 'package:flutter/material.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/app.dart';

void main() {
  FlavorConfig.initialize(
    flavor: FlavorType.vendor,
    appName: 'MobiGas Vendor',
    appTitle: 'MobiGas — Vendor App',
  );
  runApp(const MobiGasApp());
}
