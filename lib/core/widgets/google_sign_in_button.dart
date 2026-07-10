import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:mobigas/core/theme/app_theme.dart';

/// Same treatment as the vendor login button, reusable across the
/// customer login and register screens.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.label = 'Continue with Google',
    this.onDark = false,
  });

  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  /// True when the button sits on the navy header rather than the
  /// warm form background — flips the border off.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 56,
        child: Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.orange,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: onDark ? null : Border.all(color: AppColors.gray200),
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
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "or" rule used between the Google button and the email form.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.gray200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  fontSize: 12,
                ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.gray200)),
      ],
    );
  }
}
