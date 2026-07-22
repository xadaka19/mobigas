import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firestore_service.dart';


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

  /// Places an order.
  ///
  /// cash: the customer pays the vendor directly on delivery — MobiGas
  /// never touches the money. bnpl: Pezesha has already disbursed the
  /// order amount to the vendor and the customer repays Pezesha
  /// directly; [loanId] is Pezesha's loan reference for this order and
  /// MUST be supplied for a bnpl order (it is attached to
  /// OrderModel.loanId so support can look the loan up by order). Even
  /// for bnpl, MobiGas is not the lender and collects no repayment.
  ///
  /// [orderId] lets the caller pre-generate the id — the bnpl path
  /// needs it known before the loan is applied, so the loan and the
  /// order share one id. When null a fresh id is generated here,
  /// preserving the old behaviour for cash callers that don't pass one.
  ///
  /// The 1% customer-finder fee still accrues on delivery
  /// (confirmDelivery) for BOTH payment methods — financing changes who
  /// the customer pays, not whether the vendor owes the platform fee.
  Future<void> placeOrder({
    required CustomerModel customer,
    required VendorModel vendor,
    required GasListing listing,
    required PaymentMethod paymentMethod,
    String? orderId,
    String? loanId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final order = OrderModel(
        orderId: orderId ?? 'MG-${DateTime.now().millisecondsSinceEpoch}',
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
        country: vendor.country,
        paymentMethod: paymentMethod,
        // Vendor-side customer-finder fee (1%), accrued on delivery.
        // Never shown to the customer anywhere in the app. Applies to
        // bnpl too — the vendor still owes the platform fee on the sale.
        // Computed from the LISTING PRICE only (see
        // GasListing.cashFinderFee): the delivery fee below is
        // deliberately outside it, because 1% is a cut of goods sold,
        // not of the vendor's cost to get the cylinder to the door.
        finderFee: listing.cashFinderFee,
        // The vendor's flat delivery fee, read off their profile HERE
        // and frozen onto the order. effectiveDeliveryFee (not the raw
        // deliveryFee field) is what handles the tri-state: it returns
        // 0 both for a vendor who chose free delivery and for one who
        // has never answered, so an unanswered vendor can never have a
        // charge invented for them. Frozen because a vendor raising
        // their fee tomorrow must not change what this order cost.
        deliveryFee: vendor.effectiveDeliveryFee,
        // Only a bnpl order carries a loan reference; a cash order
        // never does, even if a stray loanId were passed in.
        loanId: paymentMethod == PaymentMethod.bnpl ? loanId : null,
        pin: _generatePin(),
        status: OrderStatus.pending,
        createdAt: DateTime.now(),
      );

      // Save to Firestore. The onOrderCreated Cloud Function handles
      // notifying the vendor server-side (reads their fcmToken and
      // sends the push), so the client no longer writes FCM tokens or
      // notification fields onto the order — that update was being
      // rejected by the orders security rules and failing the whole
      // placeOrder even though the order itself was created.
      await FirestoreService.createOrder(order);

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

  

  String _generatePin() {
    final now = DateTime.now();
    final pin =
        ((now.millisecondsSinceEpoch % 9000) + 1000).toString();
    return pin;
  }
}