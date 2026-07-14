#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Replace hardcoded "M-Pesa" copy in MobiGas customer/vendor screens.
# Run from mobigas repo root:  python3 fix_mpesa_labels.py

edits = [
    ("lib/features/customer/screens/onboarding_screen.dart",
     "pay cash or M-Pesa on delivery.",
     "pay cash or mobile money on delivery."),

    ("lib/features/customer/screens/login_screen.dart",
     "_infoRow('Pay cash or M-Pesa on delivery')",
     "_infoRow('Pay cash or mobile money on delivery')"),

    ("lib/features/customer/screens/home_screen.dart",
     "accessories — pay cash or M-Pesa on delivery",
     "accessories — pay cash or mobile money on delivery"),
    ("lib/features/customer/screens/home_screen.dart",
     "'Pay', 'Cash or M-Pesa'",
     "'Pay', 'Cash or mobile money'"),
    ("lib/features/customer/screens/home_screen.dart",
     "and pay cash or M-Pesa when your gas arrives.",
     "and pay cash or mobile money when your gas arrives."),

    ("lib/features/customer/screens/order_screen.dart",
     "You\\'ll pay cash or M-Pesa on delivery",
     "You\\'ll pay cash or ${MobileMoney.primaryLabelFor(_vendorCountry)} on delivery"),
    ("lib/features/customer/screens/order_screen.dart",
     "delivered — cash or M-Pesa to the vendor'",
     "delivered — cash or ${MobileMoney.primaryLabelFor(_vendorCountry)} to the vendor'"),
    ("lib/features/customer/screens/order_screen.dart",
     "_summaryRow('Payment', 'Cash / M-Pesa on delivery')",
     "_summaryRow('Payment', 'Cash / ${MobileMoney.primaryLabelFor(_vendorCountry)} on delivery')"),
    ("lib/features/customer/screens/order_screen.dart",
     "ready (cash or M-Pesa to the vendor). Only share your delivery PIN",
     "ready (cash or ${MobileMoney.primaryLabelFor(_vendorCountry)} to the vendor). Only share your delivery PIN"),

    ("lib/features/customer/screens/order_tracking_screen.dart",
     "first (cash or M-Pesa), then show this PIN",
     "first (cash or ${MobileMoney.primaryLabelFor(order.country)}), then show this PIN"),

    ("lib/features/vendor/screens/vendor_order_screen.dart",
     "customer pays $_amount (cash or M-Pesa to the vendor)",
     "customer pays $_amount (cash or mobile money to the vendor)"),
    ("lib/features/vendor/screens/vendor_order_screen.dart",
     "(cash or M-Pesa to you) before the customer shares the PIN",
     "(cash or mobile money to you) before the customer shares the PIN"),
    ("lib/features/vendor/screens/vendor_order_screen.dart",
     "(cash or M-Pesa to you) FIRST",
     "(cash or mobile money to you) FIRST"),

    ("lib/features/vendor/screens/vendor_login_screen.dart",
     "every delivery — cash or M-Pesa, direct to you",
     "every delivery — cash or mobile money, direct to you"),

    ("lib/features/vendor/screens/vendor_home_screen.dart",
     "on delivery (cash or M-Pesa to you).",
     "on delivery (cash or ${MobileMoney.primaryLabelFor(order.country)} to you)."),
    ("lib/features/vendor/screens/vendor_home_screen.dart",
     "'Customer pays you directly on delivery — cash or M-Pesa'",
     "'Customer pays you directly on delivery — cash or mobile money'"),
    ("lib/features/vendor/screens/vendor_home_screen.dart",
     "'Your M-Pesa', _vendorData?['phone']",
     "'Your ${MobileMoney.primaryLabelFor(_vendorData?[\"country\"])}', _vendorData?['phone']"),
    ("lib/features/vendor/screens/vendor_home_screen.dart",
     "_profileTile(Icons.phone_outlined, 'M-Pesa number'",
     "_profileTile(Icons.phone_outlined, '${MobileMoney.primaryLabelFor(_vendorData?[\"country\"])} number'"),

    ("lib/features/vendor/screens/vendor_edit_profile_screen.dart",
     "_buildField('M-Pesa number', _phoneController",
     "_buildField('Mobile money number', _phoneController"),
]

# Files that use MobileMoney.primaryLabelFor(...) need the import.
imports = {
    "lib/features/customer/screens/order_screen.dart":
        "import '../../../core/config/mobile_money.dart';",
    "lib/features/customer/screens/order_tracking_screen.dart":
        "import '../../../core/config/mobile_money.dart';",
    "lib/features/vendor/screens/vendor_home_screen.dart":
        "import '../../../core/config/mobile_money.dart';",
}

for path, old, new in edits:
    with open(path, encoding="utf-8") as f:
        t = f.read()
    if old not in t:
        print("MISS", path, "->", old[:45])
        continue
    with open(path, "w", encoding="utf-8") as f:
        f.write(t.replace(old, new, 1))
    print("ok  ", path)

for path, imp in imports.items():
    with open(path, encoding="utf-8") as f:
        t = f.read()
    if "mobile_money.dart" in t:
        continue
    lines = t.split("\n")
    for i, l in enumerate(lines):
        if l.startswith("import "):
            lines.insert(i + 1, imp)
            break
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("import added", path)

print("\nDone. Now run:  flutter analyze")
