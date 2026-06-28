import 'package:go_router/go_router.dart';
import 'package:mobigas/features/customer/screens/splash_screen.dart';
import 'package:mobigas/features/customer/screens/onboarding_screen.dart';
import 'package:mobigas/features/customer/screens/register_screen.dart';
import 'package:mobigas/features/customer/screens/guarantors_screen.dart';
import 'package:mobigas/features/customer/screens/crb_check_screen.dart';
import 'package:mobigas/features/customer/screens/home_screen.dart';
import 'package:mobigas/features/customer/screens/order_screen.dart';
import 'package:mobigas/features/customer/screens/order_tracking_screen.dart';
import 'package:mobigas/features/customer/screens/delivery_confirmed_screen.dart';
import 'package:mobigas/features/customer/screens/login_screen.dart';
import 'package:mobigas/features/customer/screens/credit_application_screen.dart';
import 'package:mobigas/features/customer/screens/terms_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_splash_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_login_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_onboarding_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_pending_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_home_screen.dart';
import 'package:mobigas/flavors/flavor_config.dart';

class AppRouter {
  static final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // TODO: check auth state here when Firebase is wired
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => FlavorConfig.isCustomer
            ? const SplashScreen()
            : const VendorSplashScreen(),
      ),
      // ── Customer routes ──
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: '/credit-application',
        builder: (context, state) => const CreditApplicationScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsScreen(),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const TermsScreen(isPrivacyPolicy: true),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/guarantors',
        builder: (context, state) => const GuarantorsScreen(),
      ),
      GoRoute(
        path: '/bank-approval',
        builder: (context, state) => const CrbCheckScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/order',
        builder: (context, state) => const OrderScreen(),
      ),
      GoRoute(
        path: '/order-tracking',
        builder: (context, state) => const OrderTrackingScreen(),
      ),
      GoRoute(
        path: '/delivery-confirmed',
        builder: (context, state) => const DeliveryConfirmedScreen(),
      ),
      // ── Vendor routes ──
      GoRoute(
        path: '/vendor-login',
        builder: (context, state) => const VendorLoginScreen(),
      ),
      GoRoute(
        path: '/vendor-onboarding',
        builder: (context, state) => const VendorOnboardingScreen(),
      ),
      GoRoute(
        path: '/vendor-pending',
        builder: (context, state) => const VendorPendingScreen(),
      ),
      GoRoute(
        path: '/vendor-home',
        builder: (context, state) => const VendorHomeScreen(),
      ),
    ],
  );
}
