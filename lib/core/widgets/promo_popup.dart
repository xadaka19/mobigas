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
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: switch (promo.layoutType) {
              'banner' => _buildBannerLayout(context),
              'info' => _buildInfoLayout(context),
              _ => _buildDiscountLayout(context),
            },
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

  /// The original card: MobiGas wordmark/logo, title, "KES X OFF"
  /// highlight, discount badge, and an explicit CTA button. Used for
  /// MobiGas's own promos and any advertiser happy with this frame.
  Widget _buildDiscountLayout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.navy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (promo.isSponsored) _sponsoredTag(context),
          if (promo.isSponsored) const SizedBox(height: 10),
          if (promo.isSponsored && promo.advertiserLogoUrl.isNotEmpty)
            Image.network(
              promo.advertiserLogoUrl,
              height: 32,
              errorBuilder: (_, _, _) => _wordmark(context),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.orange),
                  ),
                );
              },
            ),
          if (promo.isSponsored) ...[
            const SizedBox(height: 12),
            _disclosure(context),
          ],
        ],
      ),
    );
  }

  /// MobiGas's own internal messaging — loan enrollment, feature
  /// announcements, policy updates. Headline + body paragraph, no
  /// discount badge, CTA optional (some announcements are purely
  /// informational and need no action at all).
  Widget _buildInfoLayout(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      color: AppColors.navy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _wordmark(context)),
          const SizedBox(height: 12),
          const Icon(Icons.campaign_rounded, color: AppColors.orange, size: 26),
          const SizedBox(height: 8),
          Text(
            promo.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            promo.bodyText,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  height: 1.5,
                ),
          ),
          if (promo.imageUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            Image.network(
              promo.imageUrl,
              height: 96,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
          if (promo.ctaText.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.orange,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: onCtaTap,
                child: Text(promo.ctaText),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Advertiser's own creative fills the card edge-to-edge, no forced
  /// title/badge/CTA text overlaid on it — the image IS the ad. Only
  /// MobiGas-controlled chrome is the Sponsored tag, close button
  /// (in the parent Stack), and the disclosure line. Tapping anywhere
  /// on the image triggers the same action a CTA button would.
  Widget _buildBannerLayout(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          children: [
            GestureDetector(
              onTap: onCtaTap,
              child: AspectRatio(
                aspectRatio: promo.bannerAspectRatio,
                child: promo.imageUrl.isNotEmpty
                    ? Image.network(
                        promo.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            Container(color: AppColors.navy),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: AppColors.navy,
                            child: const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.orange),
                            ),
                          );
                        },
                      )
                    : Container(color: AppColors.navy),
              ),
            ),
            if (promo.isSponsored)
              Positioned(top: 12, left: 12, child: _sponsoredTag(context)),
          ],
        ),
        if (promo.isSponsored)
          Container(
            width: double.infinity,
            color: AppColors.navy,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _disclosure(context),
          ),
      ],
    );
  }

  Widget _sponsoredTag(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'SPONSORED',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
        ),
      ),
    );
  }

  Widget _disclosure(BuildContext context) {
    return Text(
      '${promo.disclosureText} \u24d8',
      textAlign: TextAlign.center,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: AppColors.gray400, fontSize: 10),
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
