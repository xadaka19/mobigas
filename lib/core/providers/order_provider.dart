import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class OrderProvider extends ChangeNotifier {
  final List<OrderModel> _orders = [];
  OrderModel? _activeOrder;
  bool _isLoading = false;

  List<OrderModel> get orders => _orders;
  OrderModel? get activeOrder => _activeOrder;
  bool get isLoading => _isLoading;

  void watchOrders(String customerId) {
    FirestoreService.watchCustomerOrders(customerId).listen((orders) {
      _orders.clear();
      _orders.addAll(orders);
      notifyListeners();
    });
  }

  Future<void> placeOrder({
    required CustomerModel customer,
    required VendorModel vendor,
    required GasListing listing,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final order = OrderModel(
        orderId: 'MG-${DateTime.now().millisecondsSinceEpoch}',
        customerId: customer.id,
        vendorId: vendor.id,
        vendorName: vendor.businessName,
        vendorPhone: vendor.phone,
        customerName: customer.name,
        customerArea: '${customer.estate}, ${customer.area}',
        customerLatitude: customer.latitude,
        customerLongitude: customer.longitude,
        listing: listing,
        bankDisbursementAmount: listing.price,
        originationFeeToMobigas:
            listing.price * MobiGasFees.bankCommissionRate,
        pin: _generatePin(),
        status: OrderStatus.pending,
        createdAt: DateTime.now(),
        partnerBankName: customer.partnerBankName,
      );

      // Get vendor FCM token for backend to send push notification
      String? vendorFcmToken;
      try {
        final vendorDoc = await FirebaseService.vendors.doc(vendor.id).get();
        if (vendorDoc.exists) {
          final vData = vendorDoc.data() as Map<String, dynamic>;
          vendorFcmToken = vData['fcmToken'] as String?;
        }
      } catch (_) {}

      // Save to Firestore
      await FirestoreService.createOrder(order);

      // Write vendorFcmToken to order so backend can trigger FCM
      if (vendorFcmToken != null) {
        await FirebaseService.orders
            .where('orderId', isEqualTo: order.orderId)
            .get()
            .then((snap) {
          if (snap.docs.isNotEmpty) {
            snap.docs.first.reference.update({
              'vendorFcmToken': vendorFcmToken,
              'customerFcmToken': customer.fcmToken ?? '',
              'notificationTitle': 'New order received!',
              'notificationBody':
                  '${customer.name} ordered ${listing.size} gas · KES ${listing.price.toStringAsFixed(0)}',
            });
          }
        });
      }

      // Update customer credit used
      await FirestoreService.updateCreditUsed(
          customer.id, listing.price);

      _activeOrder = order;
      _orders.insert(0, order);
    } catch (e) {
      // Handle error
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> confirmDelivery(String orderId) async {
    await FirestoreService.updateOrderStatus(
        orderId, OrderStatus.delivered);
    if (_activeOrder?.orderId == orderId) {
      clearActiveOrder();
    }
  }

  void clearActiveOrder() {
    _activeOrder = null;
    notifyListeners();
  }

  String _generatePin() {
    final now = DateTime.now();
    final pin =
        ((now.millisecondsSinceEpoch % 9000) + 1000).toString();
    return pin;
  }
}
