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
// Only one way, deliberately. MobiGas does not extend credit and does
// not intermediate payment — the customer pays the vendor directly on
// delivery (cash or mobile money straight to the vendor). The old
// `credit` value (bank pays vendor, customer repays bank) was a BNPL
// design that never shipped: no order was ever created with it, and
// the functions behind it were never deployed. Removed rather than
// left dormant, so no screen can ever render "MobiGas Credit" and no
// reader has to wonder whether we lend.
//
// Parsers use `orElse: () => PaymentMethod.cash`, so any legacy
// Firestore doc carrying paymentMethod:'credit' degrades to cash
// rather than throwing. There are none.
enum PaymentMethod {
  cash, // Customer pays the vendor on delivery — cash or mobile money
}

extension PaymentMethodExt on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cash:
        return 'Pay on delivery';
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
  double get cashFinderFee => price * MobiGasFees.cashFinderFeeRate;
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
  /// (vendor_home_screen, vendor_fees_banner). This model is what the
  /// CUSTOMER app knows about a vendor, and the customer never needs to
  /// know how the vendor gets paid; they hand over cash or send money to
  /// a number given at the door. OrderModel.vendorPhone copies THIS field
  /// — don't "fix" it into a payout number.
  final String phone;

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

  /// This vendor's own code to share with others.
  final String referralCode;
  /// The referral code THEY entered at setup, if any — permanent.
  final String? referredByCode;

  const VendorModel({
    required this.id,
    required this.businessName,
    required this.ownerName,
    this.email,
    required this.phone,
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
    this.referralCode = '',
    this.referredByCode,
  });

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
}

class CustomerModel {
  final String id;
  final String name;
  final String? email;
  final String phone;
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

  const CustomerModel({
    required this.id,
    required this.name,
    this.email,
    required this.phone,
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

  /// How the customer pays. Only one value exists — kept as a field
  /// rather than dropped entirely because every order document in
  /// Firestore carries it, and confirmDelivery still reads it when
  /// deciding whether the finder fee is chargeable.
  final PaymentMethod paymentMethod;

  /// Customer-finder fee the vendor owes MobiGas for this order
  /// (1% of gas price). Frozen at order time.
  final double finderFee;

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
    this.cancelledBy,
  });

  /// What the customer pays in total: the gas price, handed to the
  /// vendor on delivery. Nothing is added — no interest, no fee.
  double get customerTotal => listing.price;
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
  static const bool mpesaStkPush = false;         // In-app M-Pesa repayment
  static const bool vehicleLeasing = false;       // Vehicle leasing marketplace
  static const bool cargoInsurance = false;       // Cargo insurance
  static const bool cashOrders = true;            // Pay-on-delivery orders
}