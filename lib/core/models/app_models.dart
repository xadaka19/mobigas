// All gas product types
enum GasProductType {
  refill,           // Gas refill only (most common)
  fullKit,          // Gas + New cylinder
  grillKit,         // 6kg Gas + Cylinder + Burner/Grill + Regulator + Pipe
  burner,           // Standalone burner — fits 3kg or 6kg cylinders
  regulator,        // Standalone regulator — fits 13kg cylinders
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
      this == GasProductType.burner || this == GasProductType.regulator;
}

// How the customer pays for an order
enum PaymentMethod {
  credit, // Bank pays vendor, customer repays bank within 30 days
  cash,   // Customer pays vendor cash on delivery
}

extension PaymentMethodExt on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.credit:
        return 'MobiGas Credit';
      case PaymentMethod.cash:
        return 'Cash on delivery';
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
  // MobiGas earns 1% of disbursement from bank per credit order
  static const double bankCommissionRate = 0.01;
  // Bank charges customer (bank sets — we show for transparency)
  static const double bankInterestRate = 0.08;
  // Vendor pays MobiGas 1% customer-finder fee on cash orders,
  // accrued when the order is confirmed delivered, settled weekly.
  static const double cashFinderFeeRate = 0.01;
  // When a vendor's unpaid fees reach this amount (KES), they are
  // automatically hidden from customers until they settle.
  static const double vendorFeeLockThreshold = 500;
}

/// Eligibility thresholds for the Stock Boost Loan — a vendor needs
/// BOTH conditions met, not either. Single source of truth so the
/// numbers shown in the vendor app's progress bars always match the
/// numbers actually enforced in the eligibility check.
class StockLoanRequirements {
  static const int minMonthsOnPlatform = 3;
  static const int minDeliveries = 100;
}

class GasListing {
  final String size;
  final int kg;
  final double price;
  final bool available;
  final GasProductType productType;

  const GasListing({
    required this.size,
    required this.kg,
    required this.price,
    required this.available,
    this.productType = GasProductType.refill,
  });

  // Bank interest (8%) — bank charges customer (credit orders only)
  double get bankInterest => price * MobiGasFees.bankInterestRate;

  // What customer repays to bank (credit orders only)
  double get customerRepayment => price + bankInterest;

  // MobiGas earns from bank (1%) — never shown to customer
  double get mobigasCommission => price * MobiGasFees.bankCommissionRate;

  // Vendor owes MobiGas on a cash order (1%) — never shown to customer
  double get cashFinderFee => price * MobiGasFees.cashFinderFeeRate;
}

class VendorModel {
  final String id;
  final String businessName;
  final String ownerName;
  final String? email;
  final String phone;
  final String area;
  final String estate;
  final String county;
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

  /// Accumulated unpaid customer-finder fees from cash orders (KES).
  final double feesOwed;

  /// Suspended by admin for unpaid platform fees — receives NO orders
  /// (credit or cash) until cleared.
  final bool isSuspended;

  // ── Verification documents ──────────────────────────────────────
  // Uploaded once during onboarding; reviewed by admin before
  // isVerified is set to true. All fields empty until submitted.
  // Three of these are "either/or" pairs — a vendor satisfies the
  // requirement with whichever one they can actually get, not both:
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

  /// 'sole' | 'registered' | 'petrol_station' — determines whether
  /// businessRegistrationUrl is required (sole proprietors didn't
  /// previously have to prove registration at all; now they do).
  final String businessType;

  const VendorModel({
    required this.id,
    required this.businessName,
    required this.ownerName,
    this.email,
    required this.phone,
    required this.area,
    required this.estate,
    required this.county,
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
    this.businessType = '',
  });

  /// True once every required compliance document has at least one
  /// acceptable form uploaded — independent of admin approval
  /// (isVerified), so the UI can distinguish "nothing submitted yet"
  /// from "submitted, awaiting review".
  bool get documentsSubmitted {
    final hasEpraProof =
        epraCertificateUrl.isNotEmpty || subDealerAuthorizationUrl.isNotEmpty;
    final hasScaleProof =
        weighingScaleCertUrl.isNotEmpty || weighingScalePhotoUrl.isNotEmpty;
    final hasBrandProof = brandAuthorizationUrl.isNotEmpty ||
        dealerAssociationLetterUrl.isNotEmpty;
    // Registered companies and petrol stations already prove this via
    // their Step-1 certificate (Certificate of Incorporation) — only
    // sole proprietors need the separate BRS business-name document.
    final hasBusinessReg =
        businessType != 'sole' || businessRegistrationUrl.isNotEmpty;
    return hasEpraProof &&
        businessPermitUrl.isNotEmpty &&
        fireCertificateUrl.isNotEmpty &&
        premisesPhotoUrl.isNotEmpty &&
        hasScaleProof &&
        hasBrandProof &&
        hasBusinessReg;
  }

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

enum BankApprovalStatus { pending, approved, rejected }

class CustomerModel {
  final String id;
  final String name;
  final String? email;
  final String phone;
  final String? deviceFingerprint;
  final bool deviceFlagged;
  final String nationalId;
  final String county;
  final String area;
  final String estate;
  final double latitude;
  final double longitude;
  final double? bankApprovedLimit;
  final double bankCreditUsed;
  final BankApprovalStatus bankStatus;
  final String partnerBankName;
  final List<GuarantorModel> guarantors;
  final String? selfieUrl;
  final String? fcmToken;

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
    required this.latitude,
    required this.longitude,
    this.bankApprovedLimit,
    required this.bankCreditUsed,
    required this.bankStatus,
    required this.partnerBankName,
    required this.guarantors,
    this.selfieUrl,
    this.fcmToken,
  });

  double get bankCreditAvailable =>
      (bankApprovedLimit ?? 0) - bankCreditUsed;

  bool get isBankApproved =>
      bankStatus == BankApprovalStatus.approved &&
      bankApprovedLimit != null;

  bool canAfford(GasListing listing) =>
      bankCreditAvailable >= listing.price;
}

class GuarantorModel {
  final String name;
  final String phone;
  const GuarantorModel({required this.name, required this.phone});
}

class OrderModel {
  final String orderId;
  final String customerId;
  final String vendorId;
  final String vendorName;
  final String vendorPhone;
  final String customerName;
  final String customerArea;
  final double customerLatitude;
  final double customerLongitude;
  final GasListing listing;
  final double bankDisbursementAmount;
  final double originationFeeToMobigas;
  final String pin;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? bankRepaymentDueDate;
  final String? riderName;
  final String? riderPhone;
  final String partnerBankName;

  /// How the customer pays: credit (bank pays vendor) or cash on delivery.
  final PaymentMethod paymentMethod;

  /// Customer-finder fee the vendor owes MobiGas for this order
  /// (cash orders only, 1% of gas price). Frozen at order time.
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
    this.customerLatitude = 0.0,
    this.customerLongitude = 0.0,
    required this.listing,
    required this.bankDisbursementAmount,
    required this.originationFeeToMobigas,
    required this.pin,
    required this.status,
    required this.createdAt,
    this.bankRepaymentDueDate,
    this.riderName,
    this.riderPhone,
    required this.partnerBankName,
    this.paymentMethod = PaymentMethod.credit,
    this.finderFee = 0.0,
    this.cancelledBy,
  });

  /// What the customer actually pays in total:
  /// cash → gas price handed to the vendor;
  /// credit → gas price + bank interest repaid to the bank.
  double get customerTotal => paymentMethod == PaymentMethod.cash
      ? listing.price
      : listing.customerRepayment;
}

enum OrderStatus {
  pending,
  bankApprovalPending,
  accepted,
  outForDelivery,
  delivered,
  repaying,
  completed,
  defaulted,
  cancelled,
}

class PartnerBank {
  final String id;
  final String name;
  final String type;
  final double interestRate;
  final int maxRepaymentDays;
  final double minLoanAmount;
  final double maxLoanAmount;

  const PartnerBank({
    required this.id,
    required this.name,
    required this.type,
    required this.interestRate,
    required this.maxRepaymentDays,
    required this.minLoanAmount,
    required this.maxLoanAmount,
  });
}

// ── STOCK BOOST LOAN ──────────────────────────────────────────────────────
enum StockLoanStatus {
  pending,          // Vendor submitted application
  submittedToBank,  // MobiGas sent to bank API
  bankApproved,     // Bank approved loan amount
  bankRejected,     // Bank rejected
  disbursed,        // Bank sent funds to vendor M-Pesa
  repaying,         // Vendor repaying
  repaid,           // Fully repaid
}

class StockLoanApplication {
  final String id;
  final String vendorId;
  final String vendorName;
  final double requestedAmount;
  final double approvedAmount;
  final StockLoanStatus status;
  final DateTime appliedAt;
  final String partnerBankName;
  final int monthsOnPlatform;
  final int totalDeliveries;
  final double averageMonthlyRevenue;

  const StockLoanApplication({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.requestedAmount,
    required this.approvedAmount,
    required this.status,
    required this.appliedAt,
    required this.partnerBankName,
    required this.monthsOnPlatform,
    required this.totalDeliveries,
    required this.averageMonthlyRevenue,
  });
}

// ── FEATURE FLAGS ─────────────────────────────────────────────────────────
// Flip to true to activate features
class FeatureFlags {
  static const bool stockBoostLoan = true;      // Vendor stock loans
  static const bool mpesaStkPush = false;         // In-app M-Pesa repayment
  static const bool vehicleLeasing = false;       // Vehicle leasing marketplace
  static const bool cargoInsurance = false;       // Cargo insurance
  static const bool embeddedFinance = false;      // Full embedded finance suite
  static const bool cashOrders = true;            // Cash-on-delivery orders
}