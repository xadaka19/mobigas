import 'package:flutter/material.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import '../models/promo_model.dart';

class PromoPopup extends StatelessWidget {
  final PromoModel promo;
  final VoidCallback onCtaTap;
  final VoidCallback onClose;

  const PromoPopup({
    super.key,
    required this.promo,
    required this.onCtaTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (promo.isSponsored)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SPONSORED',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ),
                  ),
                if (promo.isSponsored) const SizedBox(height: 10),
                if (promo.isSponsored && promo.advertiserLogoUrl.isNotEmpty)
                  Image.network(
                    promo.advertiserLogoUrl,
                    height: 32,
                    errorBuilder: (_, __, ___) => _wordmark(context),
                  )
                else
                  _wordmark(context),
                const SizedBox(height: 10),
                Text(
                  promo.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.gray400, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  promo.highlightText,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                      ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    promo.discountText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: onCtaTap,
                  icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                  label: Text(promo.ctaText),
                ),
                const SizedBox(height: 16),
                if (promo.imageUrl.isNotEmpty)
                  Image.network(
                    promo.imageUrl,
                    height: 120,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                        height: 120,
                        child: Center(
                          child: CircularProgressIndicator(
                              color: AppColors.orange),
                        ),
                      );
                    },
                  ),
                if (promo.isSponsored) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${promo.disclosureText} \u24d8',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          Positioned(
            top: -12,
            right: -12,
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    color: AppColors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wordmark(BuildContext context) => Text(
        'MOBIGAS',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
      );
}
