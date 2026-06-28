import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';

class OrderProvider extends ChangeNotifier {
  final List<OrderModel> _orders = [];
  OrderModel? _activeOrder;
  bool _isLoading = false;

  List<OrderModel> get orders => _orders;
  OrderModel? get activeOrder => _activeOrder;
  bool get isLoading => _isLoading;

  Future<void> placeOrder({
    required CustomerModel customer,
    required VendorModel vendor,
    required GasListing listing,
  }) async {
    _isLoading = true;
    notifyListeners();

    await Future.delayed(const Duration(seconds: 1));

    final order = OrderModel(
      orderId: 'MG-${DateTime.now().millisecondsSinceEpoch}',
      customerId: customer.id,
      vendorId: vendor.id,
      vendorName: vendor.businessName,
      vendorPhone: vendor.phone,
      customerName: customer.name,
      customerArea: '${customer.estate}, ${customer.area}',
      listing: listing,
      bankDisbursementAmount: listing.price,
      originationFeeToMobigas: listing.price * 0.01,
      pin: _generatePin(),
      status: OrderStatus.pending,
      createdAt: DateTime.now(),
      partnerBankName: customer.partnerBankName,
    );

    _activeOrder = order;
    _orders.insert(0, order);
    _isLoading = false;
    notifyListeners();
  }

  void updateOrderStatus(String orderId, OrderStatus status) {
    final index = _orders.indexWhere((o) => o.orderId == orderId);
    if (index != -1) {
      _orders[index] = OrderModel(
        orderId: _orders[index].orderId,
        customerId: _orders[index].customerId,
        vendorId: _orders[index].vendorId,
        vendorName: _orders[index].vendorName,
        vendorPhone: _orders[index].vendorPhone,
        customerName: _orders[index].customerName,
        customerArea: _orders[index].customerArea,
        listing: _orders[index].listing,
        bankDisbursementAmount: _orders[index].bankDisbursementAmount,
        originationFeeToMobigas: _orders[index].originationFeeToMobigas,
        pin: _orders[index].pin,
        status: status,
        createdAt: _orders[index].createdAt,
        partnerBankName: _orders[index].partnerBankName,
        riderName: _orders[index].riderName,
        riderPhone: _orders[index].riderPhone,
      );
      if (_activeOrder?.orderId == orderId) {
        _activeOrder = _orders[index];
      }
      notifyListeners();
    }
  }

  String _generatePin() {
    final now = DateTime.now();
    return '${now.second % 9 + 1}${now.millisecond % 9 + 1}${now.minute % 9 + 1}${now.hour % 9 + 1}';
  }

  void clearActiveOrder() {
    _activeOrder = null;
    notifyListeners();
  }
}
