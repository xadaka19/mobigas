import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/google_auth_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class VendorSplashScreen extends StatefulWidget {
  const VendorSplashScreen({super.key});

  @override
  State<VendorSplashScreen> createState() => _VendorSplashScreenState();
}

class _VendorSplashScreenState extends State<VendorSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  bool _isLoading = false;
  bool _checkingSession = true;

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
    _controller.forward();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    final user = FirebaseService.auth.currentUser;
    if (user != null) {
      final vendorDoc =
          await FirebaseService.vendors.doc(user.uid).get();
      if (!mounted) return;
      if (vendorDoc.exists) {
        context.go('/vendor-home');
        return;
      } else {
        context.go('/vendor-onboarding');
        return;
      }
    }

    setState(() => _checkingSession = false);
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    final credential = await GoogleAuthService.signInWithGoogle();

    if (!mounted) return;

    if (credential == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Google sign-in failed. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final uid = credential.user!.uid;
    final vendorDoc = await FirebaseService.vendors.doc(uid).get();

    setState(() => _isLoading = false);
    if (!mounted) return;

    if (vendorDoc.exists) {
      context.go('/vendor-home');
    } else {
      context.go('/vendor-onboarding');
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
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _checkingSession
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.orange))
              : Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      const Spacer(),
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.orange,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(Icons.store_rounded,
                            color: AppColors.white, size: 56),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'MobiGas Vendor',
                        style: Theme.of(context)
                            .textTheme
                            .displayLarge
                            ?.copyWith(
                              color: AppColors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Deliver gas. Get paid instantly.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(color: AppColors.gray400),
                      ),
                      const Spacer(),
                      _valueProp(Icons.payments_rounded,
                          'Get paid instantly on every delivery'),
                      const SizedBox(height: 12),
                      _valueProp(Icons.people_outline_rounded,
                          'New customers delivered to you'),
                      const SizedBox(height: 12),
                      _valueProp(Icons.shield_outlined,
                          'Bank pays — zero credit risk to you'),
                      const Spacer(),
                      // Google Sign-In
                      _isLoading
                          ? const CircularProgressIndicator(
                              color: AppColors.orange)
                          : GestureDetector(
                              onTap: _signInWithGoogle,
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Google G logo
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CustomPaint(
                                        painter: _GoogleLogoPainter(),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Continue with Google',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: AppColors.navy,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      const SizedBox(height: 16),
                      Text(
                        'By continuing you agree to our Terms & Privacy Policy',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.gray600,
                                  fontSize: 11,
                                ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _valueProp(IconData icon, String text) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.orange, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.white),
          ),
        ),
      ],
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Blue segment
    final paintBlue = Paint()..color = const Color(0xFF4285F4);
    // Red segment  
    final paintRed = Paint()..color = const Color(0xFFEA4335);
    // Yellow segment
    final paintYellow = Paint()..color = const Color(0xFFFBBC05);
    // Green segment
    final paintGreen = Paint()..color = const Color(0xFF34A853);
    // White center
    final paintWhite = Paint()..color = const Color(0xFFFFFFFF);

    // Draw colored circle segments for G logo
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    // Full circle background - blue
    canvas.drawCircle(center, radius, paintBlue);

    // Red (top-left)
    final rectFull = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rectFull, -2.36, 1.57, true, paintRed);

    // Yellow (bottom-left)
    canvas.drawArc(rectFull, 2.36, 0.79, true, paintYellow);

    // Green (bottom-right)
    canvas.drawArc(rectFull, 3.14, 1.05, true, paintGreen);

    // White inner circle
    canvas.drawCircle(center, radius * 0.6, paintWhite);

    // Blue G bar (right side)
    final barPaint = Paint()..color = const Color(0xFF4285F4);
    final barRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.5, h * 0.35, w * 0.5, h * 0.3),
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(barRect, barPaint);

    // Blue G inner dot
    canvas.drawCircle(
        Offset(w * 0.5, h * 0.5), radius * 0.25, paintBlue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
