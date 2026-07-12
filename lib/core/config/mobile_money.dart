/// Country-aware mobile money provider info.
/// Mirrors the pattern used by the `Currency` helper.
class MobileMoneyProvider {
  final String code;   // stored value, e.g. 'mpesa', 'mtn', 'airtel', 'tigo', 'till', 'paybill'
  final String label;  // display label, e.g. 'M-Pesa'
  final String hint;   // short helper text shown under the field

  const MobileMoneyProvider({
    required this.code,
    required this.label,
    required this.hint,
  });
}

class MobileMoney {
  MobileMoney._();

  static const _kenya = [
    MobileMoneyProvider(
      code: 'mpesa',
      label: 'M-Pesa',
      hint: 'Customers pay directly to this M-Pesa number on delivery.',
    ),
    MobileMoneyProvider(
      code: 'till',
      label: 'Till (Buy Goods)',
      hint: 'Customers pay to your M-Pesa till (Buy Goods) number.',
    ),
    MobileMoneyProvider(
      code: 'paybill',
      label: 'Paybill',
      hint: 'Customers pay to your paybill. Use this if your business has a dedicated M-Pesa paybill.',
    ),
  ];

  static const _uganda = [
    MobileMoneyProvider(
      code: 'mtn',
      label: 'MTN Mobile Money',
      hint: 'Customers pay directly to this MTN Mobile Money number on delivery.',
    ),
    MobileMoneyProvider(
      code: 'airtel',
      label: 'Airtel Money',
      hint: 'Customers pay directly to this Airtel Money number on delivery.',
    ),
  ];

  static const _tanzania = [
    MobileMoneyProvider(
      code: 'mpesa',
      label: 'M-Pesa',
      hint: 'Customers pay directly to this M-Pesa number on delivery.',
    ),
    MobileMoneyProvider(
      code: 'tigo',
      label: 'Tigo Pesa',
      hint: 'Customers pay directly to this Tigo Pesa number on delivery.',
    ),
    MobileMoneyProvider(
      code: 'airtel',
      label: 'Airtel Money',
      hint: 'Customers pay directly to this Airtel Money number on delivery.',
    ),
  ];

  /// Full list of payment provider options for a given country code (KE/UG/TZ).
  /// Falls back to Kenya's list if the country is unrecognized.
  static List<MobileMoneyProvider> providersFor(String? country) {
    switch (country) {
      case 'UG':
        return _uganda;
      case 'TZ':
        return _tanzania;
      case 'KE':
      default:
        return _kenya;
    }
  }

  /// Look up a provider by its stored code within a given country's list.
  static MobileMoneyProvider providerByCode(String? country, String code) {
    final list = providersFor(country);
    return list.firstWhere(
      (p) => p.code == code,
      orElse: () => list.first,
    );
  }

  /// Short label for plain-text mentions, e.g. "cash or ${MobileMoney.primaryLabelFor(country)}".
  /// KE -> "M-Pesa", UG -> "MTN/Airtel Money", TZ -> "M-Pesa/Tigo Pesa/Airtel Money".
  static String primaryLabelFor(String? country) {
    switch (country) {
      case 'UG':
        return 'MTN/Airtel Money';
      case 'TZ':
        return 'M-Pesa/Tigo Pesa/Airtel Money';
      case 'KE':
      default:
        return 'M-Pesa';
    }
  }

  /// Generic fallback label used where no country context is available yet
  /// (e.g. pre-login onboarding/marketing screens, legal/terms text).
  static const String genericLabel = 'mobile money';

  /// Which payment rail vendors use to pay MobiGas its platform
  /// (customer-finder) fee. Kenya uses Safaricom's Daraja STK Push
  /// directly; Uganda and Tanzania route through Pesapal's hosted
  /// checkout, which itself offers MTN/Airtel Money, Tigo Pesa, cards,
  /// and bank options — so MobiGas doesn't need a separate integration
  /// per provider in those two countries.
  static PlatformFeeProvider feeProviderFor(String? country) {
    switch (country) {
      case 'UG':
      case 'TZ':
        return PlatformFeeProvider.pesapal;
      case 'KE':
      default:
        return PlatformFeeProvider.mpesaStk;
    }
  }
}

enum PlatformFeeProvider { mpesaStk, pesapal }
