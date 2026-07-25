import 'package:mobigas/core/models/app_models.dart';

/// Single source of truth for "is this vendor fee-locked?".
/// Locked => hidden from customers AND blocked from Pezesha stock
/// loans and stock insurance. Suspended, or fees at the per-country
/// threshold (KES-500 equivalent).
class VendorLock {
  const VendorLock._();

  static bool isLocked(Map<String, dynamic> data) {
    if (data['isSuspended'] == true) return true;
    final feesOwed = (data['feesOwed'] ?? 0.0).toDouble();
    final country = (data['country'] as String?) ?? 'KE';
    return feesOwed >= MobiGasFees.thresholdFor(country);
  }
}
