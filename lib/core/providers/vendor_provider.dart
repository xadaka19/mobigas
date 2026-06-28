import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';

class VendorProvider extends ChangeNotifier {
  List<VendorModel> _vendors = [];
  bool _isLoading = false;

  List<VendorModel> get vendors => _vendors;
  bool get isLoading => _isLoading;

  List<VendorModel> get onlineVendors =>
      _vendors.where((v) => v.isOnline && v.isVerified).toList();

  Future<void> loadVendors({double? lat, double? lng}) async {
    _isLoading = true;
    notifyListeners();

    // TODO: replace with real Firestore query by location
    await Future.delayed(const Duration(milliseconds: 500));
    _vendors = MockData.vendors;

    _isLoading = false;
    notifyListeners();
  }
}
