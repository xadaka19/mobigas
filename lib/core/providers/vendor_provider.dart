import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';

class VendorProvider extends ChangeNotifier {
  List<VendorModel> _vendors = [];
  bool _isLoading = false;
  String? _error;

  List<VendorModel> get vendors => _vendors;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Vendors customers can actually order from: online, verified,
  /// not suspended by admin, and not auto-locked for unpaid fees.
  List<VendorModel> get onlineVendors => _vendors
      .where((v) => v.isOnline && v.isVerified && v.canReceiveOrders)
      .toList();

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
        return FirestoreService.vendorFromMap(doc.id, data);
      }).toList();

      // Filter by distance if customer location is available
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        // Compute each vendor's distance ONCE and carry it alongside
        // the model. The old version called _distanceKm inside the
        // comparator as well as in the filter, so sorting recomputed
        // Haversine 2×log(n) times per load for numbers it had already
        // worked out a moment earlier.
        final nearby = <({VendorModel vendor, double distKm})>[];

        for (final vendor in allVendors) {
          if (vendor.latitude == 0 && vendor.longitude == 0) continue;

          final distKm =
              _distanceKm(lat, lng, vendor.latitude, vendor.longitude);
          if (distKm > _defaultRadiusKm) continue;

          // BUG FIX: this used to hand-build a replacement VendorModel
          // — `VendorModel(id: vendor.id, businessName: ..., ...)` —
          // listing about 18 of the model's fields purely so it could
          // attach a distance string. EVERY field that constructor call
          // didn't mention was silently reset to its default on this
          // path, and this is the path essentially every customer takes
          // (they have a pin, so the distance filter runs).
          //
          // Live consequences before this fix: `country` reset to 'KE',
          // so Currency.formatFor showed KSh on Ugandan and Tanzanian
          // vendors' prices; acceptsPartialPayment/partialPaymentNote
          // reset to false/'', so the "Flexible payment" chip in
          // home_screen._vendorCard never rendered for anyone. No error,
          // no warning — the fields just quietly weren't there.
          //
          // copyWith carries everything forward by default, so the same
          // mistake can't recur when the model gains a field (the new
          // delivery-fee fields would have been swallowed identically).
          nearby.add((
            vendor: vendor.copyWith(distance: _formatDistance(distKm)),
            distKm: distKm,
          ));
        }

        // Sort by distance (closest first), using the values already
        // computed above.
        nearby.sort((a, b) => a.distKm.compareTo(b.distKm));

        _vendors = nearby.map((e) => e.vendor).toList();
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
              return FirestoreService.vendorFromMap(doc.id, data);
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
}