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
  late Animation<double> _scaleAnim;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.8, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();

    // Check if already logged in
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    final user = FirebaseService.auth.currentUser;
    if (user != null) {
      // Check if vendor profile exists
      final vendorDoc =
          await FirebaseService.vendors.doc(user.uid).get();
      if (vendorDoc.exists && mounted) {
        context.go('/vendor-home');
      } else if (mounted) {
        context.go('/vendor-onboarding');
      }
    }
    // else stay on splash and show sign-in options
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    final credential = await GoogleAuthService.signInWithGoogle();

    if (credential == null) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Google sign-in cancelled'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      return;
    }

    // Check if vendor profile exists
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
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  const Spacer(),
                  // Logo
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
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.gray400,
                        ),
                  ),
                  const Spacer(),
                  // Value props
                  _valueProp(Icons.payments_rounded,
                      'Get paid instantly on every delivery'),
                  const SizedBox(height: 12),
                  _valueProp(Icons.people_outline_rounded,
                      'New customers delivered to you'),
                  const SizedBox(height: 12),
                  _valueProp(Icons.shield_outlined,
                      'Bank pays — zero credit risk to you'),
                  const Spacer(),
                  // Google Sign-In button
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
                                Image.network(
                                  'https://www.google.com/favicon.ico',
                                  width: 22,
                                  height: 22,
                                  errorBuilder: (context, error, _) => const Icon(
                                    Icons.g_mobiledata_rounded,
                                    size: 24,
                                    color: AppColors.navy,
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.white,
                ),
          ),
        ),
      ],
    );
  }
}
