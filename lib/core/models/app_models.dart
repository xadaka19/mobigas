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

  const GasListing({
    required this.size,
    required this.kg,
    required this.price,
    required this.available,
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
      interestRate: 0.08,
      maxRepaymentDays: 30,
      minLoanAmount: 500,
      maxLoanAmount: 5000,
    ),
  ];
}
