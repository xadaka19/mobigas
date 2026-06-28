import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';

class VendorAuthProvider extends ChangeNotifier {
  Map<String, dynamic>? _vendorData;
  bool _isOnline = false;
  bool _isLoading = false;
  String? _error;

  Map<String, dynamic>? get vendorData => _vendorData;
  bool get isOnline => _isOnline;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get vendorId => FirebaseService.auth.currentUser?.uid ?? '';
  String get vendorName => _vendorData?['businessName'] ?? '';
  String get vendorPhone => _vendorData?['phone'] ?? '';

  Future<void> loadVendorData() async {
    if (vendorId.isEmpty) return;
    _isLoading = true;
    notifyListeners();

    try {
      final doc = await FirebaseService.vendors.doc(vendorId).get();
      if (doc.exists) {
        _vendorData = doc.data() as Map<String, dynamic>;
        _isOnline = _vendorData?['isOnline'] ?? false;
      }
    } catch (e) {
      _error = 'Failed to load vendor data';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> toggleOnline() async {
    _isOnline = !_isOnline;
    notifyListeners();
    await FirebaseService.vendors.doc(vendorId).update({
      'isOnline': _isOnline,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> acceptOrder(String orderId) async {
    await FirestoreService.updateOrderStatus(
        orderId, OrderStatus.accepted);
  }

  Future<void> declineOrder(String orderId) async {
    await FirestoreService.updateOrderStatus(
        orderId, OrderStatus.defaulted);
  }

  Future<void> markOutForDelivery(String orderId) async {
    await FirestoreService.updateOrderStatus(
        orderId, OrderStatus.outForDelivery);
  }

  Future<bool> confirmPin(String orderId, String pin) async {
    return await FirestoreService.confirmPin(orderId, pin);
  }

  Future<void> confirmDelivery(String orderId) async {
    await FirestoreService.updateOrderStatus(
        orderId, OrderStatus.delivered);
    // TODO: trigger bank disbursement webhook here
    // Backend receives this and calls bank API to pay vendor
  }

  void signOut() {
    FirebaseService.auth.signOut();
  }
}

// Import needed
class FirestoreService {
  static Future<void> updateOrderStatus(
      String orderId, OrderStatus status) async {
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: orderId)
        .get();
    if (snap.docs.isNotEmpty) {
      await snap.docs.first.reference.update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<bool> confirmPin(
      String orderId, String enteredPin) async {
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: orderId)
        .get();
    if (snap.docs.isEmpty) return false;
    final data = snap.docs.first.data() as Map<String, dynamic>;
    return data['pin'] == enteredPin;
  }
}
