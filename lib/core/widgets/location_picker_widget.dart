import 'package:flutter/material.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class LocationPickerWidget extends StatefulWidget {
  final String hint;
  final bool darkMode;
  final Function(String address, double lat, double lng) onSelected;
  final String? initialValue;

  const LocationPickerWidget({
    super.key,
    this.hint = 'Search your location...',
    this.darkMode = false,
    required this.onSelected,
    this.initialValue,
  });

  @override
  State<LocationPickerWidget> createState() =>
      _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _hasSelection = false;

  static const String _apiKey =
      'AIzaSyDgTS1Amrsksz6IDb28pirGvRLkxucnZG0';

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      _controller.text = widget.initialValue!;
      _hasSelection = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textColor =
        widget.darkMode ? AppColors.white : AppColors.navy;
    final borderColor = widget.darkMode
        ? AppColors.white.withValues(alpha: 0.2)
        : AppColors.gray200;
    final fillColor = widget.darkMode
        ? AppColors.white.withValues(alpha: 0.05)
        : AppColors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GooglePlaceAutoCompleteTextField(
          textEditingController: _controller,
          googleAPIKey: _apiKey,
          inputDecoration: InputDecoration(
            hintText: widget.hint,
            hintStyle:
                const TextStyle(color: AppColors.gray400),
            prefixIcon: Icon(
              _hasSelection
                  ? Icons.location_on_rounded
                  : Icons.search_rounded,
              color: _hasSelection
                  ? AppColors.success
                  : AppColors.gray400,
              size: 20,
            ),
            suffixIcon: _hasSelection
                ? GestureDetector(
                    onTap: () {
                      _controller.clear();
                      setState(() => _hasSelection = false);
                    },
                    child: const Icon(Icons.clear_rounded,
                        color: AppColors.gray400, size: 18),
                  )
                : null,
            filled: true,
            fillColor: fillColor,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _hasSelection
                    ? AppColors.success
                    : borderColor,
                width: _hasSelection ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppColors.orange, width: 1.5),
            ),
          ),
          debounceTime: 400,
          countries: const ['ke'],
          isLatLngRequired: true,
          getPlaceDetailWithLatLng: (Prediction prediction) {
            final address = prediction.description ?? '';
            final lat =
                double.tryParse(prediction.lat ?? '0') ?? 0.0;
            final lng =
                double.tryParse(prediction.lng ?? '0') ?? 0.0;
            setState(() => _hasSelection = true);
            widget.onSelected(address, lat, lng);
          },
          itemClick: (Prediction prediction) {
            _controller.text = prediction.description ?? '';
            _controller.selection = TextSelection.fromPosition(
              TextPosition(offset: _controller.text.length),
            );
          },
          seperatedBuilder:
              const Divider(height: 1, color: AppColors.gray200),
          containerHorizontalPadding: 0,
          itemBuilder: (context, index, prediction) {
            return ListTile(
              dense: true,
              leading: const Icon(Icons.location_on_outlined,
                  color: AppColors.orange, size: 18),
              title: Text(
                prediction.description ?? '',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.navy),
              ),
            );
          },
          isCrossBtnShown: false,
          textStyle: TextStyle(color: textColor, fontSize: 15),
        ),
        if (_hasSelection) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 14),
              const SizedBox(width: 6),
              Text(
                'Location confirmed',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
