import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';

class FirestoreService {
  // ── USERS ─────────────────────────────────────────────────────────
  // Check if phone or national ID already registered
  static Future<Map<String, bool>> checkDuplicates({
    required String phone,
    required String nationalId,
    String? deviceFingerprint,
  }) async {
    final phoneSnap = await FirebaseService.users
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();

    final idSnap = await FirebaseService.users
        .where('nationalId', isEqualTo: nationalId)
        .limit(1)
        .get();


    bool deviceFlagged = false;
    if (deviceFingerprint != null) {
      final deviceSnap = await FirebaseService.users
          .where("deviceFingerprint", isEqualTo: deviceFingerprint)
          .get();
      deviceFlagged = deviceSnap.docs.isNotEmpty;
    }
    return {
      'phoneTaken': phoneSnap.docs.isNotEmpty,
      'idTaken': idSnap.docs.isNotEmpty,
      'deviceFlagged': deviceFlagged,
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
      'email': customer.email,
      'deviceFingerprint': customer.deviceFingerprint,
      'deviceFlagged': customer.deviceFlagged,
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
      email: data['email'],
      deviceFingerprint: data['deviceFingerprint'],
      deviceFlagged: data['deviceFlagged'] ?? false,
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
      referralCode: data['referralCode'] ?? '',
      referredByCode: data['referredByCode'],
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
      'feesOwed': 0.0,
      'isSuspended': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static VendorModel vendorFromMap(
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
                productType: GasProductType.values.firstWhere(
                  (t) => t.name == (l['productType'] ?? 'refill'),
                  orElse: () => GasProductType.refill,
                ),
              ))
          .toList(),
      rating: (data['rating'] ?? 0.0).toDouble(),
      totalReviews: data['totalReviews'] ?? 0,
      isOnline: data['isOnline'] ?? false,
      isVerified: data['isVerified'] ?? false,
      distance: data['distance'] ?? '',
      deliveryTime: data['deliveryTime'] ?? '30–45 min',
      feesOwed: (data['feesOwed'] ?? 0.0).toDouble(),
      isSuspended: data['isSuspended'] ?? false,
      epraCertificateUrl: data['epraCertificateUrl'] ?? '',
      subDealerAuthorizationUrl: data['subDealerAuthorizationUrl'] ?? '',
      parentVendorName: data['parentVendorName'] ?? '',
      parentEpraNumber: data['parentEpraNumber'] ?? '',
      brandAuthorizationUrl: data['brandAuthorizationUrl'] ?? '',
      dealerAssociationLetterUrl: data['dealerAssociationLetterUrl'] ?? '',
      businessPermitUrl: data['businessPermitUrl'] ?? '',
      businessRegistrationUrl: data['businessRegistrationUrl'] ?? '',
      fireCertificateUrl: data['fireCertificateUrl'] ?? '',
      weighingScaleCertUrl: data['weighingScaleCertUrl'] ?? '',
      weighingScalePhotoUrl: data['weighingScalePhotoUrl'] ?? '',
      premisesPhotoUrl: data['premisesPhotoUrl'] ?? '',
      businessType: data['businessType'] ?? '',
      referralCode: data['referralCode'] ?? '',
      referredByCode: data['referredByCode'],
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
      'customerLatitude': order.customerLatitude,
      'customerLongitude': order.customerLongitude,
      'gasSize': order.listing.size,
      'gasKg': order.listing.kg,
      'gasPrice': order.listing.price,
      'gasProductType': order.listing.productType.name,
      'paymentMethod': order.paymentMethod.name,
      'finderFee': order.finderFee,
      'finderFeeAccrued': false,
      'bankDisbursementAmount': order.bankDisbursementAmount,
      'originationFeeToMobigas': order.originationFeeToMobigas,
      'pin': order.pin,
      'status': order.status.name,
      'partnerBankName': order.partnerBankName,
      'riderName': order.riderName,
      'riderPhone': order.riderPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'bankRepaymentDueDate': order.paymentMethod == PaymentMethod.credit
          ? Timestamp.fromDate(
              DateTime.now().add(const Duration(days: 30)),
            )
          : null,
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
      String orderId, OrderStatus status,
      {String? cancelledBy}) async {
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: orderId)
        .get();
    if (snap.docs.isEmpty) return;

    final docRef = snap.docs.first.reference;
    final data = snap.docs.first.data() as Map<String, dynamic>;

    await docRef.update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      // Only cancellation ever sets this — never overwrite it with
      // null on other status transitions.
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
    });

    // Cash orders: accrue the 1% customer-finder fee the vendor owes
    // MobiGas — only once, and only when delivery is confirmed.
    if (status == OrderStatus.delivered &&
        (data['paymentMethod'] ?? 'credit') == 'cash' &&
        (data['finderFeeAccrued'] ?? false) == false) {
      final fee = (data['finderFee'] ?? 0).toDouble();
      final vendorId = data['vendorId'] ?? '';
      if (fee > 0 && vendorId.isNotEmpty) {
        await _accrueFinderFee(
          orderDocRef: docRef,
          orderId: orderId,
          vendorId: vendorId,
          vendorName: data['vendorName'] ?? '',
          fee: fee,
          gasPrice: (data['gasPrice'] ?? 0).toDouble(),
        );
      }
    }

    // Cancelled credit orders: release the customer's reserved bank
    // credit — only once (guarded so retries can't double-refund).
    if (status == OrderStatus.cancelled &&
        (data['paymentMethod'] ?? 'credit') == 'credit' &&
        (data['creditRefunded'] ?? false) == false) {
      final price = (data['gasPrice'] ?? 0).toDouble();
      final customerId = data['customerId'] ?? '';
      if (price > 0 && customerId.isNotEmpty) {
        await docRef.update({'creditRefunded': true});
        await updateCreditUsed(customerId, -price);
      }
    }
  }

  static Future<void> _accrueFinderFee({
    required DocumentReference orderDocRef,
    required String orderId,
    required String vendorId,
    required String vendorName,
    required double fee,
    required double gasPrice,
  }) async {
    // Mark accrued first so a retry can't double-charge.
    await orderDocRef.update({'finderFeeAccrued': true});

    await FirebaseFirestore.instance
        .collection('vendors')
        .doc(vendorId)
        .update({'feesOwed': FieldValue.increment(fee)});

    await FirebaseFirestore.instance.collection('platform_fees').add({
      'orderId': orderId,
      'vendorId': vendorId,
      'vendorName': vendorName,
      'orderAmount': gasPrice,
      'fee': fee,
      'feeType': 'cash_finder_fee',
      'status': 'accrued', // accrued -> paid (admin marks on settlement)
      'accruedAt': FieldValue.serverTimestamp(),
    });
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
      customerLatitude: (data['customerLatitude'] ?? 0.0).toDouble(),
      customerLongitude: (data['customerLongitude'] ?? 0.0).toDouble(),
      listing: GasListing(
        size: data['gasSize'] ?? '',
        kg: data['gasKg'] ?? 0,
        price: (data['gasPrice'] ?? 0).toDouble(),
        available: true,
        productType: GasProductType.values.firstWhere(
          (t) => t.name == (data['gasProductType'] ?? 'refill'),
          orElse: () => GasProductType.refill,
        ),
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (m) => m.name == (data['paymentMethod'] ?? 'credit'),
        orElse: () => PaymentMethod.credit,
      ),
      finderFee: (data['finderFee'] ?? 0).toDouble(),
      cancelledBy: data['cancelledBy'],
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

  // ── PLATFORM FEES ─────────────────────────────────────────────────
  // Vendor's own accrued/paid finder fees (for the vendor app banner
  // and fee history screen).
  static Stream<List<Map<String, dynamic>>> watchVendorFees(
      String vendorId) {
    return FirebaseFirestore.instance
        .collection('platform_fees')
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('accruedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  // ── REFERRALS ─────────────────────────────────────────────────────
  // Every customer/vendor gets a shareable code (generated lazily,
  // the first time their referral screen opens). Qualification
  // (pending -> qualified) and the reward amount are only ever set by
  // Cloud Functions (see functions/src/index.ts: onCustomerReferralCheck,
  // onVendorReferralCheck) — never by a client write, so the reward
  // can't be gamed by editing Firestore directly.

  static const List<String> _codeChars =
      ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N',
       'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
       '2', '3', '4', '5', '6', '7', '8', '9'];

  static String _randomSuffix(int length) {
    final rand = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer();
    var seed = rand;
    for (var i = 0; i < length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buffer.write(_codeChars[seed % _codeChars.length]);
    }
    return buffer.toString();
  }

  /// Returns the owner's existing referral code, or generates and
  /// saves a new unique one (prefix from their name + 4 random
  /// chars, e.g. "PAT-7F3K"). collectionRef is FirebaseService.users
  /// or FirebaseService.vendors depending on ownerType.
  static Future<String> getOrCreateReferralCode({
    required String ownerId,
    required String ownerType, // 'customer' | 'vendor'
    required String ownerName,
  }) async {
    final collectionRef =
        ownerType == 'vendor' ? FirebaseService.vendors : FirebaseService.users;
    final ownerDoc = await collectionRef.doc(ownerId).get();
    final existing =
        (ownerDoc.data() as Map<String, dynamic>?)?['referralCode'] as String?;
    if (existing != null && existing.isNotEmpty) return existing;

    final prefix = ownerName
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '')
        .padRight(3, 'X')
        .substring(0, 3);

    // Retry on the rare collision rather than assuming one attempt
    // is always unique.
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = '$prefix-${_randomSuffix(4)}';
      final codeDoc =
          await FirebaseFirestore.instance.collection('referral_codes').doc(code).get();
      if (!codeDoc.exists) {
        await FirebaseFirestore.instance.collection('referral_codes').doc(code).set({
          'ownerId': ownerId,
          'ownerType': ownerType,
          'ownerName': ownerName,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await collectionRef.doc(ownerId).update({'referralCode': code});
        return code;
      }
    }
    throw Exception('Could not generate a unique referral code — try again.');
  }

  /// Looks up who owns a code, for validating input at signup.
  /// Returns null if the code doesn't exist.
  static Future<Map<String, dynamic>?> lookupReferralCode(
      String code) async {
    if (code.trim().isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection('referral_codes')
        .doc(code.trim().toUpperCase())
        .get();
    return doc.exists ? doc.data() : null;
  }

  /// Called once, at signup, after a valid code was entered. Links
  /// the new user/vendor to their referrer and creates the pending
  /// referral record the Cloud Function will later qualify.
  /// Reads the current referral reward rates — set from the admin
  /// dashboard, applied live to every new signup from this point on.
  /// Falls back to zero (not null) if admin hasn't configured rates
  /// yet, so a referral is still recorded rather than crashing —
  /// just with no reward until admin sets real numbers.
  static Future<Map<String, double>> getReferralRewardRates() async {
    final doc = await FirebaseFirestore.instance
        .collection('platform_settings')
        .doc('referral_rewards')
        .get();
    final data = doc.data();
    return {
      'customerReward': (data?['customerReward'] ?? 0).toDouble(),
      'vendorReward': (data?['vendorReward'] ?? 0).toDouble(),
    };
  }

  static Future<void> recordReferralSignup({
    required String code,
    required String referredId,
    required String referredType, // 'customer' | 'vendor'
    required String referredName,
  }) async {
    final owner = await lookupReferralCode(code);
    if (owner == null) return; // invalid code — silently ignored

    final normalizedCode = code.trim().toUpperCase();
    final collectionRef =
        referredType == 'vendor' ? FirebaseService.vendors : FirebaseService.users;
    await collectionRef.doc(referredId).update({
      'referredByCode': normalizedCode,
    });

    // Reward amount is locked in HERE, at signup, using whatever rate
    // admin has configured right now — a later rate change in the
    // dashboard only affects new signups from that point forward,
    // never retroactively changes what an existing referral was
    // already promised.
    final rates = await getReferralRewardRates();
    final rewardAmount = referredType == 'vendor'
        ? rates['vendorReward']!
        : rates['customerReward']!;

    await FirebaseFirestore.instance.collection('referrals').add({
      'referrerId': owner['ownerId'],
      'referrerType': owner['ownerType'],
      'referrerName': owner['ownerName'],
      'referredId': referredId,
      'referredType': referredType,
      'referredName': referredName,
      'code': normalizedCode,
      'status': ReferralStatus.pending.name,
      'rewardAmount': rewardAmount,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Saves how a referrer wants to be paid — reused by both apps.
  /// payoutMethod: 'mpesa' | 'bank'. payoutCadence: '14days' | '30days'.
  static Future<void> savePayoutPreferences({
    required String ownerId,
    required String ownerType, // 'customer' | 'vendor'
    required String payoutMethod,
    required String payoutCadence,
    String? mpesaNumber,
    String? bankName,
    String? bankAccountNumber,
    String? bankAccountName,
  }) async {
    final collectionRef =
        ownerType == 'vendor' ? FirebaseService.vendors : FirebaseService.users;
    await collectionRef.doc(ownerId).update({
      'payoutMethod': payoutMethod,
      'payoutCadence': payoutCadence,
      'payoutMpesaNumber': mpesaNumber ?? '',
      'payoutBankName': bankName ?? '',
      'payoutBankAccountNumber': bankAccountNumber ?? '',
      'payoutBankAccountName': bankAccountName ?? '',
      'payoutPreferencesUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Loads a referrer's current payout preferences, for prefilling
  /// the form and for the admin dashboard to know how/when to pay.
  static Future<Map<String, dynamic>> getPayoutPreferences({
    required String ownerId,
    required String ownerType,
  }) async {
    final collectionRef =
        ownerType == 'vendor' ? FirebaseService.vendors : FirebaseService.users;
    final doc = await collectionRef.doc(ownerId).get();
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return {
      'payoutMethod': data['payoutMethod'] ?? '',
      'payoutCadence': data['payoutCadence'] ?? '',
      'payoutMpesaNumber': data['payoutMpesaNumber'] ?? '',
      'payoutBankName': data['payoutBankName'] ?? '',
      'payoutBankAccountNumber': data['payoutBankAccountNumber'] ?? '',
      'payoutBankAccountName': data['payoutBankAccountName'] ?? '',
    };
  }

  /// Live stream of everyone a given referrer has referred — used by
  /// their own Refer & Earn dashboard.
  static Stream<List<ReferralModel>> watchMyReferrals(String referrerId) {
    return FirebaseFirestore.instance
        .collection('referrals')
        .where('referrerId', isEqualTo: referrerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              return ReferralModel(
                id: d.id,
                referrerId: data['referrerId'] ?? '',
                referrerType: data['referrerType'] ?? '',
                referrerName: data['referrerName'] ?? '',
                referredId: data['referredId'] ?? '',
                referredType: data['referredType'] ?? '',
                referredName: data['referredName'] ?? '',
                code: data['code'] ?? '',
                status: ReferralStatus.values.firstWhere(
                  (s) => s.name == data['status'],
                  orElse: () => ReferralStatus.pending,
                ),
                rewardAmount: (data['rewardAmount'] ?? 0).toDouble(),
                createdAt:
                    (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                qualifiedAt: (data['qualifiedAt'] as Timestamp?)?.toDate(),
                paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
              );
            }).toList());
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