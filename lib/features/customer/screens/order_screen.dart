import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/providers/vendor_provider.dart';
import 'package:mobigas/core/models/app_models.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  int _currentStep = 0; // 0=pay+product+size+vendor, 1=payment info, 2=summary

  PaymentMethod? _method;
  GasProductType? _selectedType;
  String? _selectedSize;
  VendorModel? _selectedVendor;
  GasListing? _selectedListing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Vendors are already loaded on the home screen — only fetch
      // if the list is empty, so this screen opens instantly.
      final vendorProvider = context.read<VendorProvider>();
      if (vendorProvider.vendors.isEmpty && !vendorProvider.isLoading) {
        final auth = context.read<AuthProvider>();
        vendorProvider.loadVendors(
          lat: auth.customer?.latitude,
          lng: auth.customer?.longitude,
        );
      }
    });
  }

  bool get _isCash => _method == PaymentMethod.cash;
  bool get _isRefill => _selectedType == GasProductType.refill;

  void _selectMethod(PaymentMethod m) {
    setState(() {
      _method = m;
      // Vendor affordability changes with method — reselect vendor.
      _selectedVendor = null;
      _selectedListing = null;
    });
  }

  void _selectType(GasProductType type) {
    setState(() {
      _selectedType = type;
      _selectedSize = null;
      _selectedVendor = null;
      _selectedListing = null;
    });
  }

  void _selectSize(String size) {
    setState(() {
      _selectedSize = size;
      _selectedVendor = null;
      _selectedListing = null;
    });
  }

  void _selectOffer(VendorModel vendor, GasListing listing) {
    setState(() {
      _selectedVendor = vendor;
      _selectedListing = listing;
    });
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_method == null) {
        _showError('Please choose how you will pay');
        return;
      }
      if (_selectedType == null) {
        _showError('Please choose what you want to order');
        return;
      }
      if (_selectedSize == null) {
        _showError('Please choose a gas size');
        return;
      }
      if (_selectedVendor == null || _selectedListing == null) {
        _showError('Please choose a vendor');
        return;
      }
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _showConfirmSheet();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<void> _placeOrder() async {
    final auth = context.read<AuthProvider>();
    final orders = context.read<OrderProvider>();
    final customer = auth.customer;

    if (customer == null ||
        _selectedVendor == null ||
        _selectedListing == null ||
        _method == null) {
      return;
    }

    Navigator.pop(context); // close sheet

    await orders.placeOrder(
      customer: customer,
      vendor: _selectedVendor!,
      listing: _selectedListing!,
      paymentMethod: _method!,
    );

    if (!mounted) return;
    if (orders.error != null) {
      _showError(orders.error!);
      return;
    }
    context.pushReplacement('/order-tracking');
  }

  void _showConfirmSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildConfirmSheet(),
    );
  }

  double get _gasPrice => _selectedListing?.price ?? 0;
  double get _bankInterest =>
      _isCash ? 0 : _gasPrice * MobiGasFees.bankInterestRate;
  double get _customerTotal => _gasPrice + _bankInterest;

  String _typeDescription(GasProductType t) {
    switch (t) {
      case GasProductType.refill:
        return 'Gas only — the vendor collects your empty cylinder when they deliver';
      case GasProductType.fullKit:
        return 'New cylinder + gas — no empty cylinder needed';
      case GasProductType.grillKit:
        return '6kg gas + cylinder + stove + grill — complete starter package';
    }
  }

  IconData _typeIcon(GasProductType t) {
    switch (t) {
      case GasProductType.refill:
        return Icons.autorenew_rounded;
      case GasProductType.fullKit:
        return Icons.propane_tank_outlined;
      case GasProductType.grillKit:
        return Icons.outdoor_grill_rounded;
    }
  }

  String _shortTypeLabel(GasProductType t) {
    switch (t) {
      case GasProductType.refill:
        return 'Refill';
      case GasProductType.fullKit:
        return 'Gas + cylinder';
      case GasProductType.grillKit:
        return 'Gas + cylinder + grill';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Default payment method once customer is known:
    // approved customers default to credit, others to cash.
    final customer = context.watch<AuthProvider>().customer;
    _method ??= (customer?.isBankApproved ?? false)
        ? PaymentMethod.credit
        : PaymentMethod.cash;

    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (_currentStep == 0) _buildProductStep(),
                    if (_currentStep == 1)
                      _isCash ? _buildCashInfoStep() : _buildRepaymentStep(),
                    if (_currentStep == 2) _buildSummaryStep(),
                    const SizedBox(height: 24),
                    _buildNextButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titles = ['Order gas', 'Payment info', 'Order summary'];
    final subtitles = [
      'Pick payment, product, size, vendor',
      _isCash ? 'Pay the vendor on delivery' : 'Pay within 30 days via M-Pesa',
      'Review before confirming',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              if (_currentStep > 0) {
                setState(() => _currentStep--);
              } else {
                context.pop();
              }
            },
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titles[_currentStep],
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.white,
                          fontSize: 18,
                        )),
                Text(subtitles[_currentStep],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                        )),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${_currentStep + 1}/3',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w700,
                    )),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(3, (i) {
          final isDone = i < _currentStep;
          final isActive = i == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDone || isActive
                          ? AppColors.orange
                          : AppColors.gray200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── STEP 1: PAYMENT → PRODUCT → SIZE → VENDOR ─────────────────────
  Widget _buildProductStep() {
    final customer = context.watch<AuthProvider>().customer;
    final vendorProvider = context.watch<VendorProvider>();
    final vendors = vendorProvider.vendors
        .where((v) => v.isOnline && v.isVerified && v.canReceiveOrders)
        .toList();

    // Product types actually offered by available vendors
    final offeredTypes = <GasProductType>{
      for (final v in vendors)
        for (final l in v.listings)
          if (l.available) l.productType,
    };

    // Sizes available for the selected type (sorted by kg)
    final sizeKg = <String, int>{};
    if (_selectedType != null) {
      for (final v in vendors) {
        for (final l in v.listings) {
          if (l.available && l.productType == _selectedType) {
            sizeKg[l.size] = l.kg;
          }
        }
      }
    }
    final sizes = sizeKg.keys.toList()
      ..sort((a, b) => sizeKg[a]!.compareTo(sizeKg[b]!));

    // Vendor offers for type + size, cheapest first
    final offers = <(VendorModel, GasListing)>[];
    if (_selectedType != null && _selectedSize != null) {
      for (final v in vendors) {
        for (final l in v.listings) {
          if (l.available &&
              l.productType == _selectedType &&
              l.size == _selectedSize) {
            offers.add((v, l));
          }
        }
      }
      offers.sort((a, b) => a.$2.price.compareTo(b.$2.price));
    }

    final creditApproved = customer?.isBankApproved ?? false;
    // Credit is only offered when it can actually buy something — if
    // every available listing costs more than the customer's remaining
    // credit, this order is cash and we say so instead of showing a
    // useless credit option.
    final creditUsable = creditApproved &&
        vendors.any((v) => v.listings
            .any((l) => l.available && customer!.canAfford(l)));
    if (!creditUsable && _method == PaymentMethod.credit) {
      _method = PaymentMethod.cash;
    }
    // Section numbers shift when the payment chooser is hidden.
    final n2 = creditUsable ? 2 : 1;
    final n3 = creditUsable ? 3 : 2;
    final n4 = creditUsable ? 4 : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (creditUsable) ...[
          // Customer has a real choice — show it.
          _sectionTitle('1. How will you pay?'),
          const SizedBox(height: 10),
          _paymentMethodCards(customer),
          if (!_isCash && customer != null) ...[
            const SizedBox(height: 12),
            _buildCreditCard(customer),
          ],
        ] else if (creditApproved && vendors.isNotEmpty) ...[
          // Has credit, but it can't afford anything on offer.
          _infoCard(
            icon: Icons.payments_outlined,
            text:
                'Your available credit (KES ${customer!.bankCreditAvailable.toStringAsFixed(0)}) is below current gas prices, so this order is cash on delivery. Repay via M-Pesa to free up your credit.',
          ),
        ] else ...[
          // No credit limit — cash is simply how it works.
          _infoCard(
            icon: Icons.payments_outlined,
            text:
                'You\'ll pay cash on delivery — directly to the vendor when your gas arrives.',
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => context.push('/credit-application'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.credit_score_rounded,
                      color: AppColors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text('Want to pay later? Apply for a credit limit →',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                ],
              ),
            ),
          ),
        ],

        // Loading / empty
        if (vendorProvider.isLoading) ...[
          const SizedBox(height: 24),
          const Center(
              child: CircularProgressIndicator(color: AppColors.orange)),
        ],
        if (!vendorProvider.isLoading && vendors.isEmpty) ...[
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.gray200),
            ),
            child: Column(
              children: [
                const Icon(Icons.store_outlined,
                    size: 48, color: AppColors.gray400),
                const SizedBox(height: 12),
                Text('No vendors available near you',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.gray600,
                        )),
                const SizedBox(height: 4),
                Text('Check back soon — more vendors are joining',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                        )),
              ],
            ),
          ),
        ],

        if (vendors.isNotEmpty) ...[
          // PRODUCT TYPE
          const SizedBox(height: 20),
          _sectionTitle('$n2. What do you need?'),
          const SizedBox(height: 10),
          ...GasProductType.values
              .where((t) => offeredTypes.contains(t))
              .map((t) => _typeCard(t)),

          // SIZE
          if (_selectedType != null) ...[
            const SizedBox(height: 20),
            _sectionTitle('$n3. Choose size'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: sizes.map((s) => _sizeChip(s)).toList(),
            ),
            if (_isRefill) ...[
              const SizedBox(height: 12),
              _infoCard(
                icon: Icons.swap_horiz_rounded,
                text:
                    'Have your empty cylinder ready — the vendor collects it when they deliver.',
              ),
            ],
          ],

          // VENDOR
          if (_selectedType != null && _selectedSize != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                _sectionTitle('$n4. Choose vendor'),
                const Spacer(),
                Text('Cheapest first',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 11,
                        )),
              ],
            ),
            const SizedBox(height: 10),
            if (offers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gray200),
                ),
                child: Text(
                  'No vendor currently offers this option. Try another size or product.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.gray400),
                ),
              ),
            ...offers.asMap().entries.map((e) => _offerRow(
                  e.value.$1,
                  e.value.$2,
                  customer,
                  isCheapest: e.key == 0 && offers.length > 1,
                )),
          ],
        ],
      ],
    );
  }

  Widget _paymentMethodCards(CustomerModel? customer) {
    final creditApproved = customer?.isBankApproved ?? false;

    Widget card({
      required PaymentMethod method,
      required IconData icon,
      required String title,
      required String subtitle,
      bool enabled = true,
      VoidCallback? onDisabledTap,
    }) {
      final isSelected = _method == method && enabled;
      return Expanded(
        child: GestureDetector(
          onTap: enabled ? () => _selectMethod(method) : onDisabledTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: enabled ? AppColors.white : AppColors.gray100,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? AppColors.orange : AppColors.gray200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon,
                        size: 20,
                        color: enabled
                            ? (isSelected
                                ? AppColors.orange
                                : AppColors.navy)
                            : AppColors.gray400),
                    const Spacer(),
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color:
                          isSelected ? AppColors.orange : AppColors.gray200,
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color:
                              enabled ? AppColors.navy : AppColors.gray400,
                        )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          height: 1.3,
                          color: enabled
                              ? AppColors.gray400
                              : AppColors.gray400,
                        )),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          method: PaymentMethod.cash,
          icon: Icons.payments_outlined,
          title: 'Cash on delivery',
          subtitle: 'Pay the vendor directly when your gas arrives',
        ),
        const SizedBox(width: 10),
        card(
          method: PaymentMethod.credit,
          icon: Icons.credit_score_rounded,
          title: 'MobiGas Credit',
          subtitle: creditApproved
              ? 'KES ${customer!.bankCreditAvailable.toStringAsFixed(0)} available · repay in 30 days'
              : 'Not approved yet — tap to apply for a credit limit',
          enabled: creditApproved,
          onDisabledTap: () => context.push('/credit-application'),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ));
  }

  Widget _typeCard(GasProductType type) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () => _selectType(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.orange : AppColors.gray200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.orange
                    : AppColors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(_typeIcon(type),
                  color: isSelected ? AppColors.white : AppColors.orange,
                  size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_shortTypeLabel(type),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.navy,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 2),
                  Text(_typeDescription(type),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray400,
                            fontSize: 11,
                            height: 1.4,
                          )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: isSelected ? AppColors.orange : AppColors.gray200,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sizeChip(String size) {
    final isSelected = _selectedSize == size;
    return GestureDetector(
      onTap: () => _selectSize(size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.orange : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.orange : AppColors.gray200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          size,
          style: TextStyle(
            color: isSelected ? AppColors.white : AppColors.navy,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _offerRow(VendorModel vendor, GasListing listing,
      CustomerModel? customer,
      {bool isCheapest = false}) {
    final isSelected = _selectedVendor?.id == vendor.id &&
        _selectedListing?.size == listing.size &&
        _selectedListing?.productType == listing.productType;
    // Credit affordability only matters for credit orders —
    // cash orders can always be selected.
    final canAfford =
        _isCash ? true : (customer?.canAfford(listing) ?? false);

    return GestureDetector(
      onTap: canAfford ? () => _selectOffer(vendor, listing) : null,
      child: Opacity(
        opacity: canAfford ? 1.0 : 0.55,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? AppColors.orange : AppColors.gray200,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.orange,
                child: Text(vendor.businessName[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(vendor.businessName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontSize: 14,
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                  ),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (isCheapest && canAfford) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Best price',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.success,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    )),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${vendor.estate} · ${vendor.distance} · ★ ${vendor.rating.toStringAsFixed(1)} · ${vendor.deliveryTime}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray400,
                            fontSize: 11,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!canAfford) ...[
                      const SizedBox(height: 4),
                      Text('Above your available credit — try cash',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.error,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              )),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('KES ${listing.price.toStringAsFixed(0)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: canAfford
                                ? AppColors.orange
                                : AppColors.gray400,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          )),
                  const SizedBox(height: 4),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color:
                        isSelected ? AppColors.orange : AppColors.gray200,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditCard(CustomerModel customer) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your gas credit limit',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                        )),
                Text(
                  'KES ${customer.bankCreditAvailable.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  'Limit: KES ${customer.bankApprovedLimit?.toStringAsFixed(0) ?? "0"}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 11,
                      )),
              const SizedBox(height: 4),
              Text('Used: KES ${customer.bankCreditUsed.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 11,
                      )),
              if (customer.partnerBankName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('via ${customer.partnerBankName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        )),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── STEP 2 (CASH): PAYMENT INFO ───────────────────────────────────
  Widget _buildCashInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cash on delivery',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 16),
              _feeRow(
                  '${_shortTypeLabel(_selectedListing?.productType ?? GasProductType.refill)} (${_selectedListing?.size})',
                  'KES ${_gasPrice.toStringAsFixed(0)}'),
              _feeRow('Interest / extra fees', 'KES 0'),
              const Divider(height: 20, color: Colors.white24),
              _feeRow('Total to pay vendor',
                  'KES ${_gasPrice.toStringAsFixed(0)}',
                  isBold: true, valueColor: AppColors.orange),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text('How cash payment works',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
              const SizedBox(height: 10),
              _explainerRow(
                  'Pay the vendor when your gas is delivered — cash or M-Pesa to the vendor'),
              _explainerRow('No interest, no extra charges for you'),
              _explainerRow(
                  'Confirm delivery with your PIN only after you receive your gas'),
              _explainerRow(
                  'Want gas on credit next time? Apply for a credit limit from the home screen'),
            ],
          ),
        ),
      ],
    );
  }

  // ── STEP 2 (CREDIT): REPAYMENT INFO ───────────────────────────────
  Widget _buildRepaymentStep() {
    final customer = context.read<AuthProvider>().customer;
    final dueDate = DateTime.now().add(const Duration(days: 30));
    final dueDateStr = '${dueDate.day}/${dueDate.month}/${dueDate.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fee breakdown
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fee breakdown',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 16),
              _feeRow(
                  '${_shortTypeLabel(_selectedListing?.productType ?? GasProductType.refill)} (${_selectedListing?.size})',
                  'KES ${_gasPrice.toStringAsFixed(0)}'),
              _feeRow('Bank interest (8%)',
                  'KES ${_bankInterest.toStringAsFixed(0)}'),
              const Divider(height: 20, color: Colors.white24),
              _feeRow('Total to repay bank',
                  'KES ${_customerTotal.toStringAsFixed(0)}',
                  isBold: true, valueColor: AppColors.orange),
              if (customer?.partnerBankName.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text('Financed by ${customer!.partnerBankName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 11,
                        )),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Due date
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gray200),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      color: AppColors.orange, size: 20),
                  const SizedBox(width: 10),
                  Text('Due by',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.gray600,
                          )),
                  const Spacer(),
                  Text(dueDateStr,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
              const Divider(height: 24, color: AppColors.gray200),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      color: AppColors.orange, size: 20),
                  const SizedBox(width: 10),
                  Text('Repayment period',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.gray600,
                          )),
                  const Spacer(),
                  Text('30 days',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.tips_and_updates_outlined,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text('How repayment works',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
              const SizedBox(height: 10),
              _explainerRow('Pay any amount, any time within 30 days'),
              _explainerRow('M-Pesa paybill details shown in Repayments tab'),
              _explainerRow('Pay daily, weekly or all at once'),
              _explainerRow('On-time repayment grows your credit limit'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _feeRow(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray400,
                      fontWeight:
                          isBold ? FontWeight.w600 : FontWeight.w400,
                    ),
                overflow: TextOverflow.ellipsis),
          ),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor ?? AppColors.white,
                    fontWeight:
                        isBold ? FontWeight.w700 : FontWeight.w500,
                    fontSize: isBold ? 16 : 14,
                  )),
        ],
      ),
    );
  }

  Widget _explainerRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: AppColors.success, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Color(0xFF166534),
                      fontSize: 12,
                      height: 1.4,
                    )),
          ),
        ],
      ),
    );
  }

  // ── STEP 3: SUMMARY ───────────────────────────────────────────────
  Widget _buildSummaryStep() {
    final customer = context.read<AuthProvider>().customer;
    final dueDate = DateTime.now().add(const Duration(days: 30));
    final dueDateStr = '${dueDate.day}/${dueDate.month}/${dueDate.year}';

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gray200),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        color: AppColors.orange, size: 22),
                    const SizedBox(width: 10),
                    Text('Order summary',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppColors.white)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _summaryRow('Payment',
                        _isCash ? 'Cash on delivery' : 'MobiGas Credit'),
                    _summaryRow(
                        'Product',
                        _shortTypeLabel(_selectedListing?.productType ??
                            GasProductType.refill)),
                    _summaryRow('Gas size', _selectedListing?.size ?? ''),
                    _summaryRow('Vendor', _selectedVendor?.businessName ?? ''),
                    _summaryRow('Price',
                        'KES ${_gasPrice.toStringAsFixed(0)}'),
                    if (!_isCash)
                      _summaryRow('Bank interest (8%)',
                          'KES ${_bankInterest.toStringAsFixed(0)}'),
                    const Divider(height: 24, color: AppColors.gray200),
                    _summaryRow(
                        _isCash
                            ? 'Pay vendor on delivery'
                            : 'Total to repay',
                        'KES ${_customerTotal.toStringAsFixed(0)}',
                        isBold: true, valueColor: AppColors.orange),
                    const Divider(height: 24, color: AppColors.gray200),
                    if (!_isCash) ...[
                      _summaryRow('Due date', dueDateStr),
                      _summaryRow('Financed by',
                          customer?.partnerBankName ?? 'Partner bank'),
                    ],
                    _summaryRow('Delivery to',
                        '${customer?.estate ?? ''}, ${customer?.area ?? ''}'),
                    _summaryRow(
                        'Est. delivery', _selectedVendor?.deliveryTime ?? ''),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_isCash) ...[
          const SizedBox(height: 16),
          _infoCard(
            icon: Icons.payments_outlined,
            text:
                'Have KES ${_gasPrice.toStringAsFixed(0)} ready (cash or M-Pesa to the vendor). Only share your delivery PIN after you receive and pay for your gas.',
          ),
        ],
        if (_isRefill) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warningLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Have your empty cylinder ready',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontSize: 14,
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w600,
                              )),
                      const SizedBox(height: 4),
                      Text(
                          'The vendor collects your empty cylinder when they deliver.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Color(0xFF92400E),
                                height: 1.5,
                              )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.gray600,
                  )),
          const Spacer(),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: valueColor ?? AppColors.navy,
                      fontWeight:
                          isBold ? FontWeight.w700 : FontWeight.w500,
                      fontSize: isBold ? 16 : 14,
                    ),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ── CONFIRM SHEET ─────────────────────────────────────────────────
  Widget _buildConfirmSheet() {
    final isLoading = context.watch<OrderProvider>().isLoading;
    final typeLabel = _shortTypeLabel(
        _selectedListing?.productType ?? GasProductType.refill);

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.gray200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.local_fire_department_rounded,
              color: AppColors.orange, size: 48),
          const SizedBox(height: 16),
          Text('Confirm your order',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.navy)),
          const SizedBox(height: 8),
          Text(
              _isCash
                  ? '${_selectedListing?.size} $typeLabel · KES ${_gasPrice.toStringAsFixed(0)} cash on delivery'
                  : '${_selectedListing?.size} $typeLabel · KES ${_customerTotal.toStringAsFixed(0)} total on credit',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.gray600)),
          const SizedBox(height: 4),
          Text('from ${_selectedVendor?.businessName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w600,
                  )),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: isLoading ? null : _placeOrder,
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.white),
                  )
                : const Text('Place order'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.gray600)),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return ElevatedButton(
      onPressed: _nextStep,
      child: Text(_currentStep < 2 ? 'Continue' : 'Review & confirm'),
    );
  }

  Widget _infoCard({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orangeDeep,
                      height: 1.5,
                      fontSize: 12,
                    )),
          ),
        ],
      ),
    );
  }
}