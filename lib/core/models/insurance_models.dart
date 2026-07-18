/// Fire & theft stock insurance for vendors — MobiGas is a pure
/// distribution channel here. The underwriting risk sits with the
/// partner insurer (e.g. Lami / Turaco / a licensed insurer we're
/// integrated with); MobiGas never carries the risk itself and only
/// earns a commission on premiums that flow through the platform.
library;

enum InsurancePolicyStatus {
  active,
  expired,
  lapsed, // payment/renewal failed
  cancelled,
}

extension InsurancePolicyStatusExt on InsurancePolicyStatus {
  String get label {
    switch (this) {
      case InsurancePolicyStatus.active:
        return 'Active';
      case InsurancePolicyStatus.expired:
        return 'Expired';
      case InsurancePolicyStatus.lapsed:
        return 'Lapsed';
      case InsurancePolicyStatus.cancelled:
        return 'Cancelled';
    }
  }
}

/// How the sum insured for a policy was determined at purchase time.
/// Kept on the model (not just derivable) because the underlying
/// avgMonthlySales figure changes every month — this freezes WHY this
/// specific policy has the sum insured it has, the same way
/// OrderModel.finderFee is frozen at order time rather than
/// recomputed from current rates.
enum SumInsuredBasis {
  computed, // avgMonthlySales × coverageMultiplier
  starter, // flat starter tier — vendor had <1 month of delivery history
}

/// How many months of their own average sales a vendor wants
/// protected. Fixed set, not a free number — same "safe defaults, no
/// free-text" principle used for the vendor order-history threshold.
enum CoverageMultiplier {
  x1,
  x2,
  x3,
}

extension CoverageMultiplierExt on CoverageMultiplier {
  int get months {
    switch (this) {
      case CoverageMultiplier.x1:
        return 1;
      case CoverageMultiplier.x2:
        return 2;
      case CoverageMultiplier.x3:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case CoverageMultiplier.x1:
        return '1× monthly sales';
      case CoverageMultiplier.x2:
        return '2× monthly sales';
      case CoverageMultiplier.x3:
        return '3× monthly sales';
    }
  }
}

class InsurancePolicyModel {
  final String id;
  final String vendorId;

  /// Which underwriting partner this policy is placed with —
  /// 'lami' | 'turaco' | etc. MobiGas is the distribution channel,
  /// never the risk carrier.
  final String provider;

  /// The underwriter's own policy reference — null until their API
  /// confirms issuance.
  final String? policyNumber;

  final double sumInsured;
  final SumInsuredBasis sumInsuredBasis;
  final CoverageMultiplier? coverageMultiplier; // null when basis == starter

  /// The trailing-average sales figure this policy's sum insured was
  /// computed from, frozen at purchase time. Null when basis ==
  /// starter (no history existed to compute from).
  final double? avgMonthlySalesAtPurchase;

  final double premium;

  /// MobiGas's cut of the premium — commission earned for
  /// distribution, not underwriting. Never charged as a separate
  /// line to the vendor; it's the platform's share of the premium
  /// the underwriter pays out, the same relationship as any
  /// insurance agent's commission.
  final double mobigasCommission;

  final InsurancePolicyStatus status;
  final DateTime startDate;
  final DateTime endDate;
  final String? certificateUrl;
  final DateTime purchasedAt;

  const InsurancePolicyModel({
    required this.id,
    required this.vendorId,
    required this.provider,
    this.policyNumber,
    required this.sumInsured,
    required this.sumInsuredBasis,
    this.coverageMultiplier,
    this.avgMonthlySalesAtPurchase,
    required this.premium,
    required this.mobigasCommission,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.certificateUrl,
    required this.purchasedAt,
  });

  bool get isActive =>
      status == InsurancePolicyStatus.active && endDate.isAfter(DateTime.now());

  int get daysUntilExpiry => endDate.difference(DateTime.now()).inDays;
}
