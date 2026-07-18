import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mobigas/core/config/insurance_config.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/models/insurance_models.dart';
import 'package:mobigas/core/services/firebase_service.dart';

/// Same unbounded-call guard used elsewhere in the app (see
/// vendor_home_screen.dart, firestore_service.dart) — no Firestore or
/// Functions call in this service should be able to hang forever.
extension _Bounded<T> on Future<T> {
  Future<T> bounded([Duration timeout = const Duration(seconds: 15)]) {
    return this.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Request timed out. Check your connection and try again.',
      ),
    );
  }
}

/// Result of the avgMonthlySales computation — its own type rather
/// than a raw double so the UI can distinguish "no qualifying
/// history, use starter tier" from "here's a real computed average"
/// without a magic-number check (0.0 legitimately means "sold
/// nothing" only once a vendor already has qualifying history).
class SalesHistoryResult {
  final bool hasQualifyingHistory;
  final double avgMonthlySales;
  final int activeMonthsCount;

  const SalesHistoryResult({
    required this.hasQualifyingHistory,
    required this.avgMonthlySales,
    required this.activeMonthsCount,
  });
}

class InsuranceService {
  /// Computes the vendor's trailing-window average monthly sales,
  /// dividing only by months that actually had at least one
  /// delivered order — a vendor with 1 active month of real data is
  /// divided by 1, not diluted by empty months they simply didn't
  /// exist for yet. A quiet month lowers the average; it never
  /// knocks the vendor back onto the starter tier.
  ///
  /// Mirrors the aggregate-query pattern already used for vendor
  /// earnings (_loadEarnings in vendor_home_screen.dart) — sum()
  /// runs server-side, roughly one read per query regardless of
  /// order volume, rather than streaming every order and folding
  /// client-side.
  static Future<SalesHistoryResult> computeAvgMonthlySales(
      String vendorId) async {
    final now = DateTime.now();
    double total = 0;
    int activeMonths = 0;

    for (var i = 0; i < InsuranceConfig.salesLookbackMonths; i++) {
      final monthStart = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(now.year, now.month - i + 1, 1);

      final snap = await FirebaseService.orders
          .where('vendorId', isEqualTo: vendorId)
          .where('status', isEqualTo: OrderStatus.delivered.name)
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(monthEnd))
          .aggregate(sum('gasPrice'))
          .get()
          .bounded();

      final monthSum = snap.getSum('gasPrice') ?? 0;
      if (monthSum > 0) {
        total += monthSum;
        activeMonths++;
      }
    }

    if (activeMonths < InsuranceConfig.minMonthsForComputedTier) {
      return const SalesHistoryResult(
        hasQualifyingHistory: false,
        avgMonthlySales: 0,
        activeMonthsCount: 0,
      );
    }

    return SalesHistoryResult(
      hasQualifyingHistory: true,
      avgMonthlySales: total / activeMonths,
      activeMonthsCount: activeMonths,
    );
  }

  /// Sum insured for a given multiplier, given the vendor's sales
  /// history — capped at InsuranceConfig.maxSumInsured. Returns the
  /// starter-tier figure (and SumInsuredBasis.starter) when the
  /// vendor doesn't yet qualify for computed cover.
  static (double sumInsured, SumInsuredBasis basis) sumInsuredFor({
    required SalesHistoryResult history,
    required CoverageMultiplier multiplier,
  }) {
    if (!history.hasQualifyingHistory) {
      return (InsuranceConfig.starterTierSumInsured, SumInsuredBasis.starter);
    }
    final computed = history.avgMonthlySales * multiplier.months;
    final capped = computed > InsuranceConfig.maxSumInsured
        ? InsuranceConfig.maxSumInsured
        : computed;
    return (capped, SumInsuredBasis.computed);
  }

  /// The vendor's currently active policy, if any. Null when there
  /// isn't one — the UI treats that as "show the purchase flow"
  /// rather than a policy summary card.
  static Stream<InsurancePolicyModel?> watchActivePolicy(String vendorId) {
    return FirebaseFirestore.instance
        .collection('insurance_policies')
        .where('vendorId', isEqualTo: vendorId)
        .where('status', isEqualTo: InsurancePolicyStatus.active.name)
        .orderBy('purchasedAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return null;
      return _policyFromMap(snap.docs.first.id, snap.docs.first.data());
    });
  }

  static InsurancePolicyModel _policyFromMap(
      String id, Map<String, dynamic> data) {
    return InsurancePolicyModel(
      id: id,
      vendorId: data['vendorId'] ?? '',
      provider: data['provider'] ?? '',
      policyNumber: data['policyNumber'],
      sumInsured: (data['sumInsured'] ?? 0).toDouble(),
      sumInsuredBasis: SumInsuredBasis.values.firstWhere(
        (b) => b.name == data['sumInsuredBasis'],
        orElse: () => SumInsuredBasis.starter,
      ),
      coverageMultiplier: data['coverageMultiplier'] != null
          ? CoverageMultiplier.values.firstWhere(
              (m) => m.name == data['coverageMultiplier'],
              orElse: () => CoverageMultiplier.x1,
            )
          : null,
      avgMonthlySalesAtPurchase:
          (data['avgMonthlySalesAtPurchase'] as num?)?.toDouble(),
      premium: (data['premium'] ?? 0).toDouble(),
      mobigasCommission: (data['mobigasCommission'] ?? 0).toDouble(),
      status: InsurancePolicyStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => InsurancePolicyStatus.lapsed,
      ),
      startDate:
          (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endDate: (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      certificateUrl: data['certificateUrl'],
      purchasedAt:
          (data['purchasedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Starts the premium STK push. Mirrors initiateStkPush's contract
  /// in vendor_fees_banner.dart — returns a checkoutRequestId the
  /// caller listens to on stk_transactions.
  ///
  /// ⚠️ SERVER-SIDE WORK NOT INCLUDED HERE: the actual policy
  /// issuance (calling the underwriter's API, writing the
  /// insurance_policies doc, computing the commission split) must
  /// happen in a Cloud Function triggered off payment confirmation —
  /// the same shape as confirmDelivery / onOrderStatusChange already
  /// react to state changes server-side. That function
  /// (issueInsurancePolicy) depends on the underwriting partner's own
  /// API contract (Lami / Turaco / etc.), which isn't finalized yet,
  /// so it isn't written here.
  static Future<String?> initiatePremiumStk({
    required String vendorId,
    required String phone,
    required double sumInsured,
    required double premium,
    required SumInsuredBasis basis,
    CoverageMultiplier? multiplier,
    double? avgMonthlySales,
  }) async {
    final callable = FirebaseFunctions.instance
        .httpsCallable('initiateInsurancePremiumStk');
    final result = await callable.call({
      'vendorId': vendorId,
      'phone': phone,
      'sumInsured': sumInsured,
      'premium': premium,
      'sumInsuredBasis': basis.name,
      'coverageMultiplier': multiplier?.name,
      'avgMonthlySales': avgMonthlySales,
    }).bounded(const Duration(seconds: 20));
    return result.data['checkoutRequestId'] as String?;
  }
}
