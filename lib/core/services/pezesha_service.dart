// lib/core/services/pezesha_service.dart
//
// Thin wrapper around the Pezesha Cloud Functions (see functions/src/
// pezesha.ts) — shared by both the customer app (customer_bnpl flow)
// and the vendor app (vendor_stock loan flow). Callers pass ownerType
// so the same functions work for either side without duplicating
// Cloud Functions code.
//
// MobiGas is not involved in collecting repayment — Pezesha handles
// that directly against the borrower. Nothing here reads or writes a
// "repayment" concept; loan status is read-only, for display.

import 'package:cloud_functions/cloud_functions.dart';

class PezeshaLoanOffer {
  final double amount;
  final double rate;
  final double fee;
  final int duration;
  final double interest;

  const PezeshaLoanOffer({
    required this.amount,
    required this.rate,
    required this.fee,
    required this.duration,
    required this.interest,
  });

  factory PezeshaLoanOffer.fromMap(Map<String, dynamic> m) {
    return PezeshaLoanOffer(
      amount: (m['amount'] ?? 0).toDouble(),
      rate: double.tryParse('${m['rate']}') ?? 0,
      fee: (m['fee'] ?? 0).toDouble(),
      duration: (m['duration'] ?? 0) is int
          ? m['duration'] as int
          : int.tryParse('${m['duration']}') ?? 0,
      interest: (m['interest'] ?? 0).toDouble(),
    );
  }
}

/// Thrown for any Pezesha-related failure the UI should show as a
/// message rather than a generic error — no eligibility, rejected
/// application, not yet registered, etc.
class PezeshaException implements Exception {
  final String message;
  const PezeshaException(this.message);
  @override
  String toString() => message;
}

class PezeshaService {
  // ── In-memory session cache ─────────────────────────────────────
  // Keyed by ownerType ('customer' | 'vendor') since a signed-in
  // device only ever has one active profile of each type. This is
  // what lets BnplCheckoutSection (customer_bnpl.dart) reuse whatever
  // BnplLimitCard already fetched on the home screen — no explicit
  // prop-drilling or provider wiring between the two screens needed.
  // A cache miss (nothing checked yet this session) transparently
  // falls through to a fresh network call, so checkout still works
  // for a customer who opens it without ever visiting the home card.
  //
  // Call PezeshaService.clearCache() from AuthProvider.logout / the
  // vendor app's equivalent sign-out path — not wired here since this
  // file has no reference to either provider — so a new sign-in on
  // the same device never shows a stale offer left over from the
  // previous account.
  static final Map<String, PezeshaLoanOffer?> _offerCache = {};

  static void clearCache() => _offerCache.clear();

  static String _friendlyError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Please sign in again.';
      case 'failed-precondition':
        return e.message ?? 'This isn\'t available right now.';
      case 'invalid-argument':
        return e.message ?? 'Something about this request wasn\'t valid.';
      case 'not-found':
        // Callable unreachable/undeployed, or borrower not known yet —
        // never surface a raw code like "NOT_FOUND" to a vendor.
        return 'Stock financing isn\'t available right now. '
            'Please try again later.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  /// Registers the CURRENT signed-in user (customer or vendor) as a
  /// Pezesha borrower, if not already registered. Safe to call
  /// repeatedly — returns the existing ID rather than re-registering.
  /// Call this lazily, the first time either BNPL flow is opened, not
  /// during normal signup.
  static Future<String> ensureRegistered({
    required String ownerType, // 'customer' | 'vendor'
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('registerPezeshaBorrower')
          .call({'ownerType': ownerType});
      return result.data['pezeshaId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw PezeshaException(_friendlyError(e));
    }
  }

  /// Returns null if no offer is currently available (thin credit
  /// file, not yet eligible, etc.) rather than throwing — "no limit
  /// yet" is an expected, displayable state, not an error.
  ///
  /// Serves from the session cache by default — pass forceRefresh:
  /// true when the caller wants a guaranteed-live check (e.g. the
  /// home card's explicit "Check my limit" tap), since applying for a
  /// loan re-validates server-side regardless and doesn't depend on
  /// this cache being fresh.
  static Future<PezeshaLoanOffer?> getLoanOffer({
    required String ownerType,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _offerCache.containsKey(ownerType)) {
      return _offerCache[ownerType];
    }
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getPezeshaLoanOffer')
          .call({'ownerType': ownerType});
      final data = result.data as Map;
      final offer = data['available'] != true
          ? null
          : PezeshaLoanOffer.fromMap(
              Map<String, dynamic>.from(data['offer'] as Map),
            );
      _offerCache[ownerType] = offer;
      return offer;
    } on FirebaseFunctionsException catch (e) {
      throw PezeshaException(_friendlyError(e));
    }
  }

  /// Applies for a loan. loanType decides whose limit is used and where
  /// the money lands (see pezesha.ts header comment):
  ///   - 'vendor_stock': vendor is borrower + disbursement target
  ///   - 'customer_bnpl': customer is borrower, targetVendorId is the
  ///     disbursement target (required for this type)
  /// Throws PezeshaException with a user-facing message on rejection
  /// (e.g. "Your last loan was paid late...") — always show e.message
  /// to the user rather than a generic failure banner.
  ///
  /// Invalidates the cached offer for the relevant ownerType on
  /// success, since taking a loan changes the borrower's remaining
  /// limit — the next getLoanOffer call for them will hit the network
  /// again rather than serve a now-stale amount.
  static Future<String> applyLoan({
    required String loanType, // 'vendor_stock' | 'customer_bnpl'
    required double amount,
    String? targetVendorId,
    String? orderId,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('applyPezeshaLoan')
          .call({
            'loanType': loanType,
            'amount': amount,
            if (targetVendorId != null) 'targetVendorId': targetVendorId!,
            if (orderId != null) 'orderId': orderId!,
          });
      final ownerType = loanType == 'vendor_stock' ? 'vendor' : 'customer';
      _offerCache.remove(ownerType);
      return result.data['loanId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw PezeshaException(_friendlyError(e));
    }
  }

  /// Latest loan status, for a status banner/screen. Null if no loan
  /// has ever been taken.
  static Future<Map<String, dynamic>?> getLoanStatus({
    required String ownerType,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getPezeshaLoanStatus')
          .call({'ownerType': ownerType});
      final data = result.data;
      return data == null ? null : Map<String, dynamic>.from(data as Map);
    } on FirebaseFunctionsException catch (e) {
      throw PezeshaException(_friendlyError(e));
    }
  }

  /// Loan history — for a dedicated Loan History screen. This, plus
  /// getLoanStatus, is what satisfies the Google Play requirement to
  /// keep loan terms/status persistently visible, not just at
  /// application time.
  static Future<List<Map<String, dynamic>>> getLoanHistory({
    required String ownerType,
    int page = 1,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('getPezeshaLoanHistory')
          .call({'ownerType': ownerType, 'page': page});
      final data = result.data as List? ?? [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on FirebaseFunctionsException catch (e) {
      throw PezeshaException(_friendlyError(e));
    }
  }
}
