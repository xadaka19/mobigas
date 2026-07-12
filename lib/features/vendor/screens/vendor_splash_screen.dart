import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class VendorSplashScreen extends StatefulWidget {
  const VendorSplashScreen({super.key});

  @override
  State<VendorSplashScreen> createState() => _VendorSplashScreenState();
}

class _VendorSplashScreenState extends State<VendorSplashScreen>
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
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _scaleAnim = Tween<double>(
      begin: 0.8,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _controller.forward();
    _navigate();
  }

  Future<void> _navigate() async {
    // NOTE: the previous build hard-exited here if a root/jailbreak
    // check tripped. That check (via the safe_device plugin) is
    // known to false-positive on stock MIUI/One UI devices, and a
    // false positive locked a legitimate vendor out of the app
    // entirely. For a cash-on-delivery app with no financial
    // product, a hard exit isn't worth that risk, so the gate has
    // been removed. (Reintroduce Play Integrity API attestation here
    // if a future feature genuinely needs device attestation.)

    // Run the branded splash delay and the real auth determination
    // concurrently — whichever takes longer is what we actually wait
    // on.
    //
    // BUG FIX: the old code read FirebaseAuth.instance.currentUser
    // synchronously AFTER a fixed 1800ms delay. On a fresh install,
    // Firebase's silently-restored session can still be resolving at
    // that exact moment (cold start + SDK init + Google Play
    // Services credential handshake, all happening for the first
    // time) — so currentUser could read null even though a valid
    // session was a moment from restoring, sending a genuinely
    // logged-in vendor to the login screen. Waiting for the FIRST
    // real authStateChanges() event instead guarantees the correct
    // answer no matter how long Firebase actually takes.
    final splashDelay = Future<void>.delayed(const Duration(milliseconds: 600));
    final userFuture = FirebaseAuth.instance.authStateChanges().first;
    final user = await userFuture;
    await splashDelay;
    if (!mounted) return;
    // Request location permission early
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
    if (!mounted) return;
    if (user != null) {
      context.go('/vendor-home');
    } else {
      context.go('/vendor-login');
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
                  'MobiGas Vendor',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    color: AppColors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Deliver gas. Get paid on every order.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AppColors.gray400),
                ),
                const SizedBox(height: 48),
                const CircularProgressIndicator(
                  color: AppColors.orange,
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
