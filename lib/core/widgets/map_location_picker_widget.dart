import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/location_service.dart';

/// Map-based location picker used at registration. Replaces the old
/// text-search (google_places_flutter) picker, which called the
/// legacy Places Autocomplete REST endpoint — a call path that gets
/// rejected when the API key's Application restriction is set to
/// Android/iOS app, unlike native Maps SDK rendering used here.
///
/// Centers on the device's current GPS position (same
/// LocationService.getCurrentPosition() call vendor_order_screen.dart
/// already uses), then lets the user fine-tune by dragging the pin
/// or tapping elsewhere on the map — giving an exact lat/lng rather
/// than an address string.
class MapLocationPickerWidget extends StatefulWidget {
  final void Function(double lat, double lng) onLocationSelected;
  final double? initialLat;
  final double? initialLng;

  const MapLocationPickerWidget({
    super.key,
    required this.onLocationSelected,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<MapLocationPickerWidget> createState() =>
      _MapLocationPickerWidgetState();
}

class _MapLocationPickerWidgetState extends State<MapLocationPickerWidget> {
  // Nairobi CBD — only shown briefly if GPS lookup fails before the
  // user drags/taps to set their own pin.
  static const LatLng _fallbackCenter = LatLng(-1.286389, 36.817223);

  GoogleMapController? _mapController;
  LatLng? _pinPosition;
  bool _isLocating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _pinPosition = LatLng(widget.initialLat!, widget.initialLng!);
    } else {
      _useMyLocation();
    }
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _isLocating = true;
      _error = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error =
              'Location services are off. Please enable them, or tap the map to set your location.';
          _isLocating = false;
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _error =
              'Location permission denied. Please allow it in settings, or tap the map to set your location.';
          _isLocating = false;
        });
        return;
      }

      final position = await LocationService.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _pinPosition = latLng;
        _isLocating = false;
      });
      widget.onLocationSelected(latLng.latitude, latLng.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not get your location. Tap the map to set it manually.';
        _isLocating = false;
      });
    }
  }

  void _setPin(LatLng position) {
    setState(() => _pinPosition = position);
    widget.onLocationSelected(position.latitude, position.longitude);
  }

  @override
  Widget build(BuildContext context) {
    final center = _pinPosition ?? _fallbackCenter;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gray200),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition:
                    CameraPosition(target: center, zoom: 15),
                onMapCreated: (c) => _mapController = c,
                onTap: _setPin,
                markers: {
                  if (_pinPosition != null)
                    Marker(
                      markerId: const MarkerId('selected'),
                      position: _pinPosition!,
                      draggable: true,
                      onDragEnd: _setPin,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueOrange),
                    ),
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
              if (_isLocating)
                Container(
                  color: Colors.black.withValues(alpha: 0.15),
                  child: const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.orange),
                  ),
                ),
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: _isLocating ? null : _useMyLocation,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.my_location_rounded,
                        color: AppColors.orange, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_error != null)
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                  fontSize: 11,
                ),
          )
        else
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.gray400, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Drag the pin or tap the map to set your exact spot.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
