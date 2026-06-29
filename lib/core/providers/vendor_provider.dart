import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class VendorProvider extends ChangeNotifier {
  List<VendorModel> _vendors = [];
  bool _isLoading = false;
  String? _error;

  List<VendorModel> get vendors => _vendors;
  bool get isLoading => _isLoading;
  String? get error => _error;

  List<VendorModel> get onlineVendors =>
      _vendors.where((v) => v.isOnline && v.isVerified).toList();

  static const double _defaultRadiusKm = 8.0; // 8km max — practical gas delivery radius

  Future<void> loadVendors({double? lat, double? lng}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snap = await FirebaseService.vendors
          .where('isVerified', isEqualTo: true)
          .get();

      final allVendors = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _vendorFromMap(doc.id, data);
      }).toList();

      // Filter by distance if customer location is available
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        final nearbyVendors = <VendorModel>[];

        for (final vendor in allVendors) {
          if (vendor.latitude == 0 && vendor.longitude == 0) continue;

          final distKm = _distanceKm(
              lat, lng, vendor.latitude, vendor.longitude);

          if (distKm <= _defaultRadiusKm) {
            // Update distance string
            final updatedVendor = VendorModel(
              id: vendor.id,
              businessName: vendor.businessName,
              ownerName: vendor.ownerName,
              phone: vendor.phone,
              area: vendor.area,
              estate: vendor.estate,
              county: vendor.county,
              latitude: vendor.latitude,
              longitude: vendor.longitude,
              brands: vendor.brands,
              listings: vendor.listings,
              rating: vendor.rating,
              totalReviews: vendor.totalReviews,
              isOnline: vendor.isOnline,
              isVerified: vendor.isVerified,
              distance: _formatDistance(distKm),
              deliveryTime: vendor.deliveryTime,
            );
            nearbyVendors.add(updatedVendor);
          }
        }

        // Sort by distance (closest first)
        nearbyVendors.sort((a, b) {
          final dA = _distanceKm(lat, lng, a.latitude, a.longitude);
          final dB = _distanceKm(lat, lng, b.latitude, b.longitude);
          return dA.compareTo(dB);
        });

        _vendors = nearbyVendors;
      } else {
        // No customer location — show all verified vendors
        _vendors = allVendors;
      }
    } catch (e) {
      _error = 'Could not load vendors. Check your connection.';
      _vendors = [];
    }

    _isLoading = false;
    notifyListeners();
  }

  // Real-time stream of nearby vendors
  Stream<List<VendorModel>> watchVendors() {
    return FirebaseService.vendors
        .where('isVerified', isEqualTo: true)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _vendorFromMap(doc.id, data);
            }).toList());
  }

  // Haversine formula — returns distance in km between two coordinates
  static double _distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0; // Earth radius in km
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).toInt()}m away';
    return '${km.toStringAsFixed(1)}km away';
  }

  VendorModel _vendorFromMap(String id, Map<String, dynamic> data) {
    final listingsData = data['listings'] as List? ?? [];
    return VendorModel(
      id: id,
      businessName: data['businessName'] ?? '',
      ownerName: data['ownerName'] ?? '',
      phone: data['phone'] ?? '',
      area: data['area'] ?? '',
      estate: data['estate'] ?? '',
      county: data['county'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      brands: List<String>.from(data['brands'] ?? []),
      listings: listingsData.map((l) => GasListing(
            size: l['size'] ?? '',
            kg: (l['kg'] ?? 0) as int,
            price: (l['price'] ?? 0).toDouble(),
            available: l['available'] ?? false,
          )).toList(),
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalReviews: (data['totalReviews'] ?? 0) as int,
      isOnline: data['isOnline'] ?? false,
      isVerified: data['isVerified'] ?? false,
      distance: data['distance'] ?? '',
      deliveryTime: data['deliveryTime'] ?? '30–45 min',
    );
  }
}
