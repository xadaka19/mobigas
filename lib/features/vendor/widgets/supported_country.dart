/// Static reference data for the three supported markets.
///
/// No flag emoji here anymore — flags are rendered as SVGs by the
/// `country_flags` package in the widget layer, so they look identical on every
/// device regardless of system font. This class is pure data: code, name, dial
/// code. The country DECISION still comes from GeoService (the GPS pin); this
/// only labels the resulting code.
library;

class SupportedCountry {
  final String code; // 'KE' | 'TZ' | 'UG' — matches GeoService + Firestore
  final String name;
  final String dialCode; // for the phone field, shown in the picker

  const SupportedCountry({
    required this.code,
    required this.name,
    required this.dialCode,
  });

  static const ke = SupportedCountry(code: 'KE', name: 'Kenya', dialCode: '+254');
  static const tz = SupportedCountry(code: 'TZ', name: 'Tanzania', dialCode: '+255');
  static const ug = SupportedCountry(code: 'UG', name: 'Uganda', dialCode: '+256');

  /// In display order.
  static const List<SupportedCountry> all = [ke, tz, ug];

  /// Look up by code. Returns null for an unknown/null code so callers must
  /// decide what "not in a market" means rather than getting a silent default.
  static SupportedCountry? byCode(String? code) {
    for (final c in all) {
      if (c.code == code) return c;
    }
    return null;
  }
}