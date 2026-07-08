import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class OrderProvider extends ChangeNotifier {
  final List<OrderModel> _orders = [];
  OrderModel? _activeOrder;
  bool _isLoading = false;
  String? _error;
  String? _customerId;
  StreamSubscription<List<OrderModel>>? _ordersSub;

  List<OrderModel> get orders => _orders;
  OrderModel? get activeOrder => _activeOrder;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int _watchRetryAttempt = 0;

  void watchOrders(String customerId) {
    _customerId = customerId;
    _watchRetryAttempt = 0;
    _subscribeOrders(customerId);
  }

  void _subscribeOrders(String customerId) {
    // Cancel any previous subscription so we never stack listeners,
    // and always attach onError — an unhandled stream error kills the
    // stream silently and the list stops updating forever.
    _ordersSub?.cancel();
    _ordersSub =
        FirestoreService.watchCustomerOrders(customerId).listen((orders) {
      _watchRetryAttempt = 0; // a successful snapshot resets backoff
      _error = null;
      _orders
        ..clear()
        ..addAll(orders);
      notifyListeners();
    }, onError: (e) {
      debugPrint('Orders stream error: $e');
      // BUG FIX: previously this just logged and gave up — on a
      // fresh install (no local Firestore cache yet), the very first
      // listen attempt is more failure-prone than normal, and a
      // single transient error meant orders simply never appeared
      // again until the customer manually pulled to refresh. Retry
      // with backoff instead, up to 5 times, so it recovers on its
      // own for transient failures.
      if (_watchRetryAttempt < 5) {
        _watchRetryAttempt++;
        Future.delayed(Duration(milliseconds: 800 * _watchRetryAttempt), () {
          if (_customerId == customerId) _subscribeOrders(customerId);
        });
      } else {
        // Retries exhausted — this is very likely a PERMANENT
        // failure (e.g. a missing Firestore composite index), not a
        // transient one, since retrying an identical query just
        // fails identically every time. Surface it instead of
        // leaving the orders list silently, permanently blank.
        _error = e.toString().contains('failed-precondition') ||
                e.toString().contains('index')
            ? 'Could not load orders — a required database index is missing. Contact support.'
            : 'Could not load your orders. Pull down to try again.';
        notifyListeners();
      }
    });
  }

  /// Pull-to-refresh: re-subscribes the orders stream (also revives it
  /// if a previous error killed it).
  Future<void> refreshOrders() async {
    if (_customerId != null) {
      watchOrders(_customerId!);
    }
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    super.dispose();
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
        // Dedupe: the location picker often writes the SAME full
        // address into both estate and area, which used to render as
        // "X, X" everywhere the address shows. Containment (not just
        // equality) also catches the case where one field is the
        // other plus a suffix.
        customerArea: _dedupedArea(customer.estate, customer.area),
        customerPhone: customer.phone,
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

  /// Re-select an order as the active one — used when the customer
  /// taps an in-progress order tile to reopen the tracking screen.
  void setActiveOrder(OrderModel order) {
    _activeOrder = order;
    notifyListeners();
  }

  /// Customer cancels an order the vendor hasn't accepted yet.
  /// Credit orders get their reserved credit released automatically
  /// inside updateOrderStatus.
  Future<void> cancelOrder(OrderModel order) async {
    if (order.status != OrderStatus.pending) return;
    await FirestoreService.updateOrderStatus(
        order.orderId, OrderStatus.cancelled,
        cancelledBy: 'customer');
    if (_activeOrder?.orderId == order.orderId) {
      clearActiveOrder();
    }
  }

  void clearActiveOrder() {
    _activeOrder = null;
    notifyListeners();
  }

  /// Joins estate + area without duplication — if either contains
  /// the other, just use the longer one.
  static String _dedupedArea(String estate, String area) {
    final e = estate.trim();
    final a = area.trim();
    if (e.isEmpty) return a;
    if (a.isEmpty) return e;
    if (e.toLowerCase().contains(a.toLowerCase())) return e;
    if (a.toLowerCase().contains(e.toLowerCase())) return a;
    return '$e, $a';
  }

  String _typeLabel(GasProductType t) {
    switch (t) {
      case GasProductType.refill:
        return 'refill';
      case GasProductType.fullKit:
        return 'gas + cylinder';
      case GasProductType.grillKit:
        return 'gas + cylinder + grill';
      case GasProductType.burner:
        return 'burner';
      case GasProductType.regulator:
        return 'regulator';
      case GasProductType.mekoCooker:
        return 'meko + cooker';
    }
  }

  String _generatePin() {
    final now = DateTime.now();
    final pin =
        ((now.millisecondsSinceEpoch % 9000) + 1000).toString();
    return pin;
  }
}