import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/router/app_router.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/providers/vendor_provider.dart';
import 'package:mobigas/flavors/flavor_config.dart';
import 'package:mobigas/core/widgets/vendor_loan_fee_lock_screen.dart';

class MobiGasApp extends StatelessWidget {
  const MobiGasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => VendorProvider()),
      ],
      child: MaterialApp.router(
        title: FlavorConfig.instance.appTitle,
        theme: AppTheme.theme,
        routerConfig: AppRouter.router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => VendorLoanFeeLockGate(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
