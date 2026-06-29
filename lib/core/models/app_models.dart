// All gas product types
enum GasProductType {
  refill,           // Gas refill only (most common)
  fullKit,          // Gas + New cylinder
  grillKit,         // 6kg Gas + Cylinder + Stove/Grill + Regulator + Pipe
}

extension GasProductTypeExt on GasProductType {
  String get label {
    switch (this) {
      case GasProductType.refill:
        return 'Refill';
      case GasProductType.fullKit:
        return 'Full Kit (Gas + Cylinder)';
      case GasProductType.grillKit:
        return 'Grill Kit (Gas + Cylinder + Stove + Grill)';
    }
  }

  String get description {
    switch (this) {
      case GasProductType.refill:
        return 'Gas refill only — exchange your empty cylinder';
      case GasProductType.fullKit:
        return 'New gas cylinder + gas — no empty cylinder needed';
      case GasProductType.grillKit:
        return '6kg gas + cylinder + LPG stove + grill — complete package';
    }
  }

  bool isAvailableForSize(String size) {
    if (this == GasProductType.grillKit) return size == '6kg';
    return true;
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
  // MobiGas earns 1% of disbursement from bank per order
  static const double bankCommissionRate = 0.01;
  // Bank charges customer (bank sets — we show for transparency)
  static const double bankInterestRate = 0.08;
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

  // Bank interest (8%) — bank charges customer
  double get bankInterest => price * MobiGasFees.bankInterestRate;

  // What customer repays to bank
  double get customerRepayment => price + bankInterest;

  // MobiGas earns from bank (1%) — never shown to customer
  double get mobigasCommission => price * MobiGasFees.bankCommissionRate;
}

class VendorModel {
  final String id;
  final String businessName;
  final String ownerName;
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

  const VendorModel({
    required this.id,
    required this.businessName,
    required this.ownerName,
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
  });
}

enum BankApprovalStatus { pending, approved, rejected }

class CustomerModel {
  final String id;
  final String name;
  final String phone;
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
    required this.phone,
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
  });
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
enum StockLoanStatus { pending, approved, disbursed, repaying, repaid, rejected }

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
}
