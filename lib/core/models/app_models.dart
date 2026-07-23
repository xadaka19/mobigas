import 'package:mobigas/core/config/vendor_requirements.dart';

// All gas product types
enum GasProductType {
  refill,           // Gas refill only (most common)
  fullKit,          // Gas + New cylinder
  grillKit,         // 6kg Gas + Cylinder + Burner/Grill + Regulator + Pipe
  burner,           // Standalone burner — fits 3kg or 6kg cylinders
  regulator,        // Standalone regulator — fits 13kg cylinders
  mekoCooker,       // Standalone meko + cooker set — no gas or cylinder
}

extension GasProductTypeExt on GasProductType {
  String get label {
    switch (this) {
      case GasProductType.refill:
        return 'Refill';
      case GasProductType.fullKit:
        return 'Full Kit (Gas + Cylinder)';
      case GasProductType.grillKit:
        return 'Grill Kit (Gas + Cylinder + Burner + Grill)';
      case GasProductType.burner:
        return 'Burner';
      case GasProductType.regulator:
        return 'Regulator';
      case GasProductType.mekoCooker:
        return 'Meko + Cooker';
    }
  }

  String get description {
    switch (this) {
      case GasProductType.refill:
        return 'Gas refill only — exchange your empty cylinder';
      case GasProductType.fullKit:
        return 'New gas cylinder + gas — no empty cylinder needed';
      case GasProductType.grillKit:
        return '6kg gas + cylinder + LPG burner + grill — complete package';
      case GasProductType.burner:
        return 'Standalone gas burner — no gas or cylinder included';
      case GasProductType.regulator:
        return 'Standalone gas regulator — no gas or cylinder included';
      case GasProductType.mekoCooker:
        return 'Meko stove + cooker set — no gas or cylinder included';
    }
  }

  // "Size" here means cylinder compatibility, not gas quantity — a
  // burner/regulator carries no gas, but only fits certain cylinders.
  bool isAvailableForSize(String size) {
    switch (this) {
      case GasProductType.grillKit:
        return size == '6kg';
      case GasProductType.burner:
        return size == '3kg' || size == '6kg';
      case GasProductType.regulator:
        return size == '13kg';
      default:
        return true;
    }
  }

  /// True for products that don't actually contain gas — used to
  /// skip "have your empty cylinder ready" / cylinder-exchange copy
  /// that only makes sense for gas-containing orders.
  bool get isAccessoryOnly =>
      this == GasProductType.burner ||
      this == GasProductType.regulator ||
      this == GasProductType.mekoCooker;
}

// How the customer pays for an order.
//
// 'cash': customer pays the vendor directly, on delivery — cash or
// mobile money, no MobiGas involvement in the payment itself.
//
// 'bnpl': Pezesha disburses the order amount straight to the vendor
// at order time, and the customer repays PEZESHA directly per the
// loan schedule they were shown and accepted at checkout — see
// applyPezeshaLoan (functions/src/pezesha.ts) and
// BnplCheckoutOption/BnplCheckoutSection (customer_bnpl.dart).
// MobiGas is not a lender and does not collect repayment for this
// path either; it only initiates the loan application on the
// customer's behalf and records the resulting loanId on the order
// (see OrderModel.loanId below) so support can look a loan up by
// order.
//
// This is NOT a revival of the old `credit` value that used to sit
// here (bank pays vendor, customer repays bank — a design that never
// shipped: no order was ever created with it, and the functions
// behind it were never deployed, so it was removed rather than left
// dormant). `bnpl` is real, live, and backed by an actual
// third-party disbursement (Pezesha) with a loanId you can look up
// via getPezeshaLoanStatus/getPezeshaLoanHistory. Parsers still use
// `orElse: () => PaymentMethod.cash`, so any legacy or unrecognized
// Firestore value degrades to cash rather than throwing.
//
// A flexible-payment order is NOT a third value here and must never
// become one. The customer still pays the vendor directly on
// delivery — `cash` — they have simply arranged with that vendor to
// do it in more than one instalment. See the OrderModel.partialPayment
// block for why that distinction is load-bearing.
enum PaymentMethod {
  cash, // Customer pays the vendor on delivery — cash or mobile money
  bnpl, // Pezesha pays the vendor; customer repays Pezesha directly
}

extension PaymentMethodExt on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Pay on delivery';
      case PaymentMethod.bnpl:
        return 'Pay later (BNPL via Pezesha)';
    }
  }
}

// All Kenyan gas brands
class KenyanGasBrands {
  static const List<String> all = [
    'Total',
    'K-Gas',
    'Hashi',
    'Afrigaz',
    'Orion',
    'Pro Gas',
    'Shell',
    'Lake Gas',
    'Taifa Gas',
    'Hass Gas',
    'Top Gas',
    'Supa Gas',
    'Safe Gas',
    'Rubis Gas',
    'Mengas',
    'Salama Gas',
    'Sea Gas',
    'Raha Gas',
  ];
}

class MobiGasFees {
  // Vendor pays MobiGas 1% customer-finder fee on every order,
  // accrued server-side in confirmDelivery when the order is confirmed
  // delivered, settled weekly. This is MobiGas's only order revenue.
  // Deliberately NOT charged on financing itself — see the BNPL
  // discussion: financing access stays a retention lever (bigger,
  // more frequent orders), not a second monetized surface. If that
  // changes, it's a new rate constant, not a change to this one.
  //
  // Also deliberately NOT charged on a vendor's delivery fee. The 1%
  // is a cut of GMV — the goods sold — and a delivery fee is the
  // vendor's own cost of getting the cylinder to the door, not margin
  // on a sale. GasListing.cashFinderFee is computed from the listing
  // price alone and OrderModel.deliveryFee is kept out of it, which
  // is why the two are separate fields on the order rather than one
  // summed total.
  static const double cashFinderFeeRate = 0.01;
  // When a vendor's unpaid fees reach this amount (KES), they are
  // automatically hidden from customers until they settle.
  static const double vendorFeeLockThreshold = 500;
}

/// Referral reward rates are NOT hardcoded here — they live in
/// Firestore (platform_settings/referral_rewards), editable from the
/// admin dashboard and applied live to every new signup. See
/// FirestoreService.getReferralRewardRates / recordReferralSignup.

enum ReferralStatus {
  pending, // signed up with the code, hasn't qualified yet
  qualified, // reward earned — awaiting payout
  paid, // admin has recorded payment to the referrer
}

/// One referral relationship: someone referred a customer or a
/// vendor using a code. Qualification (and the reward amount it
/// locks in) is only ever set server-side by Cloud Functions — a
/// referral can't be marked qualified by a client write, so the
/// reward can't be gamed by editing Firestore directly.
class ReferralModel {
  final String id;
  final String referrerId;
  final String referrerType; // 'customer' | 'vendor'
  final String referrerName;
  final String referredId;
  final String referredType; // 'customer' | 'vendor'
  final String referredName;
  final String code;
  final ReferralStatus status;
  final double rewardAmount;
  final DateTime createdAt;
  final DateTime? qualifiedAt;
  final DateTime? paidAt;

  const ReferralModel({
    required this.id,
    required this.referrerId,
    required this.referrerType,
    required this.referrerName,
    required this.referredId,
    required this.referredType,
    required this.referredName,
    required this.code,
    required this.status,
    required this.rewardAmount,
    required this.createdAt,
    this.qualifiedAt,
    this.paidAt,
  });
}

class GasListing {
  final String size;
  final int kg;
  final double price;
  final bool available;
  final GasProductType productType;
  /// Brand this listing is priced for — only meaningful for refill
  /// and fullKit, since different brands genuinely cost different
  /// amounts at the same size (e.g. Total 6kg costs more than a
  /// budget brand's 6kg). Empty for accessory-type products
  /// (grillKit/burner/regulator/mekoCooker) which aren't sold "by
  /// brand" the same way.
  final String brand;

  const GasListing({
    required this.size,
    required this.kg,
    required this.price,
    required this.available,
    this.productType = GasProductType.refill,
    this.brand = '',
  });

  // Vendor owes MobiGas 1% on every order — never shown to customer.
  // Computed from the listing price ONLY; a vendor's delivery fee is
  // deliberately excluded (see MobiGasFees.cashFinderFeeRate).
  double get cashFinderFee => price * MobiGasFees.cashFinderFeeRate;
}

/// The upfront/balance split and due date computed from a vendor's
/// STRUCTURED flexible-payment terms (percent + hours) for a given
/// order total. Returned by [VendorModel.partialPaymentSplitFor] —
/// see that method for when this is null instead.
class PartialPaymentSplit {
  final double upfrontAmount;
  final double balanceAmount;
  final DateTime dueDate;

  const PartialPaymentSplit({
    required this.upfrontAmount,
    required this.balanceAmount,
    required this.dueDate,
  });
}

class VendorModel {
  final String id;
  final String businessName;
  final String ownerName;
  final String? email;

  /// The vendor's CONTACT number — the line a customer calls about a
  /// delivery. NOT necessarily where they take payment: a vendor on Till
  /// or Paybill is paid on neither, and one who set payoutPhone is paid
  /// on a different line entirely.
  ///
  /// Payout (paymentMethod / tillNumber / paybillNumber / paybillAccount
  /// / payoutPhone) deliberately does NOT live on this model — it's read
  /// straight off the vendor doc by the two screens that need it
  /// (vendor_home_screen, vendor_fees_banner), and now also by
  /// resolveVendorDisbursement in functions/src/pezesha.ts for Pezesha
  /// payouts — same five raw fields, no new ones added. This model is
  /// what the CUSTOMER app knows about a vendor, and the customer never
  /// needs to know how the vendor gets paid; they hand over cash or send
  /// money to a number given at the door. OrderModel.vendorPhone copies
  /// THIS field — don't "fix" it into a payout number.
  final String phone;

  /// A second, optional number the vendor can be reached on, set from
  /// the vendor profile screens. Purely informational — MobiGas and
  /// customers still call/message `phone`; nothing reads this for
  /// payouts, OTPs, or order routing.
  final String altPhone;

  final String area;
  final String estate;
  final String county;
  final String country; // 'KE' | 'TZ' | 'UG' — set once at onboarding from GPS
  final double latitude;
  final double longitude;
  final List<String> brands;
  final List<GasListing> listings;
  final double rating;
  final int totalReviews;
  final bool isOnline;
  final bool isVerified;
  final String distance;
  final String deliveryTime;

  /// Accumulated unpaid customer-finder fees (KES).
  final double feesOwed;

  /// Suspended by admin for unpaid platform fees — receives NO orders
  /// until cleared.
  final bool isSuspended;

  // ── Delivery ────────────────────────────────────────────────────
  // A vendor sets ONE flat fee per order (or none), in the pricing
  // step of vendor_setup_screen. Three states, not two:
  //
  //   null  — never answered. Every vendor doc written before this
  //           feature shipped is here, because it has no
  //           chargesDeliveryFee field at all. Show the customer NO
  //           delivery note: we genuinely don't know, and inventing
  //           "Free delivery" would be a promise made on the vendor's
  //           behalf that they never agreed to and might not honour.
  //   false — explicitly chose free delivery. THIS is what earns a
  //           "Free delivery" note on their card.
  //   true  — charges deliveryFee on every order.
  //
  // Use the three getters below rather than reading the nullable bool
  // directly — `chargesDeliveryFee == true` and `!= false` are easy to
  // get subtly wrong at a call site, and the difference between them
  // is the difference between showing a note and not.

  /// Whether this vendor charges for delivery. Null means unanswered —
  /// see the block comment above before reading this directly.
  final bool? chargesDeliveryFee;

  /// Flat fee per order in the vendor's own currency. Meaningful only
  /// when chargesDeliveryFee is true; 0 otherwise. Read
  /// [effectiveDeliveryFee] instead of this raw value.
  final double deliveryFee;

  // ── Verification documents ──────────────────────────────────────
  // Uploaded once during onboarding; reviewed by admin before
  // isVerified is set to true. All fields empty until submitted.
  // Which of these a given vendor actually needs is decided by their
  // country — see VendorRequirements and documentsSubmitted below.
  // Three are "either/or" pairs — a vendor satisfies the requirement
  // with whichever one they can actually get, not both:
  //   - epraCertificateUrl    OR  subDealerAuthorizationUrl
  //   - weighingScaleCertUrl  OR  weighingScalePhotoUrl
  //   - brandAuthorizationUrl OR  dealerAssociationLetterUrl
  final String epraCertificateUrl;
  final String subDealerAuthorizationUrl;
  final String parentVendorName;
  final String parentEpraNumber;
  final String brandAuthorizationUrl;
  final String dealerAssociationLetterUrl;
  final String businessPermitUrl;
  final String businessRegistrationUrl;
  final String fireCertificateUrl;
  final String weighingScaleCertUrl;
  final String weighingScalePhotoUrl;
  final String premisesPhotoUrl;

  /// Tanzania only: TIN + TRA Tax Clearance Certificate. Empty everywhere
  /// else — see VendorRequirements for TZ, which is the only country whose
  /// supportingDocs list includes it. VendorSetupScreen has collected and
  /// saved this since TZ launch; the model simply never had a field for it,
  /// so documentsSubmitted couldn't see it.
  final String taxClearanceUrl;

  /// 'sole' | 'registered' | 'petrol_station' — determines whether
  /// businessRegistrationUrl is required (sole proprietors didn't
  /// previously have to prove registration at all; now they do).
  final String businessType;

  // ── Flexible payment (NOTICEBOARD ONLY) ─────────────────────────
  // MobiGas is not a party to, and does not track, any payment
  // arrangement between a vendor and a customer. It stores whether a
  // vendor is open to arranging flexible payment, and the vendor's own
  // words describing how — nothing more. There is deliberately NO
  // deposit amount, due date, balance, or interest field anywhere:
  // MobiGas computes nothing, enforces nothing, and records no debt.
  // The customer arranges directly with the vendor; the app only points
  // them to each other. Keeping it to a bool + free text + a bool is
  // what keeps this a listing feature and not a credit product.
  //
  // (This is distinct from PaymentMethod.bnpl above, which IS a real
  // credit product — just one MobiGas facilitates access to and Pezesha
  // actually underwrites/collects, rather than one MobiGas tracks a
  // balance for itself.)

  /// Vendor is open to arranging flexible payment directly with the
  /// customer. Drives a badge on the vendor's card and the note below.
  final bool acceptsPartialPayment;

  /// The vendor's OWN description of how they'd like to handle payment,
  /// shown to customers verbatim. MobiGas never parses, validates, or
  /// acts on it — if a vendor wants "half upfront", they write that here
  /// and it's between them and the customer. Capped so it stays a short
  /// note, not a contract.
  final String partialPaymentNote;

  /// Vendor only wants to arrange flexible payment with customers who've
  /// ordered from them before. When true, the note is shown greyed-out to
  /// first-time customers — they can still order at full price now. This
  /// gates the ARRANGEMENT, never the order: a first-timer is never
  /// blocked from buying, only from the flexible-payment note.
  final bool partialRepeatOnly;

  /// Structured terms behind [partialPaymentNote], set only when the
  /// vendor picked a preset in vendor_setup_screen rather than writing
  /// free text. Null for every vendor who chose Custom, and for every
  /// doc saved before this shipped — [partialPaymentSplitFor] returns
  /// null in exactly those cases, so callers fall back to showing
  /// [partialPaymentNote] verbatim. STILL a noticeboard, not a credit
  /// product: MobiGas computes the arithmetic so the customer sees a
  /// concrete number, but tracks no balance and is not a party to
  /// whether it's actually honoured.
  final double? partialPaymentPercent;

  /// Hours from order time until the balance is due, behind the
  /// selected preset. Paired with [partialPaymentPercent] — see that
  /// field's comment.
  final int? partialPaymentDueHours;

  /// This vendor's own code to share with others.
  final String referralCode;
  /// The referral code THEY entered at setup, if any — permanent.
  final String? referredByCode;

  /// This vendor's Pezesha borrower ID, once registered (see
  /// registerPezeshaBorrower in functions/src/pezesha.ts). Null until
  /// then. Mirrors CustomerModel.pezeshaId below — exists so screens
  /// that just need to know "has this vendor already registered with
  /// Pezesha" (e.g. to skip a redundant ensureRegistered round trip,
  /// or to gate a UI element) can read it off the model already in
  /// memory instead of making a fresh call. VendorPezeshaStockLoanCard
  /// still always calls PezeshaService.ensureRegistered on open (it's
  /// idempotent and confirms current state), so this field is an
  /// optimization/gate, not the source of truth.
  final String? pezeshaId;

  const VendorModel({
    required this.id,
    required this.businessName,
    required this.ownerName,
    this.email,
    required this.phone,
    this.altPhone = '',
    required this.area,
    required this.estate,
    required this.county,
    this.country = 'KE',
    required this.latitude,
    required this.longitude,
    required this.brands,
    required this.listings,
    required this.rating,
    required this.totalReviews,
    required this.isOnline,
    required this.isVerified,
    required this.distance,
    required this.deliveryTime,
    this.feesOwed = 0.0,
    this.isSuspended = false,
    this.chargesDeliveryFee,
    this.deliveryFee = 0.0,
    this.epraCertificateUrl = '',
    this.subDealerAuthorizationUrl = '',
    this.parentVendorName = '',
    this.parentEpraNumber = '',
    this.brandAuthorizationUrl = '',
    this.dealerAssociationLetterUrl = '',
    this.businessPermitUrl = '',
    this.businessRegistrationUrl = '',
    this.fireCertificateUrl = '',
    this.weighingScaleCertUrl = '',
    this.weighingScalePhotoUrl = '',
    this.premisesPhotoUrl = '',
    this.taxClearanceUrl = '',
    this.businessType = '',
    this.acceptsPartialPayment = false,
    this.partialPaymentNote = '',
    this.partialRepeatOnly = false,
    this.partialPaymentPercent,
    this.partialPaymentDueHours,
    this.referralCode = '',
    this.referredByCode,
    this.pezeshaId,
  });

  /// Returns a copy with only the named fields changed.
  ///
  /// EXISTS TO STOP A SPECIFIC BUG CLASS. VendorProvider.loadVendors
  /// used to rebuild this object by hand — `VendorModel(id: v.id,
  /// businessName: v.businessName, ...)` — purely to attach a distance
  /// string. That constructor call listed ~18 of the fields on this
  /// class, so every field it omitted was silently reset to its default
  /// on the distance-filtered path, which is the path essentially every
  /// customer takes. country fell back to 'KE' (wrong currency for UG
  /// and TZ vendors) and acceptsPartialPayment/partialPaymentNote fell
  /// back to false/'' (the "Flexible payment" chip never rendered) —
  /// neither with any error, anywhere.
  ///
  /// Adding a field to this class and forgetting to add it there was
  /// the whole failure mode, and it recurs every time the model grows.
  /// copyWith carries everything forward by default, so a new field is
  /// safe the moment it's declared. Do not reintroduce a hand-built
  /// constructor call for "just tweaking one field".
  VendorModel copyWith({
    String? id,
    String? businessName,
    String? ownerName,
    String? email,
    String? phone,
    String? altPhone,
    String? area,
    String? estate,
    String? county,
    String? country,
    double? latitude,
    double? longitude,
    List<String>? brands,
    List<GasListing>? listings,
    double? rating,
    int? totalReviews,
    bool? isOnline,
    bool? isVerified,
    String? distance,
    String? deliveryTime,
    double? feesOwed,
    bool? isSuspended,
    bool? chargesDeliveryFee,
    double? deliveryFee,
    String? epraCertificateUrl,
    String? subDealerAuthorizationUrl,
    String? parentVendorName,
    String? parentEpraNumber,
    String? brandAuthorizationUrl,
    String? dealerAssociationLetterUrl,
    String? businessPermitUrl,
    String? businessRegistrationUrl,
    String? fireCertificateUrl,
    String? weighingScaleCertUrl,
    String? weighingScalePhotoUrl,
    String? premisesPhotoUrl,
    String? taxClearanceUrl,
    String? businessType,
    bool? acceptsPartialPayment,
    String? partialPaymentNote,
    bool? partialRepeatOnly,
    double? partialPaymentPercent,
    int? partialPaymentDueHours,
    String? referralCode,
    String? referredByCode,
    String? pezeshaId,
  }) {
    return VendorModel(
      id: id ?? this.id,
      businessName: businessName ?? this.businessName,
      ownerName: ownerName ?? this.ownerName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      altPhone: altPhone ?? this.altPhone,
      area: area ?? this.area,
      estate: estate ?? this.estate,
      county: county ?? this.county,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      brands: brands ?? this.brands,
      listings: listings ?? this.listings,
      rating: rating ?? this.rating,
      totalReviews: totalReviews ?? this.totalReviews,
      isOnline: isOnline ?? this.isOnline,
      isVerified: isVerified ?? this.isVerified,
      distance: distance ?? this.distance,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      feesOwed: feesOwed ?? this.feesOwed,
      isSuspended: isSuspended ?? this.isSuspended,
      // Nullable by design (see the tri-state block above), so `??`
      // here can only ever ADD an answer, never clear one back to
      // "unanswered". Nothing needs to un-answer it, and a caller that
      // passed null expecting a reset would be silently ignored — which
      // is the safer of the two failure modes.
      chargesDeliveryFee: chargesDeliveryFee ?? this.chargesDeliveryFee,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      epraCertificateUrl: epraCertificateUrl ?? this.epraCertificateUrl,
      subDealerAuthorizationUrl:
          subDealerAuthorizationUrl ?? this.subDealerAuthorizationUrl,
      parentVendorName: parentVendorName ?? this.parentVendorName,
      parentEpraNumber: parentEpraNumber ?? this.parentEpraNumber,
      brandAuthorizationUrl:
          brandAuthorizationUrl ?? this.brandAuthorizationUrl,
      dealerAssociationLetterUrl:
          dealerAssociationLetterUrl ?? this.dealerAssociationLetterUrl,
      businessPermitUrl: businessPermitUrl ?? this.businessPermitUrl,
      businessRegistrationUrl:
          businessRegistrationUrl ?? this.businessRegistrationUrl,
      fireCertificateUrl: fireCertificateUrl ?? this.fireCertificateUrl,
      weighingScaleCertUrl:
          weighingScaleCertUrl ?? this.weighingScaleCertUrl,
      weighingScalePhotoUrl:
          weighingScalePhotoUrl ?? this.weighingScalePhotoUrl,
      premisesPhotoUrl: premisesPhotoUrl ?? this.premisesPhotoUrl,
      taxClearanceUrl: taxClearanceUrl ?? this.taxClearanceUrl,
      businessType: businessType ?? this.businessType,
      acceptsPartialPayment:
          acceptsPartialPayment ?? this.acceptsPartialPayment,
      partialPaymentNote: partialPaymentNote ?? this.partialPaymentNote,
      partialRepeatOnly: partialRepeatOnly ?? this.partialRepeatOnly,
      // Same "add only" nullable pattern as chargesDeliveryFee above.
      partialPaymentPercent:
          partialPaymentPercent ?? this.partialPaymentPercent,
      partialPaymentDueHours:
          partialPaymentDueHours ?? this.partialPaymentDueHours,
      referralCode: referralCode ?? this.referralCode,
      referredByCode: referredByCode ?? this.referredByCode,
      pezeshaId: pezeshaId ?? this.pezeshaId,
    );
  }

  /// Max length of [partialPaymentNote]. A short note, not a contract —
  /// enforced at the input field and worth clamping on read too.
  static const int partialPaymentNoteMaxLength = 200;

  /// Computes the upfront amount, balance amount, and due date for
  /// [orderTotal] using this vendor's STRUCTURED flexible-payment
  /// terms — null whenever there aren't any (vendor wrote free-text
  /// Custom terms, or hasn't set any at all), since there's nothing to
  /// compute from plain words. Callers (order_screen) should fall back
  /// to showing [partialPaymentNote] verbatim when this is null.
  ///
  /// [dueDate] is computed from `DateTime.now()`, matching when the
  /// order is actually placed — a vendor's due-hours are relative to
  /// the order, not to whenever this happens to be called, so avoid
  /// caching a split object across a long-lived screen.
  PartialPaymentSplit? partialPaymentSplitFor(double orderTotal) {
    final percent = partialPaymentPercent;
    final hours = partialPaymentDueHours;
    if (percent == null || hours == null) return null;
    final upfront = orderTotal * percent / 100;
    final balance = orderTotal - upfront;
    return PartialPaymentSplit(
      upfrontAmount: upfront,
      balanceAmount: balance,
      dueDate: DateTime.now().add(Duration(hours: hours)),
    );
  }

  // ── Delivery getters ────────────────────────────────────────────

  /// True once this vendor has explicitly answered the delivery
  /// question by saving their pricing step. Gate EVERY customer-facing
  /// delivery note on this — false means show nothing at all, not
  /// "assume free".
  bool get deliveryPreferenceSet => chargesDeliveryFee != null;

  /// The vendor explicitly chose to deliver free. The only state that
  /// earns a "Free delivery" note — deliberately not `!charges...`,
  /// which would also be true for a vendor who never answered.
  bool get hasFreeDelivery => chargesDeliveryFee == false;

  /// What this vendor actually adds to an order for delivery. 0 for
  /// free delivery AND for an unanswered vendor — an unanswered vendor
  /// has never told us a number, so charging one would be inventing it.
  double get effectiveDeliveryFee =>
      chargesDeliveryFee == true ? deliveryFee : 0.0;

  /// Resolves a Firestore document key to this vendor's stored URL —
  /// the bridge between VendorRequirements' key-based document lists and
  /// this model's typed fields.
  String _docUrl(String key) {
    switch (key) {
      case 'epraCertificateUrl':
        return epraCertificateUrl;
      case 'subDealerAuthorizationUrl':
        return subDealerAuthorizationUrl;
      case 'brandAuthorizationUrl':
        return brandAuthorizationUrl;
      case 'dealerAssociationLetterUrl':
        return dealerAssociationLetterUrl;
      case 'businessPermitUrl':
        return businessPermitUrl;
      case 'businessRegistrationUrl':
        return businessRegistrationUrl;
      case 'fireCertificateUrl':
        return fireCertificateUrl;
      case 'weighingScaleCertUrl':
        return weighingScaleCertUrl;
      case 'weighingScalePhotoUrl':
        return weighingScalePhotoUrl;
      case 'premisesPhotoUrl':
        return premisesPhotoUrl;
      case 'taxClearanceUrl':
        return taxClearanceUrl;
      default:
        // A key in VendorRequirements with no field here. Treated as
        // missing rather than ignored, so it shows up as "not submitted"
        // instead of silently passing — add the field above to fix.
        return '';
    }
  }

  /// True once every compliance document THIS VENDOR'S COUNTRY requires
  /// has at least one acceptable form uploaded — independent of admin
  /// approval (isVerified), so the UI can distinguish "nothing submitted
  /// yet" from "submitted, awaiting review".
  ///
  /// The country-specific part is why this delegates: this getter used to
  /// hardcode Kenya's document set, so a Tanzanian vendor missing their
  /// TRA tax clearance counted as fully submitted. VendorRequirements now
  /// owns the list, and vendor_setup_screen's Step 3 renders from the same
  /// one — so what a vendor is asked for and what counts can't drift.
  bool get documentsSubmitted =>
      VendorRequirements.forCountry(country).documentsSubmitted(
        urlFor: _docUrl,
        isSole: businessType == 'sole',
      );

  /// Automatically locked out of receiving orders because unpaid
  /// platform fees reached the threshold. Unlocks automatically when
  /// admin records payment and feesOwed drops below the threshold.
  bool get isLockedForFees =>
      feesOwed >= MobiGasFees.vendorFeeLockThreshold;

  /// Vendor can appear to customers and receive orders. isVerified is
  /// checked separately at every call site today (order_screen.dart,
  /// vendor_provider.dart) — kept that way rather than folded in here,
  /// so this getter's meaning ("financially in good standing") stays
  /// distinct from "compliance-approved".
  bool get canReceiveOrders => !isSuspended && !isLockedForFees;

  /// True once this vendor has registered with Pezesha. Mirrors
  /// AuthProvider.hasPezeshaId on the customer side — see that getter's
  /// comment for the gating this is meant to support. Whatever holds
  /// VendorModel in memory (VendorProvider or equivalent — not shown
  /// here) should expose this the same way AuthProvider does.
  bool get hasPezeshaId => (pezeshaId ?? '').isNotEmpty;
}

class CustomerModel {
  final String id;
  final String name;
  final String? email;
  final String phone;

  /// A second, optional number the customer can be reached on, set
  /// from the customer profile screen. Purely informational — never
  /// used for OTPs, order updates, or any system-initiated contact;
  /// those all go to `phone`. Empty for every account created before
  /// this field existed.
  final String altPhone;

  final String? deviceFingerprint;
  final bool deviceFlagged;
  /// Kept for the referral fraud guard (recordReferralSignup reads the
  /// customer's own doc rather than trusting call parameters), NOT for
  /// credit underwriting.
  final String nationalId;
  final String county;
  final String area;
  final String estate;
  /// 'KE' | 'TZ' | 'UG' — set once when the customer's delivery pin
  /// is first captured (ProfileCompletionSheet's location step, or the
  /// Google sign-up completion flow), the same way VendorModel.country
  /// is set from the vendor's onboarding pin. Defaults to 'KE' for
  /// legacy accounts created before this field existed, and for any
  /// customer who hasn't pinned a location yet.
  final String country;
  final double latitude;
  final double longitude;
  final String? selfieUrl;
  final String? fcmToken;

  /// This customer's own code to share with others.
  final String referralCode;
  /// The referral code THEY entered at signup, if any — permanent,
  /// never changes after registration.
  final String? referredByCode;

  /// This customer's Pezesha borrower ID, once registered (see
  /// registerPezeshaBorrower in functions/src/pezesha.ts). Null until
  /// then — written into Firestore by that Cloud Function, and pulled
  /// into this model on the next profile read (see
  /// FirestoreService._customerFromMap). AuthProvider.hasPezeshaId
  /// below is the getter screens should actually use.
  final String? pezeshaId;

  const CustomerModel({
    required this.id,
    required this.name,
    this.email,
    required this.phone,
    this.altPhone = '',
    this.deviceFingerprint,
    this.deviceFlagged = false,
    required this.nationalId,
    required this.county,
    required this.area,
    required this.estate,
    this.country = 'KE',
    required this.latitude,
    required this.longitude,
    this.selfieUrl,
    this.fcmToken,
    this.referralCode = '',
    this.referredByCode,
    this.pezeshaId,
  });
}

class OrderModel {
  final String orderId;
  final String customerId;
  final String vendorId;
  final String vendorName;

  /// The vendor's CONTACT number, copied from VendorModel.phone at
  /// order-creation time — what the customer calls about this delivery.
  /// NOT a payout number: the vendor may take payment on a till, a
  /// paybill, or a different line entirely.
  final String vendorPhone;

  final String customerName;
  final String customerArea;
  final String customerPhone;
  final double customerLatitude;
  final double customerLongitude;
  final GasListing listing;
  /// 'KE' | 'TZ' | 'UG' — copied from the vendor at order-creation
  /// time and frozen, same pattern as finderFee.
  final String country;
  final String pin;
  final OrderStatus status;
  final DateTime createdAt;
  final String? riderName;
  final String? riderPhone;

  /// How the customer pays. cash (the default) or bnpl — see the
  /// PaymentMethod comment above for what each means.
  final PaymentMethod paymentMethod;

  /// Customer-finder fee the vendor owes MobiGas for this order
  /// (1% of gas price). Frozen at order time.
  final double finderFee;

  /// The vendor's flat delivery fee for this order, copied from
  /// VendorModel.effectiveDeliveryFee at order-creation time and then
  /// FROZEN — exactly like finderFee and country. A vendor raising
  /// their fee tomorrow must never change what an order placed today
  /// cost, so this is stored on the order rather than looked up from
  /// the vendor doc when the order is displayed.
  ///
  /// 0 for free delivery, for a vendor who has never set a preference,
  /// and for every order placed before this field existed. Kept
  /// separate from listing.price (rather than summed into it) for two
  /// reasons: the 1% finder fee is computed off the gas price alone,
  /// and the vendor's earnings aggregate sums the `gasPrice` field —
  /// folding delivery in would silently change both.
  final double deliveryFee;

  /// Pezesha's loan ID for this order — set only when paymentMethod ==
  /// bnpl. This is the loanId PezeshaService.applyLoan returns after
  /// BnplCheckoutOption's loan application is approved; the checkout
  /// flow should attach it here BEFORE calling createOrder (loan
  /// approval happens first, order creation second — see
  /// BnplCheckoutOption.onApproved), not backfill it afterward. Null
  /// for every cash order. Null on a bnpl order means the loan record
  /// wasn't attached — treat that as a data problem worth flagging to
  /// support, not as "no loan exists" (getPezeshaLoanStatus/History
  /// are the source of truth if this ever needs reconciling).
  final String? loanId;

  // ── Flexible payment: A MESSAGE, NOT A LEDGER ───────────────────
  //
  // The customer ticked the vendor's flexible-payment option at
  // checkout. These five fields exist for ONE reason: so the vendor
  // learns, at order time, that their customer intends to take them up
  // on the terms the vendor themselves published — and so both sides
  // are looking at the same numbers rather than two different
  // recollections of them.
  //
  // What MobiGas does with them: shows them to the vendor, shows them
  // to the customer, and stops.
  //
  // What MobiGas does NOT do, and what nothing here should ever be
  // extended to do: hold the money, split the payment, tell a rider
  // what to collect, compute what remains outstanding, remind anyone of
  // a due date, mark a balance settled, or treat a missed balance as a
  // default. HOW the vendor collects is between the vendor and the
  // customer. There is deliberately no `partialSettled` /
  // `partialPaidAt` / `balanceOutstanding` field here, and no security
  // rule permitting one to be written (see the orders block in
  // firestore.rules) — the moment one exists, MobiGas is the ledger for
  // a debt it is not party to, and the disclaimer shown to the customer
  // at checkout stops being true.
  //
  // Different thing entirely from PaymentMethod.bnpl, which IS a credit
  // product — one Pezesha underwrites and collects and MobiGas merely
  // introduces. paymentMethod stays `cash` on a flexible-payment order:
  // the customer still pays the vendor directly, just not all at once.

  /// The customer opted into this vendor's flexible-payment terms at
  /// checkout. False for every order where they didn't, and for every
  /// order placed before this field existed.
  ///
  /// Can only ever be true for a vendor whose own acceptsPartialPayment
  /// is true — enforced at order-create time in firestore.rules rather
  /// than only in the client, because the vendor app renders this as
  /// something the vendor themselves offered.
  final bool partialPayment;

  /// The upfront figure the customer was shown when they opted in,
  /// computed from the vendor's own preset against [customerTotal].
  /// 0 when the vendor publishes free-text terms instead of a preset —
  /// there is then no number to show, and [partialTerms] carries the
  /// whole arrangement.
  ///
  /// A RECORD OF WHAT WAS DISPLAYED. Not an instruction, not an amount
  /// due, not something to reconcile against.
  final double partialUpfront;

  /// The balance figure shown alongside [partialUpfront], on the same
  /// terms and with the same caveat. 0 when there was no preset.
  final double partialBalance;

  /// The date the customer was shown for the balance, derived from the
  /// vendor's own due-hours at order time. Null when there was no
  /// preset, and for every order placed before this field existed.
  ///
  /// Nothing watches this date. No reminder fires from it, no status
  /// changes because of it, and an order whose date has passed is not
  /// overdue in any sense MobiGas recognises.
  final DateTime? partialDueBy;

  /// The vendor's own published note, verbatim as the customer read it
  /// at checkout, frozen here so a vendor editing their profile next
  /// week cannot change what this customer was told. Empty when the
  /// vendor published a preset with no accompanying note.
  final String partialTerms;

  /// 'customer' | 'vendor' | null — who cancelled this order. Both
  /// paths write status=cancelled, so this is the only way to tell
  /// "customer changed their mind" from "vendor declined the order"
  /// apart afterward. Null for orders cancelled before this field
  /// existed, or for any order that was never cancelled.
  final String? cancelledBy;

  const OrderModel({
    required this.orderId,
    required this.customerId,
    required this.vendorId,
    required this.vendorName,
    required this.vendorPhone,
    required this.customerName,
    required this.customerArea,
    this.customerPhone = '',
    this.customerLatitude = 0.0,
    this.customerLongitude = 0.0,
    required this.listing,
    this.country = 'KE',
    required this.pin,
    required this.status,
    required this.createdAt,
    this.riderName,
    this.riderPhone,
    this.paymentMethod = PaymentMethod.cash,
    this.finderFee = 0.0,
    this.deliveryFee = 0.0,
    this.loanId,
    this.partialPayment = false,
    this.partialUpfront = 0.0,
    this.partialBalance = 0.0,
    this.partialDueBy,
    this.partialTerms = '',
    this.cancelledBy,
  });

  /// What the customer pays in total for the order: the gas price plus
  /// the vendor's flat delivery fee (0 when they deliver free, which is
  /// the case for every order predating that feature).
  ///
  /// Unchanged by paymentMethod — cash and bnpl orders cost the
  /// customer the same; the difference is WHO they pay and WHEN (vendor
  /// now in cash, Pezesha over time in bnpl), not how much. Any
  /// interest/fee owed on a bnpl order is Pezesha's loan terms
  /// (offer.rate/interest/fee — see PezeshaLoanOffer), owed to Pezesha,
  /// and never added here — MobiGas still adds nothing of its own.
  ///
  /// ALSO unchanged by partialPayment, and that one matters most. A
  /// flexible-payment order is worth exactly what any other order is
  /// worth; the customer simply intends to hand it over in more than
  /// one go, by arrangement with the vendor. Every surface that shows
  /// what an order is WORTH — the vendor's header, the customer's
  /// summary, the rider handoff message, the earnings screens — shows
  /// THIS, never partialUpfront. Substituting the upfront figure would
  /// be MobiGas quietly repricing a sale on the strength of a private
  /// arrangement it is not part of.
  double get customerTotal => listing.price + deliveryFee;

  /// True when there are concrete figures to show alongside the
  /// flexible-payment note. False when the customer opted in against a
  /// vendor's free-text terms, where [partialTerms] is the whole story.
  bool get hasPartialFigures =>
      partialPayment && (partialUpfront > 0 || partialBalance > 0);
}

enum OrderStatus {
  pending,
  accepted,
  outForDelivery,
  delivered,
  cancelled,
}

// ── FEATURE FLAGS ─────────────────────────────────────────────────────────
// Flip to true to activate features
class FeatureFlags {
  // Vendor stock boost — a REFERRAL to a finance partner, not a loan
  // from MobiGas. Gates nothing in code today; the real gate is
  // stockBoostEligibility, written by the nightly server sweep.
  static const bool stockBoostReferral = true;
  // Pezesha vendor-stock-loan + customer-BNPL flows. Gates whether the
  // Pezesha cards render at all, independent of the finer-grained
  // platform_settings/financing country gate (FinancingConfigService) —
  // this flag is the kill switch; that config is the country dial.
  static const bool pezeshaFinancing = true;
  static const bool mpesaStkPush = false;         // In-app M-Pesa repayment
  static const bool vehicleLeasing = false;       // Vehicle leasing marketplace
  static const bool cargoInsurance = false;       // Cargo insurance
  static const bool cashOrders = true;            // Pay-on-delivery orders
}