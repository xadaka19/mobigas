import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';

/// BUG FIX: nothing in this file had a timeout — checkDuplicates was
/// already parallelized with Future.wait, but a stuck call inside it
/// (or any single-doc get() elsewhere) could still hang the calling
/// screen forever. On a fresh install specifically, the first
/// Firestore call has to wait on App Check's first-ever Play Integrity
/// attestation for that device, which is uncached and can take
/// anywhere from seconds to well over a minute. `.bounded()` gives
/// every login/signup-critical call a ceiling: past it, the future
/// throws TimeoutException instead of hanging, so AuthProvider's
/// existing catch blocks can put the user back in control instead of
/// leaving them on an unbounded spinner.
extension _Bounded<T> on Future<T> {
  Future<T> bounded([Duration timeout = const Duration(seconds: 15)]) {
    return this.timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        'Request timed out. Check your connection and try again.',
      ),
    );
  }
}

class FirestoreService {
  // ── USERS ─────────────────────────────────────────────────────────
  // Check if phone, alt phone, or national ID already registered.
  //
  // `altPhone` is checked as its OWN axis, not folded into `phone` —
  // a customer's alt number colliding with someone else's PRIMARY
  // phone is a real conflict (that number is already how that other
  // account gets contacted/verified), and so is it colliding with
  // someone else's alt number. Both should surface as `altPhoneTaken`.
  //
  // BACKEND DEPENDENCY: the checkDuplicates Cloud Function itself
  // (functions/src/index.ts — not included here) needs a matching
  // update to actually read `data.altPhone` from the callable request
  // and check it against both the `phone` and `altPhone` fields on
  // `users`/`vendors`, returning `altPhoneTaken` in its response. Until
  // that ships, the client will always get `altPhoneTaken: false` back
  // (unmatched fields are simply absent from the callable's response),
  // which is a safe default — it fails open the same way every other
  // check here does on error, it just doesn't yet fail CLOSED on a
  // genuine collision. Wire the function first if that matters before
  // launch.
  static Future<Map<String, bool>> checkDuplicates({
    required String phone,
    required String nationalId,
    String? altPhone,
    String? deviceFingerprint,
  }) async {
    // Moved server-side. The old version queried `users` and `vendors`
    // filtered by phone/nationalId/deviceFingerprint — a shape the
    // Firestore rules engine can never prove safe, so it was rejected
    // with permission-denied for every customer. The checkDuplicates
    // Cloud Function runs the same parallel check with the Admin SDK
    // and returns only booleans, so no other user's PII is ever
    // readable from a client.
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('checkDuplicates');
      final result = await callable.call({
        'phone': phone,
        'nationalId': nationalId,
        'altPhone': ?altPhone,
        'deviceFingerprint': ?deviceFingerprint,
      }).timeout(const Duration(seconds: 15));

      final data = Map<String, dynamic>.from(result.data as Map);
      return {
        'phoneTaken': data['phoneTaken'] == true,
        'idTaken': data['idTaken'] == true,
        'altPhoneTaken': data['altPhoneTaken'] == true,
        'deviceFlagged': data['deviceFlagged'] == true,
      };
    } catch (_) {
      // Fail OPEN — the same posture the client-side version had by
      // accident, now a deliberate choice. A missed duplicate is
      // recoverable (support can flag it later); a customer blocked
      // from finishing signup by a transient Cloud Function or network
      // hiccup is not an acceptable tradeoff.
      return {
        'phoneTaken': false,
        'idTaken': false,
        'altPhoneTaken': false,
        'deviceFlagged': false,
      };
    }
  }

  // Load full customer data from Firestore
  static Future<CustomerModel?> getUserByPhone(String phone) async {
    final snap = await FirebaseService.users
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final data = snap.docs.first.data() as Map<String, dynamic>;
    return _customerFromMap(snap.docs.first.id, data);
  }

  static Future<void> createUser(
    CustomerModel customer, {
    String? authMethod,
  }) async {
    // BUG FIX: unbounded write — see the bounded() extension above.
    await FirebaseService.users.doc(customer.id).set({
      'id': customer.id,
      'name': customer.name,
      'email': customer.email,
      'deviceFingerprint': customer.deviceFingerprint,
      'deviceFlagged': customer.deviceFlagged,
      'phone': customer.phone,
      // Almost always empty at signup time today (no screen collects
      // it yet) — written explicitly anyway so a future signup flow
      // that DOES set it doesn't need a second write to add it.
      'altPhone': customer.altPhone,
      'nationalId': customer.nationalId,
      'county': customer.county,
      'area': customer.area,
      'estate': customer.estate,
      'country': customer.country,
      'latitude': customer.latitude,
      'longitude': customer.longitude,
      // Folded in so email/password signup no longer needs a second
      // write just to set this. Written only when supplied.
      'authMethod': ?authMethod,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).bounded();
  }

  /// [source] defaults to serverAndCache, so every existing caller
  /// behaves exactly as before. AuthProvider's cold-start session
  /// restore passes Source.cache for an instant read from the local
  /// cache (then refreshes with Source.server in the background) — the
  /// difference between "home screen appears immediately on relaunch"
  /// and "wait for a server round trip every time".
  static Future<CustomerModel?> getUser(
    String uid, {
    Source source = Source.serverAndCache,
  }) async {
    // BUG FIX: this was the specific unbounded call most likely to
    // turn a slow first-ever App Check attestation (fresh install) or
    // a flaky connection into a spinner with no ceiling.
    final doc = await FirebaseService.users
        .doc(uid)
        .get(GetOptions(source: source))
        .bounded();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    return _customerFromMap(uid, data);
  }

  /// Sets the customer's country once a delivery pin is captured
  /// (ProfileCompletionSheet's location step, or the Google sign-up
  /// completion flow). Mirrors how VendorModel.country is written in
  /// vendor_setup_screen.dart's _save() — same GeoService detection,
  /// same "decided once from the pin, not re-derived later" contract.
  static Future<void> updateUserCountry(String uid, String country) async {
    await FirebaseService.users.doc(uid).update({
      'country': country,
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
      altPhone: data['altPhone'] ?? '',
      nationalId: data['nationalId'] ?? '',
      county: data['county'] ?? '',
      area: data['area'] ?? '',
      estate: data['estate'] ?? '',
      country: data['country'] ?? 'KE',
      latitude: (data['latitude'] ?? 0.0).toDouble(),
      longitude: (data['longitude'] ?? 0.0).toDouble(),
      selfieUrl: data['selfieUrl'],
      fcmToken: data['fcmToken'],
      referralCode: data['referralCode'] ?? '',
      referredByCode: data['referredByCode'],
      // Written by registerPezeshaBorrower (functions/src/pezesha.ts)
      // the first time this customer registers with Pezesha. Null
      // until then — AuthProvider.hasPezeshaId reflects this.
      pezeshaId: data['pezeshaId'],
    );
  }

  /// True if this uid has a vendor profile document. Used to stop a
  /// vendor's Google account from being treated as a customer (and
  /// vice versa via isRegisteredCustomer) if it ever authenticates
  /// through the wrong app's login screen. Vendor profiles are keyed
  /// by uid (see vendor_setup_screen.dart's _vendorId), so a direct
  /// doc lookup is correct here — no query needed.
  static Future<bool> isRegisteredVendor(String uid) async {
    // BUG FIX: unbounded — this runs on every customer-app login
    // before the vendor guard can pass or fail, so it's one of the
    // two calls most likely to be the thing holding the spinner open.
    final doc = await FirebaseService.vendors.doc(uid).get().bounded();
    return doc.exists;
  }

  /// True if this uid has a customer profile document. Mirror of
  /// isRegisteredVendor, used by the vendor login screen to reject a
  /// customer's Google account.
  static Future<bool> isRegisteredCustomer(String uid) async {
    final doc = await FirebaseService.users.doc(uid).get().bounded();
    return doc.exists;
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
      email: data['email'],
      phone: data['phone'] ?? '',
      altPhone: data['altPhone'] ?? '',
      area: data['area'] ?? '',
      estate: data['estate'] ?? '',
      county: data['county'] ?? '',
      country: data['country'] ?? 'KE',
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
                brand: l['brand'] ?? '',
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
      // DELIBERATELY NOT `data['chargesDeliveryFee'] ?? false`. The
      // model's field is nullable and the three states are distinct:
      // absent (this vendor has never saved since the delivery feature
      // shipped — show NO delivery note), false (explicitly chose free
      // delivery — show "Free delivery"), true (charges deliveryFee).
      // The `is bool` test is what preserves null for an absent field;
      // `?? false` would collapse "never answered" into "free" and
      // promise free delivery on behalf of every legacy vendor.
      chargesDeliveryFee: data['chargesDeliveryFee'] is bool
          ? data['chargesDeliveryFee'] as bool
          : null,
      deliveryFee: (data['deliveryFee'] ?? 0).toDouble(),
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
      // TZ only — the model gained this field so documentsSubmitted can
      // see it; without it here, a Tanzanian vendor who HAS uploaded
      // their TRA clearance still reads as not submitted.
      taxClearanceUrl: data['taxClearanceUrl'] ?? '',
      businessType: data['businessType'] ?? '',
      // Flexible-payment noticeboard — vendor's stored intent + own note.
      // MobiGas surfaces these; it's not a party to any arrangement.
      acceptsPartialPayment: data['acceptsPartialPayment'] ?? false,
      partialPaymentNote: data['partialPaymentNote'] ?? '',
      partialRepeatOnly: data['partialRepeatOnly'] ?? false,
      // Structured terms behind the note above — set only when the
      // vendor picked one of vendor_setup_screen's presets rather than
      // writing free-text Custom terms. `?.toDouble()` / `?.toInt()`
      // on a `num?` (rather than `?? 0` collapsing to a number) is
      // what preserves null for "vendor wrote Custom" or "never set
      // any terms" — VendorModel.partialPaymentSplitFor relies on
      // both being null in exactly those cases to know there's
      // nothing to compute, and fall back to showing partialPaymentNote
      // verbatim instead.
      partialPaymentPercent:
          (data['partialPaymentPercent'] as num?)?.toDouble(),
      partialPaymentDueHours:
          (data['partialPaymentDueHours'] as num?)?.toInt(),
      referralCode: data['referralCode'] ?? '',
      referredByCode: data['referredByCode'],
      // Written by registerPezeshaBorrower (functions/src/pezesha.ts)
      // the first time this vendor registers with Pezesha. Null until
      // then — VendorModel.hasPezeshaId reflects this.
      pezeshaId: data['pezeshaId'],
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
      'customerPhone': order.customerPhone,
      'customerLatitude': order.customerLatitude,
      'customerLongitude': order.customerLongitude,
      'gasSize': order.listing.size,
      'gasKg': order.listing.kg,
      // The GOODS money field. confirmDelivery accrues the 1% finder
      // fee from it, onOrderStatusChange sums it into
      // vendor_stats_alltime, and the vendor's earnings screen
      // aggregates it. The vendor's delivery fee is deliberately NOT
      // added in here — see deliveryFee below.
      'gasPrice': order.listing.price,
      'gasProductType': order.listing.productType.name,
      'gasBrand': order.listing.brand,
      'country': order.country,
      'paymentMethod': order.paymentMethod.name,
      'finderFee': order.finderFee,
      'finderFeeAccrued': false,
      // The vendor's flat delivery fee, frozen at order time. Its OWN
      // field rather than part of gasPrice, on purpose: the 1% finder
      // fee is a cut of goods sold, and a delivery fee is the vendor's
      // cost of getting the cylinder to the door, not margin on a
      // sale. Folding it into gasPrice would silently charge the
      // vendor 1% of their own delivery cost (and inflate the earnings
      // aggregate, which sums gasPrice). 0 for free delivery and for
      // every order placed before this existed.
      //
      // NOTE: if firestore.rules whitelists the fields a client may
      // write onto an order, add 'deliveryFee' there or this whole
      // write starts failing permission-denied.
      'deliveryFee': order.deliveryFee,
      // Set only for paymentMethod == bnpl — see OrderModel.loanId's
      // comment for why this must already be populated on `order`
      // before createOrder is called (loan approval happens first,
      // via PezeshaService.applyLoan / BnplCheckoutOption.onApproved).
      'loanId': order.loanId,
      // ── Flexible payment: A MESSAGE TO THE VENDOR, NOT A LEDGER ──
      // What the customer was SHOWN at checkout when they opted into
      // this vendor's own published terms, frozen here so both sides
      // are looking at the same numbers instead of two different
      // recollections. The vendor app renders these; nothing else
      // consumes them.
      //
      // Nothing reads these back to compute an outstanding balance.
      // No scheduled function watches partialDueBy. There is
      // deliberately no `partialSettled`/`partialPaidAt` written here
      // or anywhere else, and the orders security rules permit neither
      // party to write one — how and when the vendor actually collects
      // is between the vendor and their customer, and the moment
      // MobiGas records that, it is the ledger for a debt it is not
      // party to. See the OrderModel.partialPayment block.
      //
      // All five are on coreFieldsUnchanged() in firestore.rules, so
      // neither side can rewrite them once the order exists — a vendor
      // cannot raise the balance after delivery, and a customer cannot
      // lower the upfront figure the vendor was shown.
      'partialPayment': order.partialPayment,
      'partialUpfront': order.partialUpfront,
      'partialBalance': order.partialBalance,
      // Timestamp, not DateTime — Firestore stores the latter as a
      // Timestamp anyway, but being explicit keeps this symmetrical
      // with the `as Timestamp?` read in orderFromMap below.
      'partialDueBy': order.partialDueBy == null
          ? null
          : Timestamp.fromDate(order.partialDueBy!),
      'partialTerms': order.partialTerms,
      'pin': order.pin,
      'status': order.status.name,
      'riderName': order.riderName,
      'riderPhone': order.riderPhone,
      'createdAt': FieldValue.serverTimestamp(),
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
              return orderFromMap(doc.id, data);
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
              return orderFromMap(doc.id, data);
            }).toList());
  }

  /// Resolves an order the CURRENT USER is a party to.
  ///
  /// Orders are stored with an auto-generated document ID and the
  /// human-readable orderId as a field, so every lookup is a query.
  /// Under the scoped `orders` rules a query filtered on orderId alone
  /// is rejected outright — Firestore cannot prove the result belongs
  /// to the caller, so it refuses rather than leak. Each lookup must
  /// therefore also filter on customerId or vendorId.
  ///
  /// (The durable fix is to make the document ID equal the orderId, so
  /// these become .doc(orderId) gets that rules evaluate per-document.
  /// That's a data migration — worth doing on the branch after launch.)
  static Future<DocumentReference?> _myOrderRef(String orderId) async {
    final uid = FirebaseService.auth.currentUser?.uid;
    if (uid == null) return null;

    for (final field in ['customerId', 'vendorId']) {
      final snap = await FirebaseService.orders
          .where('orderId', isEqualTo: orderId)
          .where(field, isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) return snap.docs.first.reference;
    }
    return null;
  }

  /// Status transitions a client is allowed to make.
  ///
  /// `delivered` is deliberately NOT among them. It is written only by
  /// the confirmDelivery Cloud Function, after the server has compared
  /// the PIN the customer read out — and that same function accrues
  /// the 1% finder fee. Previously this method compared nothing,
  /// wrote `delivered` on the vendor's say-so, and then asked the
  /// vendor's own phone to charge itself a fee. A patched client
  /// simply skipped that step.
  static Future<void> updateOrderStatus(
      String orderId, OrderStatus status,
      {String? cancelledBy}) async {
    if (status == OrderStatus.delivered) {
      throw ArgumentError(
        'Delivered is written only by the confirmDelivery Cloud Function. '
        'Call it instead — otherwise the finder fee is never charged.',
      );
    }

    final docRef = await _myOrderRef(orderId);
    if (docRef == null) return;

    await docRef.update({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
      // Only cancellation ever sets this — never overwrite it with
      // null on other status transitions.
      'cancelledBy': ?cancelledBy,
    });
  }

  /// THE order mapper. Public on purpose.
  ///
  /// vendor_home_screen.dart used to keep a private copy of this, and
  /// the two drifted — twice. First it dropped customerLatitude /
  /// customerLongitude, so every OrderModel handed to VendorOrderScreen
  /// carried 0,0 and any map pointed at the Gulf of Guinea. That got
  /// patched there but not here, and the copy then also turned out to
  /// omit `country`, so every order on the vendor's screen fell back to
  /// the 'KE' default and Currency.formatFor showed KSh to Ugandan and
  /// Tanzanian vendors on their own dashboards. It omitted loanId too.
  ///
  /// Two mappers for one document shape will always drift, because
  /// adding a field to the model only forces you to update the one you
  /// happen to be looking at. So there is now exactly one, and both
  /// apps call it. Don't add a second — if a screen needs a tweak to
  /// the result, map here and adjust at the call site.
  static OrderModel orderFromMap(
      String docId, Map<String, dynamic> data) {
    return OrderModel(
      orderId: data['orderId'] ?? docId,
      customerId: data['customerId'] ?? '',
      vendorId: data['vendorId'] ?? '',
      vendorName: data['vendorName'] ?? '',
      vendorPhone: data['vendorPhone'] ?? '',
      customerName: data['customerName'] ?? '',
      customerArea: data['customerArea'] ?? '',
      customerPhone: data['customerPhone'] ?? '',
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
        brand: data['gasBrand'] ?? '',
      ),
      country: data['country'] ?? 'KE',
      paymentMethod: PaymentMethod.values.firstWhere(
        (m) => m.name == (data['paymentMethod'] ?? 'cash'),
        orElse: () => PaymentMethod.cash,
      ),
      finderFee: (data['finderFee'] ?? 0).toDouble(),
      // Frozen at order time — never re-read from the vendor doc, so a
      // vendor raising their fee tomorrow can't change what an order
      // placed today cost. Feeds OrderModel.customerTotal.
      deliveryFee: (data['deliveryFee'] ?? 0).toDouble(),
      loanId: data['loanId'],
      // Flexible payment — false/0/null/'' for every order where the
      // customer didn't opt in, and for every order predating the
      // feature. Read back only so the vendor app can show the
      // customer what they were shown; see createOrder above for why
      // there is nothing here about whether any of it was paid.
      partialPayment: data['partialPayment'] ?? false,
      partialUpfront: (data['partialUpfront'] ?? 0).toDouble(),
      partialBalance: (data['partialBalance'] ?? 0).toDouble(),
      partialDueBy: (data['partialDueBy'] as Timestamp?)?.toDate(),
      partialTerms: data['partialTerms'] ?? '',
      cancelledBy: data['cancelledBy'],
      pin: data['pin'] ?? '',
      status: OrderStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => OrderStatus.pending,
      ),
      createdAt: (data['createdAt'] as dynamic)?.toDate() ?? DateTime.now(),
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

  /// Records a referral signup — moved server-side (Cloud Function)
  /// so a modified/rooted client can never skip or spoof the identity
  /// fraud guard (the function reads phone/National ID/email from
  /// the referred person's own already-created Firestore doc, not
  /// from client-supplied values). deviceFingerprint is the one
  /// value still passed from here, since there's no server-side
  /// equivalent for it. Silently no-ops on any failure (invalid code,
  /// transient error, etc.) — never blocks a successful signup.
  static Future<void> recordReferralSignup({
    required String code,
    required String referredType, // 'customer' | 'vendor'
    String? deviceFingerprint,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('recordReferralSignup');
      await callable.call({
        'code': code,
        'referredType': referredType,
        'deviceFingerprint': ?deviceFingerprint,
      });
    } catch (_) {
      // Invalid code, no profile yet, or a transient failure — never
      // let a referral hiccup block a successful signup.
    }
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

  // ── NOTIFICATIONS INBOX ───────────────────────────────────────────
  // Persistent record of every push notification actually received,
  // written by notification_service.dart at the moment it arrives, and
  // by the onNotificationQueued Cloud Function for server-originated
  // messages.

  static Stream<List<Map<String, dynamic>>> watchNotifications(
      String userId) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              return {
                'id': d.id,
                'title': data['title'] ?? '',
                'body': data['body'] ?? '',
                'type': data['type'] ?? '',
                'read': data['read'] ?? false,
                'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
              };
            }).toList());
  }

  static Future<void> markNotificationRead(String notificationId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  static Future<void> markAllNotificationsRead(String userId) async {
    final snap = await FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  static Future<void> deleteNotification(String notificationId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notificationId)
        .delete();
  }

  // ── ORDER CHAT ────────────────────────────────────────────────────
  // Scoped per-order (not a general DM) — vendor and customer chatting
  // about THIS specific delivery. order_chats/{orderId} holds who's in
  // the conversation (for security rules to check against, without a
  // separate lookup to the orders collection); messages live in its
  // messages subcollection.

  /// Creates the chat doc if it doesn't exist yet (lazy — most orders
  /// never need a chat at all). Safe to call every time the chat
  /// screen opens.
  static Future<void> ensureOrderChatExists({
    required String orderId,
    required String customerId,
    required String vendorId,
    required String customerName,
    required String vendorName,
  }) async {
    final ref = FirebaseFirestore.instance.collection('order_chats').doc(orderId);
    final doc = await ref.get();
    if (doc.exists) return;
    await ref.set({
      'orderId': orderId,
      'customerId': customerId,
      'vendorId': vendorId,
      'customerName': customerName,
      'vendorName': vendorName,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> sendOrderChatMessage({
    required String orderId,
    required String senderId,
    required String senderType, // 'customer' | 'vendor'
    required String senderName,
    required String text,
  }) async {
    final chatRef = FirebaseFirestore.instance.collection('order_chats').doc(orderId);
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await chatRef.collection('messages').add({
      'senderId': senderId,
      'senderType': senderType,
      'senderName': senderName,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'read': false,
    });
    await chatRef.update({
      'lastMessage': trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<List<Map<String, dynamic>>> watchOrderChatMessages(
      String orderId) {
    return FirebaseFirestore.instance
        .collection('order_chats')
        .doc(orderId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              return {
                'id': d.id,
                'senderId': data['senderId'] ?? '',
                'senderType': data['senderType'] ?? '',
                'senderName': data['senderName'] ?? '',
                'text': data['text'] ?? '',
                'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
                'read': data['read'] ?? false,
              };
            }).toList());
  }

  /// Marks every message NOT sent by [readerId] as read — called when
  /// the chat screen opens, so the other party's unread badge clears.
  static Future<void> markOrderChatRead({
    required String orderId,
    required String readerId,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('order_chats')
        .doc(orderId)
        .collection('messages')
        .where('senderId', isNotEqualTo: readerId)
        .where('read', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }
}