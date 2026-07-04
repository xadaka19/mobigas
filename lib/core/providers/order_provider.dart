import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class OrderProvider extends ChangeNotifier {
  final List<OrderModel> _orders = [];
  OrderModel? _activeOrder;
  bool _isLoading = false;
  String? _error;

  List<OrderModel> get orders => _orders;
  OrderModel? get activeOrder => _activeOrder;
  bool get isLoading => _isLoading;
  String? get error => _error;

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
    required PaymentMethod paymentMethod,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final isCash = paymentMethod == PaymentMethod.cash;

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
        paymentMethod: paymentMethod,
        // Vendor-side customer-finder fee (1%) — cash orders only.
        // Never shown to the customer anywhere in the app.
        finderFee: isCash ? listing.cashFinderFee : 0.0,
        // No bank involvement on cash orders.
        bankDisbursementAmount: isCash ? 0.0 : listing.price,
        originationFeeToMobigas:
            isCash ? 0.0 : listing.price * MobiGasFees.bankCommissionRate,
        pin: _generatePin(),
        status: OrderStatus.pending,
        createdAt: DateTime.now(),
        partnerBankName: isCash ? '' : customer.partnerBankName,
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
                  '${customer.name} ordered ${listing.size} ${_typeLabel(listing.productType)} · KES ${listing.price.toStringAsFixed(0)} · ${isCash ? 'CASH on delivery' : 'Paid by bank credit'}',
              'notificationType': 'new_order',
            });
          }
        });
      }

      // Credit orders reserve the customer's bank credit;
      // cash orders don't touch it.
      if (!isCash) {
        await FirestoreService.updateCreditUsed(
            customer.id, listing.price);
      }

      _activeOrder = order;
      _orders.insert(0, order);
    } catch (e) {
      debugPrint('placeOrder failed: $e');
      _error = 'Could not place your order. Please try again.';
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

  /// Customer cancels an order the vendor hasn't accepted yet.
  /// Credit orders get their reserved credit released automatically
  /// inside updateOrderStatus.
  Future<void> cancelOrder(OrderModel order) async {
    if (order.status != OrderStatus.pending) return;
    await FirestoreService.updateOrderStatus(
        order.orderId, OrderStatus.cancelled);
    if (_activeOrder?.orderId == order.orderId) {
      clearActiveOrder();
    }
  }

  void clearActiveOrder() {
    _activeOrder = null;
    notifyListeners();
  }

  String _typeLabel(GasProductType t) {
    switch (t) {
      case GasProductType.refill:
        return 'refill';
      case GasProductType.fullKit:
        return 'gas + cylinder';
      case GasProductType.grillKit:
        return 'gas + cylinder + grill';
    }
  }

  String _generatePin() {
    final now = DateTime.now();
    final pin =
        ((now.millisecondsSinceEpoch % 9000) + 1000).toString();
    return pin;
  }
}