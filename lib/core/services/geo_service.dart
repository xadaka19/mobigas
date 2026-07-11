/// GPS → country, decided offline.
///
/// This is deliberately NOT a reverse-geocoding call. The country decides
/// which licence documents a vendor is legally required to upload — an EWURA
/// vendor must never be shown EPRA fields — and that decision cannot depend on
/// a network request succeeding at a new shopfront with patchy signal.
///
/// Kenya, Tanzania and Uganda are enormous and far apart. A bounding box is
/// crude, but at this scale there is no ambiguity: a pin is either hundreds of
/// kilometres inside one country's box or it is not. Address lookup (county,
/// street) is a separate, network-dependent concern handled elsewhere and is
/// allowed to fail — the country is not.
library;

/// Supported country codes. `null` from [countryFromLatLng] means "outside
/// every market we operate in" — a real answer the caller must handle, not an
/// error.
class GeoService {
  const GeoService._();

  /// Axis-aligned bounding boxes. Intentionally generous at the edges — a box
  /// slightly larger than the country is fine because the three are far enough
  /// apart that the boxes do not overlap. Erring toward inclusion inside a
  /// country beats rejecting a genuine vendor near a border.
  ///
  /// [minLat, maxLat, minLng, maxLng]
  static const Map<String, List<double>> _boxes = {
    // Kenya: ~ -4.7..5.5 lat, 33.9..41.9 lng
    'KE': [-4.9, 5.5, 33.9, 42.0],
    // Tanzania: ~ -11.8..-0.9 lat, 29.3..40.5 lng
    'TZ': [-11.8, -0.8, 29.2, 40.6],
    // Uganda: ~ -1.5..4.2 lat, 29.5..35.1 lng
    'UG': [-1.5, 4.3, 29.5, 35.1],
  };

  /// Returns 'KE' | 'TZ' | 'UG', or null if the point is outside all three.
  ///
  /// Kenya and Uganda share a small latitude/longitude overlap around Lake
  /// Victoria's north-east, and Kenya/Tanzania around the south. Boxes are
  /// checked in a fixed order and the first containing box wins; the ordering
  /// below places the more likely market first for the overlap zones. For a
  /// production system with real border-town vendors this is where you would
  /// switch to a polygon test — noted, not needed for launch.
  static String? countryFromLatLng(double lat, double lng) {
    for (final code in ['KE', 'UG', 'TZ']) {
      final b = _boxes[code]!;
      if (lat >= b[0] && lat <= b[1] && lng >= b[2] && lng <= b[3]) {
        return code;
      }
    }
    return null;
  }

  /// Whether a pin falls in any supported market. Convenience for onboarding
  /// gating ("MobiGas isn't in your country yet").
  static bool isSupported(double lat, double lng) =>
      countryFromLatLng(lat, lng) != null;
}

