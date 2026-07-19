// lib/core/config/pezesha_config.dart
//
// Single gate for whether the Pezesha financing UI (customer BNPL +
// vendor stock loan) is offered at all. Every mount point asks this
// one method, so "where does BNPL show" has exactly one answer.
//
// Two conditions, both required:
//   1. FeatureFlags.pezeshaFinancing — the global kill switch in
//      app_models.dart. Keep it OFF until Pezesha onboarding reaches
//      Go Live and production API credentials exist.
//   2. Country — Pezesha lends across East Africa (confirmed by
//      Pezesha), which covers every market MobiGas operates in:
//      Kenya, Uganda, and Tanzania.

import 'package:mobigas/core/models/app_models.dart';

class PezeshaConfig {
  const PezeshaConfig._();

  /// Countries where Pezesha is live. Pezesha lends across East
  /// Africa, so this covers all current MobiGas markets.
  static const Set<String> supportedCountries = {'KE', 'UG', 'TZ'};

  /// True when Pezesha financing should be offered to a customer or
  /// vendor in [country]. Null/empty country -> false.
  static bool isAvailableFor(String? country) {
    if (!FeatureFlags.pezeshaFinancing) return false;
    if (country == null) return false;
    return supportedCountries.contains(country);
  }
}
