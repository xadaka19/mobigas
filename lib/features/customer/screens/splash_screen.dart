import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/permission_sequencer.dart';

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

  Future<void> _navigate() async {
    // NOTE: the previous build hard-exited here on two checks — a
    // root/jailbreak block and a client-side APK signature check.
    // The signature check is fundamentally incompatible with Play
    // App Signing: Google re-signs the delivered APK with its own
    // key, so the runtime certificate never matches an upload/debug
    // key baked into the app, and (because the check fails closed)
    // EVERY Play-delivered build was blocked at the splash. App
    // authenticity is already guaranteed by Play App Signing, so
    // that check has been removed entirely.
    //
    // Root detection has also been known to false-positive on stock
    // MIUI/One UI devices; a false positive there previously locked
    // a legitimate user out completely. For a cash-on-delivery app
    // with no financial product, that trade-off isn't worth a hard
    // exit, so it's no longer a gate. (Reintroduce Play Integrity API
    // attestation here if a future feature genuinely needs it.)

    // Run the branded splash delay and the real auth determination
    // concurrently — whichever takes longer is what we actually wait
    // on.
    //
    // BUG FIX: the old code read FirebaseAuth.instance.currentUser
    // synchronously AFTER a fixed 1800ms delay. On a fresh install,
    // Firebase's silently-restored session can still be resolving at
    // that moment, so currentUser could read null even though a
    // valid session was about to restore — sending a genuinely
    // logged-in customer to onboarding/login instead of home.
    // Waiting for the FIRST real authStateChanges() event instead
    // guarantees the correct answer no matter how long Firebase takes.
    // Wait for the first auth event AND the branded delay concurrently,
    // but cap the auth wait so a stalled Firebase stream can never hang
    // the splash forever (previously authStateChanges().first had no
    // timeout — if it never emitted, navigation never fired). On
    // timeout we fall back to currentUser, which is read from disk and
    // is already populated for a returning logged-in user.
    final splashDelay = Future<void>.delayed(const Duration(milliseconds: 1800));
    User? user;
    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .first
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }
    await splashDelay;
    if (!mounted) return;

    // Request location permission.
    //
    // BUG FIX: this request has no timeout, and it turns out that's
    // dangerous, not just slow. main.dart fires the FCM notification
    // permission request (via NotificationService.initialize(), in a
    // fire-and-forget Future right after runApp()) at almost the same
    // moment this splash reaches its own Geolocator permission
    // request. Android resolves only one native permission-request
    // callback at a time; when two plugins (firebase_messaging and
    // geolocator) request permission in close succession, the loser
    // of that race can have its result callback silently dropped —
    // no exception, no completion, the await just hangs forever. That
    // froze the splash indefinitely right after the user tapped
    // "Allow" on the notification dialog, since this Geolocator call
    // never returned and context.go() below never ran. A timeout with
    // a swallowed exception lets the splash proceed regardless; the
    // user can grant location later from wherever it's actually used.
    try {
      final permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 5));
      if (permission == LocationPermission.denied) {
        // BUG FIX: routed through PermissionSequencer instead of
        // called directly, so this can never collide with
        // NotificationService's own permission dialog regardless of
        // exact timing — see permission_sequencer.dart.
        await PermissionSequencer.run(
          () => Geolocator.requestPermission()
              .timeout(const Duration(seconds: 5)),
        );
      }
    } catch (_) {
      // Timed out or errored — proceed without blocking navigation.
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