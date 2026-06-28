// ── Fee constants ─────────────────────────────────────────────────────
class MobiGasFees {
  // Charged to customer every order — added to repayment
  static const double crbCheckFee = 60.0;

  // MobiGas earns from bank per disbursement (1% of gas price)
  static const double bankOriginationRate = 0.01;

  // Bank charges customer (bank sets this — we show it for transparency)
  // Typical SACCO/MFI rate: 8-15% per month on reducing balance
  // We show an estimate only — actual set by bank
  static const double estimatedBankInterestRate = 0.10; // 10% flat for display
}

// ── Gas listing (vendor sets price) ──────────────────────────────────
class GasListing {
  final String size;
  final int kg;
  final double price; // vendor sets this
  final bool available;

  const GasListing({
    required this.size,
    required this.kg,
    required this.price,
    required this.available,
  });

  // MobiGas origination fee (paid by bank to MobiGas)
  double get originationFee => price * MobiGasFees.bankOriginationRate;

  // CRB fee paid by customer every order
  double get crbFee => MobiGasFees.crbCheckFee;

  // Total customer repays to bank (gas price + bank interest + crb fee)
  // Bank interest is set by bank — we show estimate
  double get estimatedBankInterest =>
      price * MobiGasFees.estimatedBankInterestRate;

  // What customer repays (gas + estimated bank interest + CRB fee)
  double get estimatedTotalRepayment =>
      price + estimatedBankInterest + crbFee;

  // What MobiGas earns per order
  double get mobigasEarning => originationFee + crbFee;
}

// ── Vendor ────────────────────────────────────────────────────────────
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

// ── Customer ──────────────────────────────────────────────────────────
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
  final CrbStatus crbStatus;
  final double? bankApprovedLimit; // set by bank after their check
  final double bankCreditUsed;
  final List<GuarantorModel> guarantors;

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
    required this.crbStatus,
    this.bankApprovedLimit,
    required this.bankCreditUsed,
    required this.guarantors,
  });

  double get bankCreditAvailable =>
      (bankApprovedLimit ?? 0) - bankCreditUsed;

  bool get isBankApproved =>
      crbStatus == CrbStatus.approved && bankApprovedLimit != null;

  // Can customer afford this listing?
  // Bank covers gas price, customer pays CRB fee separately
  bool canAfford(GasListing listing) {
    return bankCreditAvailable >= listing.price;
  }
}

class GuarantorModel {
  final String name;
  final String phone;
  const GuarantorModel({required this.name, required this.phone});
}

enum CrbStatus { unchecked, pending, approved, rejected }

// ── Order ─────────────────────────────────────────────────────────────
class OrderModel {
  final String orderId;
  final String customerId;
  final String vendorId;
  final String vendorName;
  final String vendorPhone;
  final String customerName;
  final String customerArea;
  final GasListing listing;
  final double crbFee;
  final double bankDisbursementAmount; // bank pays vendor this
  final double originationFeeToMobigas; // bank pays mobigas this
  final String pin;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? bankRepaymentDueDate; // set by bank
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
    required this.listing,
    required this.crbFee,
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

  // What customer owes bank (bank sets actual amount)
  double get estimatedCustomerRepayment =>
      listing.estimatedTotalRepayment;

  // CRB fee customer pays MobiGas separately
  double get customerCrbFee => crbFee;
}

enum OrderStatus {
  pending,
  crbCheckPending,
  bankApprovalPending,
  accepted,
  outForDelivery,
  delivered,
  repaying,
  completed,
  defaulted,
}

// ── Partner banks/SACCOs ──────────────────────────────────────────────
class PartnerBank {
  final String id;
  final String name;
  final String type; // 'bank', 'sacco', 'mfi'
  final double interestRate; // monthly rate
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

// ── Mock data for pilot ───────────────────────────────────────────────
class MockData {
  static List<VendorModel> get vendors => [
    VendorModel(
      id: 'v001',
      businessName: 'Kamau Gas Supplies',
      ownerName: 'James Kamau',
      phone: '0722123456',
      area: 'Kasarani',
      estate: 'Mirema Drive',
      county: 'Nairobi',
      latitude: -1.2234,
      longitude: 36.8901,
      brands: ['Total', 'K-Gas'],
      listings: [
        GasListing(size: '3kg', kg: 3, price: 750, available: true),
        GasListing(size: '6kg', kg: 6, price: 1500, available: true),
        GasListing(size: '13kg', kg: 13, price: 3200, available: false),
      ],
      rating: 4.8,
      totalReviews: 124,
      isOnline: true,
      isVerified: true,
      distance: '0.4 km',
      deliveryTime: '20–35 min',
    ),
    VendorModel(
      id: 'v002',
      businessName: 'Wanjiku Petroleum',
      ownerName: 'Grace Wanjiku',
      phone: '0733456789',
      area: 'Kasarani',
      estate: 'Bypass Road',
      county: 'Nairobi',
      latitude: -1.2256,
      longitude: 36.8923,
      brands: ['Orion', 'Afrigaz', 'Pro Gas'],
      listings: [
        GasListing(size: '3kg', kg: 3, price: 730, available: true),
        GasListing(size: '6kg', kg: 6, price: 1480, available: true),
        GasListing(size: '13kg', kg: 13, price: 3150, available: true),
      ],
      rating: 4.6,
      totalReviews: 89,
      isOnline: true,
      isVerified: true,
      distance: '1.1 km',
      deliveryTime: '30–45 min',
    ),
    VendorModel(
      id: 'v003',
      businessName: 'Mwangi Gas Centre',
      ownerName: 'Peter Mwangi',
      phone: '0711234567',
      area: 'Kasarani',
      estate: 'Mirema Estate',
      county: 'Nairobi',
      latitude: -1.2267,
      longitude: 36.8934,
      brands: ['K-Gas', 'Total', 'Hashi'],
      listings: [
        GasListing(size: '3kg', kg: 3, price: 760, available: true),
        GasListing(size: '6kg', kg: 6, price: 1520, available: true),
        GasListing(size: '13kg', kg: 13, price: 3250, available: false),
      ],
      rating: 4.5,
      totalReviews: 67,
      isOnline: false,
      isVerified: true,
      distance: '1.8 km',
      deliveryTime: '35–50 min',
    ),
  ];

  static List<PartnerBank> get partnerBanks => [
    PartnerBank(
      id: 'b001',
      name: 'Stima SACCO',
      type: 'sacco',
      interestRate: 0.12,
      maxRepaymentDays: 30,
      minLoanAmount: 500,
      maxLoanAmount: 5000,
    ),
    PartnerBank(
      id: 'b002',
      name: 'Kenya Women MFI',
      type: 'mfi',
      interestRate: 0.15,
      maxRepaymentDays: 30,
      minLoanAmount: 500,
      maxLoanAmount: 3500,
    ),
  ];

  // MobiGas CRB check result (mock)
  // Real: calls Metropol API with nationalId + phone
  static Map<String, dynamic> mockCrbResult(String nationalId) {
    return {
      'score': 680,
      'status': 'approved',
      'hasDefaults': false,
      'activeLoans': 0,
      'reportRef': 'CRB-${DateTime.now().millisecondsSinceEpoch}',
    };
  }

  // Bank pre-qualification (mock)
  // Real: MobiGas sends CRB report to bank API
  // Bank returns approved limit
  static double mockBankApprovedLimit(Map<String, dynamic> crbResult) {
    final score = crbResult['score'] as int;
    if (score >= 700) return 5000;
    if (score >= 600) return 3200;
    if (score >= 500) return 1500;
    return 0; // rejected
  }
}
