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

  Future<void> loadVendors({double? lat, double? lng}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snap = await FirebaseService.vendors
          .where('isVerified', isEqualTo: true)
          .get();

      _vendors = snap.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return _vendorFromMap(doc.id, data);
      }).toList();

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
