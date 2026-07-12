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

# ══════════════════ delivery_notification_service.dart ══════════════════
F0 = "lib/core/services/delivery_notification_service.dart"

replace_once(F0,
    "      body: '$gasSize delivered · Paid KES $amount — thank you!',",
    "      body: '$gasSize delivered · Paid $amount — thank you!',",
    "delivery_notification_service: drop hardcoded KES (caller now passes formatted amount)")

# ══════════════════ order_tracking_screen.dart ══════════════════
F1 = "lib/features/customer/screens/order_tracking_screen.dart"

replace_once(F1,
    "import 'package:mobigas/core/services/delivery_notification_service.dart';\n"
    "import 'package:mobigas/core/services/screen_security_service.dart';",
    "import 'package:mobigas/core/services/delivery_notification_service.dart';\n"
    "import 'package:mobigas/core/services/screen_security_service.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';",
    "order_tracking_screen: import currency.dart")

replace_once(F1,
    "      DeliveryNotificationService.showDeliveryConfirmed(\n"
    "        gasSize: _order?.listing.size ?? '',\n"
    "        // Cash on delivery — customerTotal is the gas price, the same\n"
    "        // figure shown on the vendor card and the PIN panel.\n"
    "        amount: _order?.customerTotal.toStringAsFixed(0) ?? '',\n"
    "      );",
    "      DeliveryNotificationService.showDeliveryConfirmed(\n"
    "        gasSize: _order?.listing.size ?? '',\n"
    "        // Cash on delivery — customerTotal is the gas price, the same\n"
    "        // figure shown on the vendor card and the PIN panel. Already\n"
    "        // includes the currency symbol for the order's country.\n"
    "        amount: Currency.formatFor(_order?.country, _order?.customerTotal ?? 0),\n"
    "      );",
    "order_tracking_screen: notification amount uses Currency.formatFor")

replace_once(F1,
    "                  Text(\n"
    "                    'KES ${order.customerTotal.toStringAsFixed(0)}',\n"
    "                    style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                          color: AppColors.orange,\n"
    "                          fontWeight: FontWeight.w700,\n"
    "                        ),\n"
    "                  ),",
    "                  Text(\n"
    "                    Currency.formatFor(order.country, order.customerTotal),\n"
    "                    style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                          color: AppColors.orange,\n"
    "                          fontWeight: FontWeight.w700,\n"
    "                        ),\n"
    "                  ),",
    "order_tracking_screen: bottom card price")

replace_once(F1,
    "                Text(\n"
    "                  'Pay the vendor KES ${order.customerTotal.toStringAsFixed(0)} first (cash or M-Pesa), then show this PIN',",
    "                Text(\n"
    "                  'Pay the vendor ${Currency.formatFor(order.country, order.customerTotal)} first (cash or M-Pesa), then show this PIN',",
    "order_tracking_screen: PIN panel payment instruction")

# ══════════════════ order_screen.dart ══════════════════
F2 = "lib/features/customer/screens/order_screen.dart"

replace_once(F2,
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "\n"
    "class OrderScreen extends StatefulWidget {",
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';\n"
    "\n"
    "class OrderScreen extends StatefulWidget {",
    "order_screen: import currency.dart")

replace_once(F2,
    "  double get _gasPrice => _selectedListing?.price ?? 0;",
    "  double get _gasPrice => _selectedListing?.price ?? 0;\n"
    "\n"
    "  /// Currency follows the vendor being ordered from — set once at\n"
    "  /// vendor onboarding from GPS, not a customer preference.\n"
    "  String get _vendorCountry => _selectedVendor?.country ?? 'KE';",
    "order_screen: add _vendorCountry getter")

replace_once(F2,
    "                Text('KES ${listing.price.toStringAsFixed(0)}',\n"
    "                    style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                          color: AppColors.orange,\n"
    "                          fontWeight: FontWeight.w800,\n"
    "                          fontSize: 16,\n"
    "                        )),",
    "                Text(Currency.formatFor(vendor.country, listing.price),\n"
    "                    style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                          color: AppColors.orange,\n"
    "                          fontWeight: FontWeight.w800,\n"
    "                          fontSize: 16,\n"
    "                        )),",
    "order_screen: offer row price")

replace_once(F2,
    "              _feeRow(\n"
    "                  '${_shortTypeLabel(_selectedListing?.productType ?? GasProductType.refill)} (${_selectedListing?.size})',\n"
    "                  'KES ${_gasPrice.toStringAsFixed(0)}'),\n"
    "              _feeRow('Extra fees', 'KES 0'),\n"
    "              const Divider(height: 20, color: Colors.white24),\n"
    "              _feeRow('Total to pay vendor',\n"
    "                  'KES ${_gasPrice.toStringAsFixed(0)}',\n"
    "                  isBold: true, valueColor: AppColors.orange),",
    "              _feeRow(\n"
    "                  '${_shortTypeLabel(_selectedListing?.productType ?? GasProductType.refill)} (${_selectedListing?.size})',\n"
    "                  Currency.formatFor(_vendorCountry, _gasPrice)),\n"
    "              _feeRow('Extra fees', Currency.formatFor(_vendorCountry, 0)),\n"
    "              const Divider(height: 20, color: Colors.white24),\n"
    "              _feeRow('Total to pay vendor',\n"
    "                  Currency.formatFor(_vendorCountry, _gasPrice),\n"
    "                  isBold: true, valueColor: AppColors.orange),",
    "order_screen: cash info step fee rows")

replace_once(F2,
    "                    _summaryRow('Pay vendor on delivery',\n"
    "                        'KES ${_gasPrice.toStringAsFixed(0)}',\n"
    "                        isBold: true, valueColor: AppColors.orange),",
    "                    _summaryRow('Pay vendor on delivery',\n"
    "                        Currency.formatFor(_vendorCountry, _gasPrice),\n"
    "                        isBold: true, valueColor: AppColors.orange),",
    "order_screen: summary step pay-vendor row")

replace_once(F2,
    "          text:\n"
    "              'Have KES ${_gasPrice.toStringAsFixed(0)} ready (cash or M-Pesa to the vendor). Only share your delivery PIN after you receive and pay for your gas.',",
    "          text:\n"
    "              'Have ${Currency.formatFor(_vendorCountry, _gasPrice)} ready (cash or M-Pesa to the vendor). Only share your delivery PIN after you receive and pay for your gas.',",
    "order_screen: summary info card")

replace_once(F2,
    "              '${_selectedListing?.size} $typeLabel · KES ${_gasPrice.toStringAsFixed(0)} cash on delivery',",
    "              '${_selectedListing?.size} $typeLabel · ${Currency.formatFor(_vendorCountry, _gasPrice)} cash on delivery',",
    "order_screen: confirm sheet subtitle")

# ══════════════════ vendor_order_screen.dart ══════════════════
F3 = "lib/features/vendor/screens/vendor_order_screen.dart"

replace_once(F3,
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/features/shared/order_chat_screen.dart';",
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';\n"
    "import 'package:mobigas/features/shared/order_chat_screen.dart';",
    "vendor_order_screen: import currency.dart")

replace_once(F3,
    "  String get _amount => widget.order.listing.price.toStringAsFixed(0);",
    "  // Already includes the currency symbol for the order's country —\n"
    "  // every use site below just interpolates $_amount directly.\n"
    "  String get _amount =>\n"
    "      Currency.formatFor(widget.order.country, widget.order.listing.price);",
    "vendor_order_screen: _amount getter uses Currency.formatFor")

replace_once(F3,
    "      ..write(\n"
    "          'Payment: customer pays KES $_amount (cash or M-Pesa to the vendor). Confirm payment is received before taking the PIN.');",
    "      ..write(\n"
    "          'Payment: customer pays $_amount (cash or M-Pesa to the vendor). Confirm payment is received before taking the PIN.');",
    "vendor_order_screen: rider message body")

replace_once(F3,
    "            child: Text(\n"
    "              'KES $_amount \U0001F4B5',\n"
    "              style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                    color: AppColors.orange,\n"
    "                    fontWeight: FontWeight.w700,\n"
    "                  ),\n"
    "            ),",
    "            child: Text(\n"
    "              '$_amount \U0001F4B5',\n"
    "              style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                    color: AppColors.orange,\n"
    "                    fontWeight: FontWeight.w700,\n"
    "                  ),\n"
    "            ),",
    "vendor_order_screen: header amount badge")

replace_once(F3,
    "          _row(Icons.payments_rounded, 'You receive',\n"
    "              'KES $_amount from customer on delivery'),",
    "          _row(Icons.payments_rounded, 'You receive',\n"
    "              '$_amount from customer on delivery'),",
    "vendor_order_screen: prepare step you-receive row")

replace_once(F3,
    "        _infoBox(Icons.payments_rounded,\n"
    "            'Confirm payment of KES $_amount is received (cash or M-Pesa to you) before the customer shares the PIN — the PIN completes the delivery.'),",
    "        _infoBox(Icons.payments_rounded,\n"
    "            'Confirm payment of $_amount is received (cash or M-Pesa to you) before the customer shares the PIN — the PIN completes the delivery.'),",
    "vendor_order_screen: prepare step info box")

replace_once(F3,
    "          _row(Icons.payments_rounded, 'Payment',\n"
    "              'KES $_amount — confirm received before PIN'),",
    "          _row(Icons.payments_rounded, 'Payment',\n"
    "              '$_amount — confirm received before PIN'),",
    "vendor_order_screen: en-route payment row")

replace_once(F3,
    "        _infoBox(Icons.payments_rounded,\n"
    "            'Confirm payment of KES $_amount is received (cash or M-Pesa to you) FIRST — the customer\\'s PIN completes the delivery.'),",
    "        _infoBox(Icons.payments_rounded,\n"
    "            'Confirm payment of $_amount is received (cash or M-Pesa to you) FIRST — the customer\\'s PIN completes the delivery.'),",
    "vendor_order_screen: arrived step info box")

replace_once(F3,
    "          _row(Icons.payments_rounded, 'You collected',\n"
    "              'KES $_amount from customer'),",
    "          _row(Icons.payments_rounded, 'You collected',\n"
    "              '$_amount from customer'),",
    "vendor_order_screen: arrived step collected row")

replace_once(F3,
    "                  Text(\n"
    "                    'KES $_amount',\n"
    "                    style: Theme.of(context)\n"
    "                        .textTheme\n"
    "                        .titleLarge\n"
    "                        ?.copyWith(\n"
    "                          color: AppColors.success,\n"
    "                          fontWeight: FontWeight.w800,\n"
    "                          fontSize: 24,\n"
    "                        ),\n"
    "                  ),",
    "                  Text(\n"
    "                    _amount,\n"
    "                    style: Theme.of(context)\n"
    "                        .textTheme\n"
    "                        .titleLarge\n"
    "                        ?.copyWith(\n"
    "                          color: AppColors.success,\n"
    "                          fontWeight: FontWeight.w800,\n"
    "                          fontSize: 24,\n"
    "                        ),\n"
    "                  ),",
    "vendor_order_screen: confirmed step amount")

print("\nAll edits applied successfully.")
