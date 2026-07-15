import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

import '../../../core/services/geo_service.dart';
import 'supported_country.dart';

/// Confirms (or corrects) the country a vendor's GPS pin resolved to.
///
/// GPS leads, the picker is an escape hatch:
///  • The vendor pins their shop; GeoService.countryFromLatLng gives the
///    country offline. This SHOWS that result rather than offering a blank
///    dropdown a Tanzanian vendor could wrongly set to "Kenya" (and be shown
///    EPRA fields).
///  • "Not right?" opens a picker for genuine edge cases (a border pin on the
///    wrong side). Correcting is one tap but deliberate, not the default.
///  • A pin outside all three markets shows a blocked state; the parent's
///    _step1Valid guard prevents progress.
///
/// Controlled widget — holds no country state, renders [selectedCode] and calls
/// [onCountryChanged], so it stays in sync with the vendor's pin.
///
/// Flags are SVGs via the `country_flags` package — identical on every device.
class CountryConfirmation extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final String? selectedCode;
  final ValueChanged<String?> onCountryChanged;
  final Color accent;

  const CountryConfirmation({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.selectedCode,
    required this.onCountryChanged,
    this.accent = const Color(0xFF00B2CA),
  });

  bool get _hasPin => latitude != null && longitude != null;

  String? get _detectedCode =>
      _hasPin ? GeoService.countryFromLatLng(latitude!, longitude!) : null;

  @override
  Widget build(BuildContext context) {
    if (!_hasPin) return const SizedBox.shrink();

    final detected = _detectedCode;

    if (detected == null && selectedCode == null) {
      return _OutOfMarketCard(accent: accent);
    }

    final effective = SupportedCountry.byCode(selectedCode) ??
        SupportedCountry.byCode(detected);
    if (effective == null) return _OutOfMarketCard(accent: accent);

    final isOverridden =
        detected != null && selectedCode != null && selectedCode != detected;

    return _ConfirmedCard(
      country: effective,
      isOverridden: isOverridden,
      accent: accent,
      onChangeTap: () => _openPicker(context, effective.code),
    );
  }

  Future<void> _openPicker(BuildContext context, String currentCode) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(
        currentCode: currentCode,
        detectedCode: _detectedCode,
        accent: accent,
      ),
    );
    if (chosen != null && chosen != selectedCode) {
      onCountryChanged(chosen);
    }
  }
}

/// A rounded SVG flag at a given size.
Widget _flag(String code, {double height = 26}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: CountryFlag.fromCountryCode(
      code,
      height: height,
      width: height * 4 / 3,
    ),
  );
}

// ── Confirmed state ────────────────────────────────────────────────────────

class _ConfirmedCard extends StatelessWidget {
  final SupportedCountry country;
  final bool isOverridden;
  final Color accent;
  final VoidCallback onChangeTap;

  const _ConfirmedCard({
    required this.country,
    required this.isOverridden,
    required this.accent,
    required this.onChangeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          _flag(country.code, height: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOverridden ? 'Country set to' : 'Detected from your pin',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      country.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D1B40),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      country.dialCode,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                if (isOverridden)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Manually overridden',
                      style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChangeTap,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(isOverridden ? 'Change' : 'Not right?',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Out-of-market state ────────────────────────────────────────────────────

class _OutOfMarketCard extends StatelessWidget {
  final Color accent;
  const _OutOfMarketCard({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.location_off_outlined, color: Colors.red.shade400, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "MobiGas isn't in your area yet",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'We currently operate in Kenya, Tanzania and Uganda. '
                  'Check your pinned location.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Override picker (bottom sheet) ─────────────────────────────────────────

class _CountryPickerSheet extends StatelessWidget {
  final String currentCode;
  final String? detectedCode;
  final Color accent;

  const _CountryPickerSheet({
    required this.currentCode,
    required this.detectedCode,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select your country',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'This sets which licence and permit documents we ask you for, '
                  'so it must match where your business actually operates.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final c in SupportedCountry.all)
            _CountryTile(
              country: c,
              selected: c.code == currentCode,
              isDetected: c.code == detectedCode,
              accent: accent,
              onTap: () => Navigator.of(context).pop(c.code),
            ),
        ],
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final SupportedCountry country;
  final bool selected;
  final bool isDetected;
  final Color accent;
  final VoidCallback onTap;

  const _CountryTile({
    required this.country,
    required this.selected,
    required this.isDetected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            _flag(country.code, height: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Row(
                children: [
                  Text(
                    country.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: const Color(0xFF0D1B40),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    country.dialCode,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                  if (isDetected) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'GPS',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: accent, size: 20),
          ],
        ),
      ),
    );
  }
}