/// Currency display for the customer app.
///
/// The customer never picks a currency. A price is shown in the currency of the
/// VENDOR selling it — you cannot pay a Kenyan vendor in Tanzanian shillings, so
/// currency is a fact about the transaction, not a preference. Every price the
/// customer sees comes from a vendor (or an order), and each of those carries a
/// `country`. This maps that country → symbol and formats the amount.
///
/// This is the offline default, mirroring the countries/{code} Firestore doc so
/// prices render instantly without waiting on a fetch. If you later load the
/// live country config, prefer its symbol; the values here are the fallback.
library;

import 'package:intl/intl.dart';

class Currency {
  final String code; // ISO 4217: KES | TZS | UGX
  final String symbol; // KSh | TSh | USh
  final int decimals; // shown decimals — 0 for all three (gas priced whole)

  const Currency({
    required this.code,
    required this.symbol,
    required this.decimals,
  });

  static const _byCountry = <String, Currency>{
    'KE': Currency(code: 'KES', symbol: 'KSh', decimals: 0),
    'TZ': Currency(code: 'TZS', symbol: 'TSh', decimals: 0),
    'UG': Currency(code: 'UGX', symbol: 'USh', decimals: 0),
  };

  /// Currency for a country code. Defaults to Kenya for an unknown/null code so
  /// a price never renders blank — the customer app should always show *a*
  /// number, and KE is the launch market.
  static Currency forCountry(String? countryCode) =>
      _byCountry[countryCode] ?? _byCountry['KE']!;

  /// Format an amount (major units — gas is priced in whole shillings) for the
  /// given country. e.g. formatFor('KE', 1850) -> "KSh 1,850".
  static String formatFor(String? countryCode, num? amount) {
    final c = forCountry(countryCode);
    final n = amount ?? 0;
    final f = NumberFormat.currency(
      symbol: '${c.symbol} ',
      decimalDigits: c.decimals,
      locale: 'en',
    );
    // NumberFormat.currency puts the symbol tight against the number; the
    // trailing space in `symbol` gives "KSh 1,850" rather than "KSh1,850".
    return f.format(n).trimRight();
  }

  /// Just the symbol for a country — for labels like "Total (KSh)".
  static String symbolFor(String? countryCode) => forCountry(countryCode).symbol;
}
