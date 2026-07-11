import 'package:go_router/go_router.dart';
import 'package:mobigas/features/customer/screens/splash_screen.dart';
import 'package:mobigas/features/customer/screens/onboarding_screen.dart';
import 'package:mobigas/features/customer/screens/register_screen.dart';
import 'package:mobigas/features/customer/screens/home_screen.dart';
import 'package:mobigas/features/customer/screens/order_screen.dart';
import 'package:mobigas/features/customer/screens/order_tracking_screen.dart';
import 'package:mobigas/features/customer/screens/delivery_confirmed_screen.dart';
import 'package:mobigas/features/customer/screens/login_screen.dart';
import 'package:mobigas/core/screens/terms_screen.dart';
import 'package:mobigas/core/screens/delete_account_screen.dart';
import 'package:mobigas/features/customer/screens/edit_profile_screen.dart';
import 'package:mobigas/features/customer/screens/support_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_support_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_splash_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_login_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_onboarding_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_pending_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_home_screen.dart';
import 'package:mobigas/flavors/flavor_config.dart';

class AppRouter {
  // Routes that only make sense in the customer-flavored build.
  // Anything NOT in this set and NOT starting with '/vendor' is
  // treated as shared (terms/privacy/delete-account already read
  // FlavorConfig themselves to render the right audience).
  static const _customerOnlyRoutes = {
    '/onboarding',
    '/register',
    '/home',
    '/order',
    '/order-tracking',
    '/delivery-confirmed',
    '/edit-profile',
    '/support',
    '/login',
  };

  static final router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final path = state.uri.path;

      // Defense-in-depth against deep links / direct navigation to
      // the other flavor's routes. This does NOT replace the
      // account-role checks in AuthProvider.login()/signInWithGoogle()
      // and VendorLoginScreen — those stop a real cross-role account
      // from ever being treated as authenticated in the wrong app.
      // This guard stops navigation to the wrong flavor's screens in
      // the first place, e.g. via a stale bookmark, a malformed deep
      // link, or a future code path that calls context.go('/vendor-
      // home') from customer code by mistake.
      final isVendorRoute = path.startsWith('/vendor');
      if (isVendorRoute && FlavorConfig.isCustomer) {
        return '/';
      }
      if (_customerOnlyRoutes.contains(path) && FlavorConfig.isVendor) {
        return '/';
      }
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
        path: '/edit-profile',
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: '/support',
        builder: (context, state) => const SupportScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) => const TermsScreen(audience: TermsAudience.customer),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, state) => const TermsScreen(
          audience: TermsAudience.customer,
          isPrivacyPolicy: true,
        ),
      ),
      GoRoute(
        path: '/vendor-terms',
        builder: (context, state) => const TermsScreen(audience: TermsAudience.vendor),
      ),
      GoRoute(
        path: '/vendor-privacy',
        builder: (context, state) => const TermsScreen(
          audience: TermsAudience.vendor,
          isPrivacyPolicy: true,
        ),
      ),
      // Shared by both flavors — the screen reads FlavorConfig itself.
      GoRoute(
        path: '/delete-account',
        builder: (context, state) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/vendor-support',
        builder: (context, state) => const VendorSupportScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
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