/// Fire & theft stock insurance — rate table and starter-tier
/// constants. Actual underwriting terms (rate, minimum/maximum sum
/// insured, exclusions) live with the partner insurer and MUST be
/// confirmed with them before these numbers ship — the values below
/// are placeholders wired for the UI/calculation flow, not agreed
/// underwriting rates.
class InsuranceConfig {
  /// ⚠️ PLACEHOLDER — confirm actual rate with underwriting partner
  /// (Lami / Turaco / etc.) before launch. Annual rate as a fraction
  /// of sum insured (e.g. 0.02 = 2% of sum insured per year).
  static const double annualPremiumRate = 0.02;

  /// MobiGas's commission as a fraction of the premium — confirm
  /// with the underwriter's distribution agreement. MobiGas never
  /// charges this separately; it's the platform's share of what the
  /// underwriter collects.
  static const double commissionRate = 0.15;

  /// Flat sum insured (KES) for vendors with less than one month of
  /// delivery history — see minMonthsForComputedTier. TBD with the
  /// underwriting partner; this is a conservative starter figure,
  /// not a final number.
  static const double starterTierSumInsured = 50000;

  /// Minimum months of qualifying delivery history required before a
  /// vendor is switched from the flat starter tier onto the computed
  /// (avgMonthlySales × multiplier) formula. A "qualifying" month is
  /// any trailing month with at least one delivered order — see
  /// InsuranceService.computeAvgMonthlySales.
  static const int minMonthsForComputedTier = 1;

  /// How many trailing months feed the avgMonthlySales average.
  /// 3 months balances smoothing out a single unusually slow/busy
  /// week against staying current enough to track real growth.
  static const int salesLookbackMonths = 3;

  /// Absolute ceiling MobiGas will quote for, regardless of computed
  /// sales — protects against a single anomalous month producing an
  /// unrealistic sum insured. Confirm against the underwriter's own
  /// per-policy maximum.
  static const double maxSumInsured = 2000000;

  static double premiumFor(double sumInsured) =>
      sumInsured * annualPremiumRate;

  static double commissionFor(double premium) => premium * commissionRate;
}
