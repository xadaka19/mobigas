// lib/core/services/financing_config_service.dart
//
// Reads platform_settings/financing once per screen life — same
// pattern as FirestoreService.getReferralRewardRates. Gates which
// financing UI (the Pezesha cards vs. the old bank-partner referral
// StockBoostCard, or nothing) renders for a given vendor/customer's
// country. Falls back to "not available" on any read failure or
// missing doc, never to "show it anyway" — an unconfigured/unreadable
// gate should hide the feature, not expose a partner in a country
// they haven't confirmed coverage for.
//
// Expected doc shape (platform_settings/financing):
//   { "provider": "pezesha", "supportedCountries": ["KE"] }
// VERIFY these exact field names/values against whatever the admin
// dashboard actually writes — this file is the consumer, not the
// source of truth for the schema.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class FinancingConfig {
  final String provider; // 'pezesha' | 'referral' | 'none'
  final List<String> supportedCountries; // e.g. ['KE']

  const FinancingConfig({
    required this.provider,
    required this.supportedCountries,
  });

  static const none = FinancingConfig(provider: 'none', supportedCountries: []);

  bool get isPezesha => provider == 'pezesha';
  bool coversCountry(String country) => supportedCountries.contains(country);
}

class FinancingConfigService {
  static Future<FinancingConfig> load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('platform_settings')
          .doc('financing')
          .get();
      final data = doc.data();
      if (data == null) return FinancingConfig.none;
      return FinancingConfig(
        provider: (data['provider'] as String?) ?? 'none',
        supportedCountries:
            List<String>.from(data['supportedCountries'] ?? const []),
      );
    } catch (_) {
      return FinancingConfig.none;
    }
  }
}

/// Drop-in gate for wherever the vendor stock-loan card (or the
/// customer BNPL card) is currently placed — the "one-line change"
/// flagged in vendor_pezesha_stock_loan.dart's header comment.
/// Renders nothing while the config loads (avoids a flash of the
/// wrong card), then whichever builder matches: pezeshaBuilder if
/// FeatureFlags.pezeshaFinancing is on AND the config says pezesha AND
/// this country is covered; fallbackBuilder otherwise (pass the old
/// StockBoostCard, or (_) => const SizedBox.shrink() for the customer
/// side, which has no fallback UI).
class FinancingGate extends StatelessWidget {
  final String country;
  final WidgetBuilder pezeshaBuilder;
  final WidgetBuilder fallbackBuilder;

  const FinancingGate({
    super.key,
    required this.country,
    required this.pezeshaBuilder,
    required this.fallbackBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FinancingConfig>(
      future: FinancingConfigService.load(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final config = snap.data!;
        if (config.isPezesha && config.coversCountry(country)) {
          return pezeshaBuilder(context);
        }
        return fallbackBuilder(context);
      },
    );
  }
}
