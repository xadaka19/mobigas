import 'package:flutter/material.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class VendorPendingScreen extends StatelessWidget {
  const VendorPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: AppColors.warning, size: 56),
              ),
              const SizedBox(height: 32),
              Text(
                'Application submitted!',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: AppColors.white,
                      fontSize: 26,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Our team will verify your business details within 24 hours. You will receive an SMS on your registered number once approved.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.gray400,
                      height: 1.6,
                    ),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  children: [
                    _pendingStep('Business details verified', true),
                    _pendingStep('ID verification', false),
                    _pendingStep('Location confirmed', false),
                    _pendingStep('Account activated', false),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Questions? Call us on 0800 000 000',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingStep(String label, bool done) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done
                  ? AppColors.success
                  : AppColors.white.withValues(alpha: 0.1),
              border: Border.all(
                color:
                    done ? AppColors.success : AppColors.gray600,
                width: 1.5,
              ),
            ),
            child: done
                ? const Icon(Icons.check_rounded,
                    color: AppColors.white, size: 13)
                : null,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: done ? AppColors.success : AppColors.gray600,
              fontSize: 14,
              fontWeight:
                  done ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
