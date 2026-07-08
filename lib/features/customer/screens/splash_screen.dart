import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/security_service.dart';
import 'package:mobigas/core/services/screen_security_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
    _navigate();
  }

  void _showSecurityWarning() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Security Warning'),
        content: const Text(
          'MobiGas cannot run on rooted or jailbroken devices for your security. '
          'Please use a standard device to access the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Future<void> _navigate() async {
    // Security check — block rooted/jailbroken devices
    final isCompromised = await SecurityService.isDeviceCompromised();
    if (isCompromised && mounted) {
      _showSecurityWarning();
      return;
    }

    // Verify app hasn't been repackaged/re-signed by a third party
    if (!kDebugMode) {
      final isAuthentic = await ScreenSecurityService.verifyAppSignature();
      if (!isAuthentic && mounted) {
        _showSecurityWarning();
        return;
      }
    }

    // Run the branded splash delay and the real auth determination
    // concurrently — whichever takes longer is what we actually wait
    // on. This is both a correctness fix and a speed fix:
    //
    // BUG FIX: the old code read FirebaseAuth.instance.currentUser
    // synchronously AFTER a fixed 1800ms delay — and by this point
    // there was already a security check and a signature verification
    // stacked in front of it, both real async work. On a fresh
    // install, Firebase's silently-restored session can still be
    // resolving by the time all of that finishes, so currentUser
    // could read null even though a valid session was a moment from
    // restoring — sending a genuinely logged-in customer to
    // onboarding/login instead of home. Waiting for the FIRST real
    // authStateChanges() event instead guarantees the correct answer
    // no matter how long Firebase actually takes.
    //
    // SPEED FIX: the fixed delay previously ran BEFORE the auth check
    // even started, making total wait time 1800ms + auth-check-time
    // on top of the security/signature checks. Now the delay and the
    // auth check run at once, so this stage takes
    // max(authCheckTime, 1800ms) instead of the sum of both.
    final splashDelay = Future<void>.delayed(const Duration(milliseconds: 1800));
    final userFuture = FirebaseAuth.instance.authStateChanges().first;

    final user = await userFuture;
    await splashDelay;
    if (!mounted) return;

    // Request location permission
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    if (!mounted) return;

    if (user != null) {
      context.go('/home');
    } else {
      final prefs = await SharedPreferences.getInstance();
      final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
      if (!mounted) return;
      if (seenOnboarding) {
        context.go('/login');
      } else {
        await prefs.setBool('seen_onboarding', true);
        if (!mounted) return;
        context.go('/onboarding');
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(
                    Icons.local_fire_department_rounded,
                    color: AppColors.white,
                    size: 56,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'MobiGas',
                  style: Theme.of(context)
                      .textTheme
                      .displayLarge
                      ?.copyWith(
                        color: AppColors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gas delivered in minutes',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}