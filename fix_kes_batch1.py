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

# ══════════════════ vendor_fees_banner.dart ══════════════════
F1 = "lib/core/widgets/vendor_fees_banner.dart"

replace_once(F1,
    "import 'package:mobigas/core/theme/app_theme.dart';\n"
    "import 'package:mobigas/core/models/app_models.dart';",
    "import 'package:mobigas/core/theme/app_theme.dart';\n"
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';",
    "vendor_fees_banner: import currency.dart")

replace_once(F1,
    "        final data = snap.data!.data() as Map<String, dynamic>;\n"
    "        final feesOwed = (data['feesOwed'] ?? 0.0).toDouble();\n"
    "        final isSuspended = data['isSuspended'] ?? false;",
    "        final data = snap.data!.data() as Map<String, dynamic>;\n"
    "        final feesOwed = (data['feesOwed'] ?? 0.0).toDouble();\n"
    "        final country = (data['country'] as String?) ?? 'KE';\n"
    "        final isSuspended = data['isSuspended'] ?? false;",
    "vendor_fees_banner: read country from stream")

replace_once(F1,
    "                      Text(\n"
    "                        locked\n"
    "                            ? 'Orders paused — platform fees due'\n"
    "                            : 'Platform fees: KES ${feesOwed.toStringAsFixed(0)} owed',",
    "                      Text(\n"
    "                        locked\n"
    "                            ? 'Orders paused — platform fees due'\n"
    "                            : 'Platform fees: ${Currency.formatFor(country, feesOwed)} owed',",
    "vendor_fees_banner: banner title")

replace_once(F1,
    "                      Text(\n"
    "                        locked\n"
    "                            ? 'Pay KES ${feesOwed.toStringAsFixed(0)} now to resume receiving orders. Tap for payment details.'\n"
    "                            : 'Customer-finder fee (1%) on your cash orders. Orders pause automatically at KES ${MobiGasFees.vendorFeeLockThreshold.toStringAsFixed(0)} — tap to pay now.',",
    "                      Text(\n"
    "                        locked\n"
    "                            ? 'Pay ${Currency.formatFor(country, feesOwed)} now to resume receiving orders. Tap for payment details.'\n"
    "                            : 'Customer-finder fee (1%) on your cash orders. Orders pause automatically at ${Currency.formatFor(country, MobiGasFees.vendorFeeLockThreshold)} — tap to pay now.',",
    "vendor_fees_banner: banner body")

replace_once(F1,
    "            builder: (_) => _FeeSheet(\n"
    "              feesOwed: feesOwed,\n"
    "              locked: locked,\n"
    "              vendorPhone: (data['phone'] ?? '').toString(),\n"
    "            ),",
    "            builder: (_) => _FeeSheet(\n"
    "              feesOwed: feesOwed,\n"
    "              locked: locked,\n"
    "              country: country,\n"
    "              vendorPhone: (data['phone'] ?? '').toString(),\n"
    "            ),",
    "vendor_fees_banner: pass country to _FeeSheet")

replace_once(F1,
    "class _FeeSheet extends StatefulWidget {\n"
    "  final double feesOwed;\n"
    "  final bool locked;\n"
    "  final String vendorPhone;\n"
    "\n"
    "  const _FeeSheet({\n"
    "    required this.feesOwed,\n"
    "    required this.locked,\n"
    "    required this.vendorPhone,\n"
    "  });",
    "class _FeeSheet extends StatefulWidget {\n"
    "  final double feesOwed;\n"
    "  final bool locked;\n"
    "  final String country;\n"
    "  final String vendorPhone;\n"
    "\n"
    "  const _FeeSheet({\n"
    "    required this.feesOwed,\n"
    "    required this.locked,\n"
    "    required this.country,\n"
    "    required this.vendorPhone,\n"
    "  });",
    "vendor_fees_banner: _FeeSheet field: country")

replace_once(F1,
    "                  Text(isSuccess ? 'Amount paid' : 'Amount owed',\n"
    "                      style: Theme.of(context)\n"
    "                          .textTheme\n"
    "                          .bodySmall\n"
    "                          ?.copyWith(color: AppColors.gray400)),\n"
    "                  Text('KES ${feesOwed.toStringAsFixed(0)}',",
    "                  Text(isSuccess ? 'Amount paid' : 'Amount owed',\n"
    "                      style: Theme.of(context)\n"
    "                          .textTheme\n"
    "                          .bodySmall\n"
    "                          ?.copyWith(color: AppColors.gray400)),\n"
    "                  Text(Currency.formatFor(widget.country, feesOwed),",
    "vendor_fees_banner: sheet amount owed")

replace_once(F1,
    "                            : 'Pay KES ${feesOwed.toStringAsFixed(0)} now'),",
    "                            : 'Pay ${Currency.formatFor(widget.country, feesOwed)} now'),",
    "vendor_fees_banner: pay button label")

replace_once(F1,
    "                'If unpaid fees reach KES ${MobiGasFees.vendorFeeLockThreshold.toStringAsFixed(0)}, '",
    "                'If unpaid fees reach ${Currency.formatFor(widget.country, MobiGasFees.vendorFeeLockThreshold)}, '",
    "vendor_fees_banner: threshold explainer")

replace_once(F1,
    "                        _payLine(context,\n"
    "                            '4. Amount: KES ${feesOwed.toStringAsFixed(0)}'),",
    "                        _payLine(context,\n"
    "                            '4. Amount: ${Currency.formatFor(widget.country, feesOwed)}'),",
    "vendor_fees_banner: paybill instructions amount")

# ══════════════════ vendor_statistics_screen.dart ══════════════════
F2 = "lib/features/vendor/screens/vendor_statistics_screen.dart"

replace_once(F2,
    "import 'package:mobigas/core/theme/app_theme.dart';\n"
    "\n"
    "/// Detailed sales & fulfillment statistics for a vendor, with a",
    "import 'package:mobigas/core/theme/app_theme.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';\n"
    "\n"
    "/// Detailed sales & fulfillment statistics for a vendor, with a",
    "vendor_statistics_screen: import currency.dart")

replace_once(F2,
    "    final cards = [\n"
    "      ('Total sales', 'KES ${totalSales.toStringAsFixed(0)}',\n"
    "          Icons.account_balance_wallet_rounded, AppColors.success),",
    "    final country = (widget.vendorData['country'] as String?) ?? 'KE';\n"
    "    final cards = [\n"
    "      ('Total sales', Currency.formatFor(country, totalSales),\n"
    "          Icons.account_balance_wallet_rounded, AppColors.success),",
    "vendor_statistics_screen: summary grid total sales")

replace_once(F2,
    "                        child: Text(\n"
    "                            'KES ${m.totalSales.toStringAsFixed(0)}',\n"
    "                            textAlign: TextAlign.end,",
    "                        child: Text(\n"
    "                            Currency.formatFor(\n"
    "                                (widget.vendorData['country'] as String?) ?? 'KE',\n"
    "                                m.totalSales),\n"
    "                            textAlign: TextAlign.end,",
    "vendor_statistics_screen: monthly table sales column")

replace_once(F2,
    "                _pdfRow('Total sales (all time)',\n"
    "                    'KES ${totalSales.toStringAsFixed(0)}', bold: true),",
    "                _pdfRow('Total sales (all time)',\n"
    "                    Currency.formatFor(\n"
    "                        (widget.vendorData['country'] as String?) ?? 'KE',\n"
    "                        totalSales),\n"
    "                    bold: true),",
    "vendor_statistics_screen: PDF total sales row")

# ══════════════════ vendor_home_screen.dart ══════════════════
F3 = "lib/features/vendor/screens/vendor_home_screen.dart"

replace_once(F3,
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/features/vendor/screens/vendor_edit_profile_screen.dart';",
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';\n"
    "import 'package:mobigas/features/vendor/screens/vendor_edit_profile_screen.dart';",
    "vendor_home_screen: import currency.dart")

replace_once(F3,
    "  String _money(double? v) =>\n"
    "      v == null ? '—' : 'KES ${v.toStringAsFixed(0)}';",
    "  String _money(double? v) => v == null\n"
    "      ? '—'\n"
    "      : Currency.formatFor((_vendorData?['country'] as String?) ?? 'KE', v);",
    "vendor_home_screen: _money() uses vendor's own country")

replace_once(F3,
    "                    Column(\n"
    "                      crossAxisAlignment: CrossAxisAlignment.end,\n"
    "                      children: [\n"
    "                        Text(\n"
    "                          'KES ${order.listing.price.toStringAsFixed(0)}',\n"
    "                          style:\n"
    "                              Theme.of(context).textTheme.titleLarge?.copyWith(",
    "                    Column(\n"
    "                      crossAxisAlignment: CrossAxisAlignment.end,\n"
    "                      children: [\n"
    "                        Text(\n"
    "                          Currency.formatFor(order.country, order.listing.price),\n"
    "                          style:\n"
    "                              Theme.of(context).textTheme.titleLarge?.copyWith(",
    "vendor_home_screen: incoming order card price")

replace_once(F3,
    "                    'Collect KES ${order.listing.price.toStringAsFixed(0)} from the customer on delivery (cash or M-Pesa to you).',",
    "                    'Collect ${Currency.formatFor(order.country, order.listing.price)} from the customer on delivery (cash or M-Pesa to you).',",
    "vendor_home_screen: collect-on-delivery note")

replace_once(F3,
    "          Text('KES ${order.listing.price.toStringAsFixed(0)}',\n"
    "              style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                    fontSize: 14,\n"
    "                    color: AppColors.success,\n"
    "                    fontWeight: FontWeight.w700,\n"
    "                  )),",
    "          Text(Currency.formatFor(order.country, order.listing.price),\n"
    "              style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                    fontSize: 14,\n"
    "                    color: AppColors.success,\n"
    "                    fontWeight: FontWeight.w700,\n"
    "                  )),",
    "vendor_home_screen: completed order tile price")

# ══════════════════ home_screen.dart (customer) ══════════════════
F4 = "lib/features/customer/screens/home_screen.dart"

replace_once(F4,
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/widgets/double_back_to_exit.dart';",
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';\n"
    "import 'package:mobigas/core/widgets/double_back_to_exit.dart';",
    "home_screen(customer): import currency.dart")

replace_once(F4,
    "                  if (cheapestRefill != null)\n"
    "                    chip(\n"
    "                        '${cheapestRefill.size} refill from KES ${cheapestRefill.price.toStringAsFixed(0)}'),",
    "                  if (cheapestRefill != null)\n"
    "                    chip(\n"
    "                        '${cheapestRefill.size} refill from ${Currency.formatFor(vendor.country, cheapestRefill.price)}'),",
    "home_screen(customer): vendor card cheapest refill chip")

replace_once(F4,
    "              Text('KES ${order.customerTotal.toStringAsFixed(0)}',\n"
    "                  style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                      fontSize: 14,\n"
    "                      color: order.status == OrderStatus.cancelled\n"
    "                          ? AppColors.gray400\n"
    "                          : AppColors.navy,\n"
    "                      fontWeight: FontWeight.w700)),",
    "              Text(Currency.formatFor(order.country, order.customerTotal),\n"
    "                  style: Theme.of(context).textTheme.titleMedium?.copyWith(\n"
    "                      fontSize: 14,\n"
    "                      color: order.status == OrderStatus.cancelled\n"
    "                          ? AppColors.gray400\n"
    "                          : AppColors.navy,\n"
    "                      fontWeight: FontWeight.w700)),",
    "home_screen(customer): order tile total")

# ══════════════════ refer_earn_screen.dart ══════════════════
F5 = "lib/features/shared/refer_earn_screen.dart"

replace_once(F5,
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/services/firestore_service.dart';",
    "import 'package:cloud_firestore/cloud_firestore.dart';\n"
    "import 'package:mobigas/core/models/app_models.dart';\n"
    "import 'package:mobigas/core/services/firestore_service.dart';\n"
    "import 'package:mobigas/core/config/currency.dart';",
    "refer_earn_screen: imports")

replace_once(F5,
    "class _ReferEarnScreenState extends State<ReferEarnScreen> {\n"
    "  String? _code;\n"
    "  bool _isLoadingCode = true;\n"
    "  double _customerRate = 0;\n"
    "  double _vendorRate = 0;",
    "class _ReferEarnScreenState extends State<ReferEarnScreen> {\n"
    "  String? _code;\n"
    "  bool _isLoadingCode = true;\n"
    "  double _customerRate = 0;\n"
    "  double _vendorRate = 0;\n"
    "  // Only vendors carry a country today (set at onboarding from GPS).\n"
    "  // Customers don't yet — defaults to KE until that's added.\n"
    "  String _ownerCountry = 'KE';",
    "refer_earn_screen: add _ownerCountry field")

replace_once(F5,
    "  void initState() {\n"
    "    super.initState();\n"
    "    _loadCode();\n"
    "    _loadRates();\n"
    "    _loadPayoutPreferences();\n"
    "  }",
    "  void initState() {\n"
    "    super.initState();\n"
    "    _loadCode();\n"
    "    _loadRates();\n"
    "    _loadPayoutPreferences();\n"
    "    _loadOwnerCountry();\n"
    "  }\n"
    "\n"
    "  Future<void> _loadOwnerCountry() async {\n"
    "    if (widget.ownerType != 'vendor') return;\n"
    "    try {\n"
    "      final doc = await FirebaseFirestore.instance\n"
    "          .collection('vendors')\n"
    "          .doc(widget.ownerId)\n"
    "          .get();\n"
    "      if (mounted && doc.exists) {\n"
    "        setState(() {\n"
    "          _ownerCountry = (doc.data()?['country'] as String?) ?? 'KE';\n"
    "        });\n"
    "      }\n"
    "    } catch (_) {\n"
    "      // Keep the KE default rather than block the referral screen.\n"
    "    }\n"
    "  }",
    "refer_earn_screen: add _loadOwnerCountry()")

replace_once(F5,
    "                            _statCard(\n"
    "                                'Total earned',\n"
    "                                'KES ${totalEarned.toStringAsFixed(0)}',\n"
    "                                AppColors.success),\n"
    "                            const SizedBox(width: 12),\n"
    "                            _statCard(\n"
    "                                'Pending payout',\n"
    "                                'KES ${pendingPayout.toStringAsFixed(0)}',\n"
    "                                AppColors.orange),\n"
    "                            const SizedBox(width: 12),\n"
    "                            _statCard(\n"
    "                                'Paid out',\n"
    "                                'KES ${totalPaid.toStringAsFixed(0)}',\n"
    "                                AppColors.navy),",
    "                            _statCard(\n"
    "                                'Total earned',\n"
    "                                Currency.formatFor(_ownerCountry, totalEarned),\n"
    "                                AppColors.success),\n"
    "                            const SizedBox(width: 12),\n"
    "                            _statCard(\n"
    "                                'Pending payout',\n"
    "                                Currency.formatFor(_ownerCountry, pendingPayout),\n"
    "                                AppColors.orange),\n"
    "                            const SizedBox(width: 12),\n"
    "                            _statCard(\n"
    "                                'Paid out',\n"
    "                                Currency.formatFor(_ownerCountry, totalPaid),\n"
    "                                AppColors.navy),",
    "refer_earn_screen: stat cards")

replace_once(F5,
    "            Text('KES ${rewardEach.toStringAsFixed(0)} each',",
    "            Text('${Currency.formatFor(_ownerCountry, rewardEach)} each',",
    "refer_earn_screen: reward-each label")

print("\nAll edits applied successfully.")
