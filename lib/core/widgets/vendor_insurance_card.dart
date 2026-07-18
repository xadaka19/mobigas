import 'package:flutter/material.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/models/insurance_models.dart';
import 'package:mobigas/core/services/insurance_service.dart';
import 'package:mobigas/features/vendor/screens/vendor_insurance_screen.dart';

/// Drop into the vendor Earnings tab, same slot as StockBoostCard —
/// see vendor_home_screen.dart's _buildEarningsTab():
///
///   StockBoostCard(vendorId: _vendorId, vendorData: _vendorData),
///   VendorInsuranceCard(vendorId: _vendorId, vendorData: _vendorData),
///
/// Shows either an active-policy summary or a "get covered" prompt —
/// never both. Unlike StockBoostCard, insurance is offered to every
/// vendor rather than gated by an eligibility sweep — wrap the call
/// site in `if (_vendorData?['isVerified'] == true)` if you don't
/// want it shown before verification.
class VendorInsuranceCard extends StatelessWidget {
  final String vendorId;
  final Map<String, dynamic>? vendorData;

  const VendorInsuranceCard({
    super.key,
    required this.vendorId,
    required this.vendorData,
  });

  String get _country => (vendorData?['country'] as String?) ?? 'KE';

  @override
  Widget build(BuildContext context) {
    if (vendorId.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<InsurancePolicyModel?>(
      stream: InsuranceService.watchActivePolicy(vendorId),
      builder: (context, snap) {
        final policy = snap.data;
        final isActive = policy != null && policy.isActive;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VendorInsuranceScreen(
                vendorId: vendorId,
                vendorData: vendorData,
                existingPolicy: policy,
              ),
            ),
          ),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (isActive ? AppColors.success : AppColors.orange)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isActive ? AppColors.success : AppColors.orange)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (isActive ? AppColors.success : AppColors.orange)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isActive
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: isActive ? AppColors.success : AppColors.orange,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive ? 'Stock insured' : 'Insure your stock',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.navy,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isActive
                            ? '${Currency.formatFor(_country, policy.sumInsured)} cover · ${policy.daysUntilExpiry} days left'
                            : 'Fire & theft cover for your gas stock — one tap, instant cover',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.gray600,
                              fontSize: 11,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: AppColors.gray400, size: 14),
              ],
            ),
          ),
        );
      },
    );
  }
}
