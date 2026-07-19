// lib/core/config/pezesha_config.dart
//
// Single gate for whether the Pezesha financing UI (customer BNPL +
// vendor stock loan) is offered at all. Every mount point — the
// customer home card, the customer checkout section, and the vendor
// earnings card — asks this one method, so "where does BNPL show" has
// exactly one answer.
//
// Two conditions, both required:
//   1. FeatureFlags.pezeshaFinancing — the global kill switch in
//      app_models.dart. Flip it false to remove every Pezesha surface
//      instantly, without touching call sites.
//   2. Country — Pezesha is licensed/operational in Kenya and Uganda
//      only. A TZ vendor or customer never sees it, even with the flag
//      on.

import 'package:mobigas/core/models/app_models.dart';

class PezeshaConfig {
  const PezeshaConfig._();

  /// Countries where Pezesha is live. Kenya and Uganda only.
  static const Set<String> supportedCountries = {'KE', 'UG'};

  /// True when Pezesha financing should be offered to a customer or
  /// vendor in [country]. Null/empty country -> false.
  static bool isAvailableFor(String? country) {
    if (!FeatureFlags.pezeshaFinancing) return false;
    if (country == null) return false;
    return supportedCountries.contains(country);
  }
}
