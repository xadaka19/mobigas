import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/google_auth_service.dart';

class VendorLoginScreen extends StatefulWidget {
  const VendorLoginScreen({super.key});

  @override
  State<VendorLoginScreen> createState() => _VendorLoginScreenState();
}

class _VendorLoginScreenState extends State<VendorLoginScreen> {
  bool _isLoading = false;

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

    setState(() => _isLoading = false);
    if (!mounted) return;
    // Always go to home — setup happens inside the dashboard
    context.go('/vendor-home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              // Logo
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: AppColors.white,
                  size: 52,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'MobiGas Vendor',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: AppColors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Deliver gas. Get paid on every order.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
              const Spacer(),
              // Value props
              _valueProp(Icons.payments_rounded,
                  'Get paid on every delivery — M-Pesa or cash'),
              const SizedBox(height: 12),
              _valueProp(Icons.people_outline_rounded,
                  'New customers delivered to you'),
              const SizedBox(height: 12),
              _valueProp(Icons.shield_outlined,
                  'Credit orders: the bank pays you in seconds'),
              const Spacer(),
              // Google Sign-In button
              _isLoading
                  ? const CircularProgressIndicator(color: AppColors.orange)
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
                            SvgPicture.asset(
                              'assets/icon/google_icon.svg',
                              width: 24,
                              height: 24,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('By continuing you agree to our ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontSize: 11,
                          )),
                  GestureDetector(
                    onTap: () => context.push('/terms'),
                    child: Text('Terms',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.orange,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                            )),
                  ),
                  Text(' & ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontSize: 11,
                          )),
                  GestureDetector(
                    onTap: () => context.push('/privacy'),
                    child: Text('Privacy Policy',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.orange,
                              fontSize: 11,
                              decoration: TextDecoration.underline,
                            )),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
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