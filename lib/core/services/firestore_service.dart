import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';

class FirestoreService {
  // ── USERS ─────────────────────────────────────────────────────────
  // Check if phone or national ID already registered
  static Future<Map<String, bool>> checkDuplicates({
    required String phone,
    required String nationalId,
  }) async {
    final phoneSnap = await FirebaseService.users
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();

    final idSnap = await FirebaseService.users
        .where('nationalId', isEqualTo: nationalId)
        .limit(1)
        .get();

    return {
      'phoneTaken': phoneSnap.docs.isNotEmpty,
      'idTaken': idSnap.docs.isNotEmpty,
    };
  }

  // Load full customer data including guarantors from Firestore
  static Future<CustomerModel?> getUserByPhone(String phone) async {
    final snap = await FirebaseService.users
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data() as Map<String, dynamic>;
    return _customerFromMap(snap.docs.first.id, data);
  }

  static Future<void> createUser(CustomerModel customer) async {
    await FirebaseService.users.doc(customer.id).set({
      'id': customer.id,
      'name': customer.name,
      'phone': customer.phone,
      'nationalId': customer.nationalId,
      'county': customer.county,
      'area': customer.area,
      'estate': customer.estate,
      'latitude': customer.latitude,
      'longitude': customer.longitude,
      'bankStatus': customer.bankStatus.name,
      'bankApprovedLimit': customer.bankApprovedLimit,
      'bankCreditUsed': customer.bankCreditUsed,
      'partnerBankName': customer.partnerBankName,
      'guarantors': customer.guarantors
          .map((g) => {'name': g.name, 'phone': g.phone})
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<CustomerModel?> getUser(String uid) async {
    final doc = await FirebaseService.users.doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    return _customerFromMap(uid, data);
  }

  static Future<void> updateUserBankStatus({
    required String uid,
    required BankApprovalStatus status,
    double? approvedLimit,
    String? bankName,
  }) async {
    final data = <String, dynamic>{
      'bankStatus': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (approvedLimit != null) data['bankApprovedLimit'] = approvedLimit;
    if (bankName != null) data['partnerBankName'] = bankName;
    await FirebaseService.users.doc(uid).update(data);
  }

  static Future<void> updateCreditUsed(String uid, double amount) async {
    await FirebaseService.users.doc(uid).update({
      'bankCreditUsed': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static CustomerModel _customerFromMap(
      String uid, Map<String, dynamic> data) {
    return CustomerModel(
      id: uid,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      nationalId: data['nationalId'] ?? '',
      county: data['county'] ?? '',
      area: data['area'] ?? '',
      estate: data['estate'] ?? '',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      bankApprovedLimit: data['bankApprovedLimit']?.toDouble(),
      bankCreditUsed: (data['bankCreditUsed'] ?? 0.0).toDouble(),
      bankStatus: BankApprovalStatus.values.firstWhere(
        (e) => e.name == data['bankStatus'],
        orElse: () => BankApprovalStatus.pending,
      ),
      partnerBankName: data['partnerBankName'] ?? '',
      guarantors: (data['guarantors'] as List? ?? [])
          .map((g) => GuarantorModel(
                name: g['name'] ?? '',
                phone: g['phone'] ?? '',
              ))
          .toList(),
      selfieUrl: data['selfieUrl'],
      fcmToken: data['fcmToken'],
    );
  }

  // ── VENDORS ───────────────────────────────────────────────────────
  static Future<void> createVendor(Map<String, dynamic> vendorData) async {
    await FirebaseService.vendors.add({
      ...vendorData,
      'isVerified': false,
      'isOnline': false,
      'rating': 0.0,
      'totalReviews': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<List<VendorModel>> getNearbyVendors({
    required double lat,
    required double lng,
  }) async {
    // TODO: use GeoFlutterFire for radius queries
    // For now fetch all verified vendors
    final snap = await FirebaseService.vendors
        .where('isVerified', isEqualTo: true)
        .get();

    return snap.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return _vendorFromMap(doc.id, data);
    }).toList();
  }

  static VendorModel _vendorFromMap(
      String id, Map<String, dynamic> data) {
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
      listings: listingsData
          .map((l) => GasListing(
                size: l['size'] ?? '',
                kg: l['kg'] ?? 0,
                price: (l['price'] ?? 0).toDouble(),
                available: l['available'] ?? false,
              ))
          .toList(),
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalReviews: data['totalReviews'] ?? 0,
      isOnline: data['isOnline'] ?? false,
      isVerified: data['isVerified'] ?? false,
      distance: data['distance'] ?? '',
      deliveryTime: data['deliveryTime'] ?? '30–45 min',
    );
  }

  // ── ORDERS ────────────────────────────────────────────────────────
  static Future<String> createOrder(OrderModel order) async {
    final ref = await FirebaseService.orders.add({
      'orderId': order.orderId,
      'customerId': order.customerId,
      'vendorId': order.vendorId,
      'vendorName': order.vendorName,
      'vendorPhone': order.vendorPhone,
      'customerName': order.customerName,
      'customerArea': order.customerArea,
      'gasSize': order.listing.size,
      'gasKg': order.listing.kg,
      'gasPrice': order.listing.price,
      'bankDisbursementAmount': order.bankDisbursementAmount,
      'originationFeeToMobigas': order.originationFeeToMobigas,
      'pin': order.pin,
      'status': order.status.name,
      'partnerBankName': order.partnerBankName,
      'riderName': order.riderName,
      'riderPhone': order.riderPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'bankRepaymentDueDate': Timestamp.fromDate(
        DateTime.now().add(const Duration(days: 30)),
      ),
    });
    return ref.id;
  }

  static Stream<List<OrderModel>> watchCustomerOrders(
      String customerId) {
    return FirebaseService.orders
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _orderFromMap(doc.id, data);
            }).toList());
  }

  static Stream<List<OrderModel>> watchVendorOrders(String vendorId) {
    return FirebaseService.orders
        .where('vendorId', isEqualTo: vendorId)
        .where('status', whereIn: [
          OrderStatus.pending.name,
          OrderStatus.accepted.name,
          OrderStatus.outForDelivery.name,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _orderFromMap(doc.id, data);
            }).toList());
  }

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

  static OrderModel _orderFromMap(
      String docId, Map<String, dynamic> data) {
    return OrderModel(
      orderId: data['orderId'] ?? docId,
      customerId: data['customerId'] ?? '',
      vendorId: data['vendorId'] ?? '',
      vendorName: data['vendorName'] ?? '',
      vendorPhone: data['vendorPhone'] ?? '',
      customerName: data['customerName'] ?? '',
      customerArea: data['customerArea'] ?? '',
      listing: GasListing(
        size: data['gasSize'] ?? '',
        kg: data['gasKg'] ?? 0,
        price: (data['gasPrice'] ?? 0).toDouble(),
        available: true,
      ),
      bankDisbursementAmount:
          (data['bankDisbursementAmount'] ?? 0).toDouble(),
      originationFeeToMobigas:
          (data['originationFeeToMobigas'] ?? 0).toDouble(),
      pin: data['pin'] ?? '',
      status: OrderStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => OrderStatus.pending,
      ),
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
      partnerBankName: data['partnerBankName'] ?? '',
      riderName: data['riderName'],
      riderPhone: data['riderPhone'],
    );
  }

  // ── BANK APPLICATIONS ─────────────────────────────────────────────
  // This is where we pass customer KYC to partner bank
  static Future<void> submitBankApplication({
    required String customerId,
    required String name,
    required String phone,
    required String nationalId,
    required String county,
    required String area,
    required List<Map<String, String>> guarantors,
  }) async {
    await FirebaseService.bankApplications.add({
      'customerId': customerId,
      'name': name,
      'phone': phone,
      'nationalId': nationalId,
      'county': county,
      'area': area,
      'guarantors': guarantors,
      'status': 'pending',
      // Bank reads this collection via webhook/API
      // Bank updates status + approvedLimit when done
      'submittedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── REPAYMENTS ────────────────────────────────────────────────────
  static Future<void> recordRepayment({
    required String orderId,
    required String customerId,
    required double amount,
    required String mpesaRef,
  }) async {
    await FirebaseService.repayments.add({
      'orderId': orderId,
      'customerId': customerId,
      'amount': amount,
      'mpesaRef': mpesaRef,
      'status': 'paid',
      'paidAt': FieldValue.serverTimestamp(),
    });

    // Reduce credit used
    await updateCreditUsed(customerId, -amount);
  }

  static Stream<List<Map<String, dynamic>>> watchCustomerRepayments(
      String customerId) {
    return FirebaseService.repayments
        .where('customerId', isEqualTo: customerId)
        .orderBy('paidAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => doc.data() as Map<String, dynamic>)
            .toList());
  }
}
