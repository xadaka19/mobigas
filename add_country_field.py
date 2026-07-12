import sys

def replace_once(path, old, new, label):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    count = content.count(old)
    if count != 1:
        print(f"FAILED [{label}] in {path}: expected 1 match, found {count}")
        print("---- looking for ----")
        print(old)
        sys.exit(1)
    content = content.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"OK: {label}")

replace_once(
    "lib/core/models/app_models.dart",
    "  final double latitude;\n"
    "  final double longitude;\n"
    "  final List<String> brands;\n"
    "  final List<GasListing> listings;",
    "  final String country; // 'KE' | 'TZ' | 'UG' — set once at onboarding from GPS\n"
    "  final double latitude;\n"
    "  final double longitude;\n"
    "  final List<String> brands;\n"
    "  final List<GasListing> listings;",
    "VendorModel field: country",
)

replace_once(
    "lib/core/models/app_models.dart",
    "    required this.county,\n"
    "    required this.latitude,\n"
    "    required this.longitude,\n"
    "    required this.brands,\n"
    "    required this.listings,",
    "    required this.county,\n"
    "    this.country = 'KE',\n"
    "    required this.latitude,\n"
    "    required this.longitude,\n"
    "    required this.brands,\n"
    "    required this.listings,",
    "VendorModel constructor: country",
)

replace_once(
    "lib/core/models/app_models.dart",
    "  final GasListing listing;\n"
    "  final double bankDisbursementAmount;",
    "  final GasListing listing;\n"
    "  /// 'KE' | 'TZ' | 'UG' — copied from the vendor at order-creation\n"
    "  /// time and frozen, same pattern as finderFee.\n"
    "  final String country;\n"
    "  final double bankDisbursementAmount;",
    "OrderModel field: country",
)

replace_once(
    "lib/core/models/app_models.dart",
    "    required this.listing,\n"
    "    required this.bankDisbursementAmount,",
    "    required this.listing,\n"
    "    this.country = 'KE',\n"
    "    required this.bankDisbursementAmount,",
    "OrderModel constructor: country",
)

replace_once(
    "lib/core/services/firestore_service.dart",
    "      county: data['county'] ?? '',\n"
    "      latitude: (data['latitude'] ?? 0.0).toDouble(),\n"
    "      longitude: (data['longitude'] ?? 0.0).toDouble(),\n"
    "      brands: List<String>.from(data['brands'] ?? []),",
    "      county: data['county'] ?? '',\n"
    "      country: data['country'] ?? 'KE',\n"
    "      latitude: (data['latitude'] ?? 0.0).toDouble(),\n"
    "      longitude: (data['longitude'] ?? 0.0).toDouble(),\n"
    "      brands: List<String>.from(data['brands'] ?? []),",
    "vendorFromMap: read country",
)

replace_once(
    "lib/core/services/firestore_service.dart",
    "      'gasBrand': order.listing.brand,\n"
    "      'paymentMethod': order.paymentMethod.name,",
    "      'gasBrand': order.listing.brand,\n"
    "      'country': order.country,\n"
    "      'paymentMethod': order.paymentMethod.name,",
    "createOrder: write country",
)

replace_once(
    "lib/core/services/firestore_service.dart",
    "        brand: data['gasBrand'] ?? '',\n"
    "      ),\n"
    "      paymentMethod: PaymentMethod.values.firstWhere(",
    "        brand: data['gasBrand'] ?? '',\n"
    "      ),\n"
    "      country: data['country'] ?? 'KE',\n"
    "      paymentMethod: PaymentMethod.values.firstWhere(",
    "_orderFromMap: read country",
)

replace_once(
    "lib/core/providers/order_provider.dart",
    "import 'package:mobigas/core/services/firebase_service.dart';",
    "import 'package:mobigas/core/services/firebase_service.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';",
    "order_provider.dart: import currency.dart",
)

replace_once(
    "lib/core/providers/order_provider.dart",
    "        listing: listing,\n"
    "        paymentMethod: PaymentMethod.cash,",
    "        listing: listing,\n"
    "        country: vendor.country,\n"
    "        paymentMethod: PaymentMethod.cash,",
    "order_provider.dart: OrderModel(country: vendor.country)",
)

replace_once(
    "lib/core/providers/order_provider.dart",
    "'${customer.name} ordered ${listing.size} ${_typeLabel(listing.productType)} · KES ${listing.price.toStringAsFixed(0)} · CASH on delivery',",
    "'${customer.name} ordered ${listing.size} ${_typeLabel(listing.productType)} · ${Currency.formatFor(vendor.country, listing.price)} · CASH on delivery',",
    "order_provider.dart: notification body uses Currency.formatFor",
)

print("\nAll edits applied successfully.")
