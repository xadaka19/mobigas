import 'package:flutter/material.dart';
import '../../../core/config/mobile_money.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/providers/vendor_provider.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/config/pezesha_config.dart';
import 'package:mobigas/features/bnpl/customer_bnpl.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  int _currentStep = 0; // 0=product+size+vendor, 1=payment info, 2=summary

  GasProductType? _selectedType;
  String? _selectedSize;
  String? _selectedBrand;
  VendorModel? _selectedVendor;
  GasListing? _selectedListing;

  /// The customer has ticked this vendor's flexible-payment option.
  /// Off by default and reset by every selection change below — an
  /// arrangement is with a SPECIFIC vendor on SPECIFIC terms, so it
  /// cannot survive switching vendor, size, brand or product.
  bool _usePartialPayment = false;

  /// The split FROZEN at the moment the customer ticked the box.
  ///
  /// partialPaymentSplitFor() derives its due date from DateTime.now(),
  /// so calling it again on the next rebuild yields a slightly later
  /// date. Capturing it once means the figures stored on the order are
  /// exactly the figures the customer was looking at when they agreed
  /// to them, rather than whatever the arithmetic happened to produce
  /// milliseconds before the write. Null while un-ticked, and null even
  /// when ticked if the vendor publishes free-text terms rather than a
  /// preset — there is nothing to compute in that case, and
  /// partialPaymentNote carries the whole arrangement instead.
  PartialPaymentSplit? _agreedSplit;

  // BNPL: generate the order id up front so the SAME id is attached
  // to the Pezesha loan at apply time and to the order at create
  // time — the loan's orderId must match the order that ends up
  // carrying its loanId. Lazily created, reused for whichever
  // payment path the customer takes.
  String? _pendingOrderId;
  String get _orderId =>
      _pendingOrderId ??= 'MG-${DateTime.now().millisecondsSinceEpoch}';

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

  bool get _isRefill => _selectedType == GasProductType.refill;

  /// Clears any flexible-payment opt-in. Called from every selection
  /// change — see _usePartialPayment's comment.
  void _clearPartialPayment() {
    _usePartialPayment = false;
    _agreedSplit = null;
  }

  void _selectType(GasProductType type) {
    setState(() {
      _selectedType = type;
      _selectedSize = null;
      _selectedBrand = null;
      _selectedVendor = null;
      _selectedListing = null;
      _clearPartialPayment();
    });
  }

  void _selectSize(String size) {
    setState(() {
      _selectedSize = size;
      _selectedBrand = null;
      _selectedVendor = null;
      _selectedListing = null;
      _clearPartialPayment();
    });
  }

  void _selectBrand(String brand) {
    setState(() {
      _selectedBrand = brand;
      _selectedVendor = null;
      _selectedListing = null;
      _clearPartialPayment();
    });
  }

  void _selectOffer(VendorModel vendor, GasListing listing) {
    setState(() {
      _selectedVendor = vendor;
      _selectedListing = listing;
      _clearPartialPayment();
    });
  }

  /// Ticking the flexible-payment box. Captures the split as shown at
  /// this instant (see _agreedSplit) so what gets stored on the order
  /// is what the customer actually read.
  void _setPartialPayment(bool on, VendorModel vendor) {
    setState(() {
      _usePartialPayment = on;
      _agreedSplit = on ? vendor.partialPaymentSplitFor(_orderTotal) : null;
    });
  }

  void _nextStep() {
    if (_currentStep == 0) {
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
        _selectedListing == null) {
      return;
    }

    Navigator.pop(context); // close sheet

    await orders.placeOrder(
      customer: customer,
      vendor: _selectedVendor!,
      listing: _selectedListing!,
      paymentMethod: PaymentMethod.cash,
      orderId: _orderId,
      // Passes the customer's choice and the exact figures they were
      // shown through to the order, so the vendor sees the same thing
      // before their rider sets off. MobiGas records what was
      // displayed and nothing about whether it gets paid — see
      // OrderProvider.placeOrder.
      partialPayment: _usePartialPayment,
      partialSplit: _agreedSplit,
      partialTerms: _selectedVendor!.partialPaymentNote,
    );

    if (!mounted) return;
    if (orders.error != null) {
      _showError(orders.error!);
      return;
    }
    context.pushReplacement('/order-tracking');
  }

  /// Called by BnplCheckoutSection once Pezesha approves and
  /// disburses the loan for THIS order. The loan is already applied
  /// (loanId in hand); create the order as bnpl with that loanId and
  /// the SAME _orderId the loan was applied against, then go to
  /// tracking — mirroring the cash path's tail.
  ///
  /// No flexible-payment fields here on purpose: Pezesha has already
  /// paid the vendor in full, so there is no balance to arrange with
  /// them. The BNPL section is also hidden once the customer ticks the
  /// flexible-payment box, so the two can't be chosen together.
  Future<void> _placeBnplOrder(String loanId) async {
    final auth = context.read<AuthProvider>();
    final orders = context.read<OrderProvider>();
    final customer = auth.customer;

    if (customer == null ||
        _selectedVendor == null ||
        _selectedListing == null) {
      return;
    }

    await orders.placeOrder(
      customer: customer,
      vendor: _selectedVendor!,
      listing: _selectedListing!,
      paymentMethod: PaymentMethod.bnpl,
      orderId: _orderId,
      loanId: loanId,
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

  /// Gas price plus the selected vendor's flat delivery fee (0 if they
  /// deliver free or haven't set a preference) — the actual amount the
  /// customer owes for this order, and what a partial-payment split
  /// should be computed against rather than the gas price alone.
  double get _orderTotal => _gasPrice + (_selectedVendor?.effectiveDeliveryFee ?? 0);

  /// The selected vendor's flat delivery fee, and whether we actually
  /// know what it is. deliveryPreferenceSet is the tri-state guard (see
  /// VendorModel): a vendor who has never answered the delivery
  /// question is NOT the same as one who chose free delivery, so the
  /// checkout shows no delivery line at all for them rather than
  /// promising free delivery on their behalf. effectiveDeliveryFee
  /// returns 0 in both of those cases, which keeps _orderTotal honest.
  bool get _deliveryFeeKnown => _selectedVendor?.deliveryPreferenceSet ?? false;
  double get _deliveryFee => _selectedVendor?.effectiveDeliveryFee ?? 0;

  /// Currency follows the vendor being ordered from — set once at
  /// vendor onboarding from GPS, not a customer preference.
  String get _vendorCountry => _selectedVendor?.country ?? 'KE';

  /// Whether this customer has ordered from the selected vendor before.
  /// Only used to decide whether a vendor's flexible-payment note shows
  /// in full or greyed-out (when the vendor set partialRepeatOnly). It
  /// gates the NOTE and the opt-in, never the order — a first-timer
  /// always orders at full price regardless. "Before" counts any
  /// non-cancelled prior order with this vendor; MobiGas isn't judging
  /// repayment, just whether they're a returning customer.
  bool _hasOrderedFromSelectedVendor(OrderProvider orders) {
    final vid = _selectedVendor?.id;
    if (vid == null) return false;
    return orders.orders.any(
      (o) => o.vendorId == vid && o.status != OrderStatus.cancelled,
    );
  }

  /// dd/MM/yyyy — matches the date format Kenyan/Ugandan/Tanzanian
  /// customers already read on receipts and statements. Manual
  /// formatting rather than intl's DateFormat since this is the only
  /// place in the screen that needs one.
  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _typeDescription(GasProductType t) {
    switch (t) {
      case GasProductType.refill:
        return 'Gas only — the vendor collects your empty cylinder when they deliver';
      case GasProductType.fullKit:
        return 'New cylinder + gas — no empty cylinder needed';
      case GasProductType.grillKit:
        return '6kg gas + cylinder + burner + grill — complete starter package';
      case GasProductType.burner:
        return 'Standalone burner — fits 3kg or 6kg cylinders, no gas included';
      case GasProductType.regulator:
        return 'Standalone regulator — fits 13kg cylinders, no gas included';
      case GasProductType.mekoCooker:
        return 'Meko + two burner cooker set — gas, hosepipe + 6kg cylinder included';
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
      case GasProductType.burner:
        return Icons.whatshot_rounded;
      case GasProductType.regulator:
        return Icons.speed_rounded;
      case GasProductType.mekoCooker:
        return Icons.soup_kitchen_rounded;
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
      case GasProductType.burner:
        return 'Burner';
      case GasProductType.regulator:
        return 'Regulator';
      case GasProductType.mekoCooker:
        return 'Meko + Cooker';
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    if (_currentStep == 1) _buildCashInfoStep(),
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
      'Pick product, size and vendor',
      'Pay the vendor on delivery',
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

  // ── STEP 1: PRODUCT → SIZE → (BRAND) → VENDOR ─────────────────────
  Widget _buildProductStep() {
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

    // Distinct brands available at this exact type+size — refill,
    // fullKit, and grillKit are priced per-brand (see
    // GasListing.brand); pure accessories (burner/regulator/
    // mekoCooker) never need this step at all.
    final isBrandAwareType = _selectedType == GasProductType.refill ||
        _selectedType == GasProductType.fullKit ||
        _selectedType == GasProductType.grillKit;
    final brandsAvailable = <String>{};
    if (isBrandAwareType && _selectedSize != null) {
      for (final v in vendors) {
        for (final l in v.listings) {
          if (l.available &&
              l.productType == _selectedType &&
              l.size == _selectedSize &&
              l.brand.isNotEmpty) {
            brandsAvailable.add(l.brand);
          }
        }
      }
    }
    final brands = brandsAvailable.toList()..sort();
    final needsBrandStep = brands.isNotEmpty;

    // Vendor offers for type + size (+ brand, when applicable),
    // cheapest first.
    final offers = <(VendorModel, GasListing)>[];
    if (_selectedType != null &&
        _selectedSize != null &&
        (!needsBrandStep || _selectedBrand != null)) {
      for (final v in vendors) {
        for (final l in v.listings) {
          if (l.available &&
              l.productType == _selectedType &&
              l.size == _selectedSize &&
              (!needsBrandStep || l.brand == _selectedBrand)) {
            offers.add((v, l));
          }
        }
      }
      offers.sort((a, b) => a.$2.price.compareTo(b.$2.price));
    }

    final vendorSectionNumber = needsBrandStep ? 4 : 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoCard(
          icon: Icons.payments_outlined,
          text:
              'You\'ll pay cash or ${MobileMoney.primaryLabelFor(_vendorCountry)} on delivery — directly to the vendor when your gas arrives. No prepayment needed.',
        ),

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
          _sectionTitle('1. What do you need?'),
          const SizedBox(height: 10),
          ...GasProductType.values
              .where((t) => offeredTypes.contains(t))
              .map((t) => _typeCard(t)),

          // SIZE
          if (_selectedType != null) ...[
            const SizedBox(height: 20),
            _sectionTitle('2. Choose size'),
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

          // BRAND — only for refill/fullKit/grillKit, once size chosen
          if (needsBrandStep && _selectedSize != null) ...[
            const SizedBox(height: 20),
            _sectionTitle('3. Choose brand'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: brands.map((b) => _brandChip(b)).toList(),
            ),
          ],

          // VENDOR
          if (_selectedType != null &&
              _selectedSize != null &&
              (!needsBrandStep || _selectedBrand != null)) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                _sectionTitle('$vendorSectionNumber. Choose vendor'),
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
                  isCheapest: e.key == 0 && offers.length > 1,
                )),
          ],
        ],
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

  Widget _brandChip(String brand) {
    final isSelected = _selectedBrand == brand;
    return GestureDetector(
      onTap: () => _selectBrand(brand),
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
          brand,
          style: TextStyle(
            color: isSelected ? AppColors.white : AppColors.navy,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
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
      {bool isCheapest = false}) {
    final isSelected = _selectedVendor?.id == vendor.id &&
        _selectedListing?.size == listing.size &&
        _selectedListing?.productType == listing.productType;

    return GestureDetector(
      onTap: () => _selectOffer(vendor, listing),
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
                      if (isCheapest) ...[
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
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Currency.formatFor(vendor.country, listing.price),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.orange,
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
    );
  }

  // ── STEP 2: PAYMENT INFO (CASH / M-PESA ON DELIVERY) ──────────────
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
              Text('Pay on delivery',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 16),
              _feeRow(
                  '${_shortTypeLabel(_selectedListing?.productType ?? GasProductType.refill)} (${_selectedListing?.size})',
                  Currency.formatFor(_vendorCountry, _gasPrice)),
              // BUG FIX: this row was hardcoded to "Extra fees 0" and
              // the total below it to the gas price alone, so a vendor
              // who charges for delivery had their fee silently dropped
              // from checkout — while OrderModel.customerTotal (gas +
              // delivery) and the flexible-payment split (computed on
              // _orderTotal) both included it. Checkout said 1,100, the
              // split said 575 + 575, and the order tile afterwards said
              // 1,150. All three now read off _orderTotal.
              if (_deliveryFeeKnown)
                _feeRow(
                    'Delivery',
                    _deliveryFee > 0
                        ? Currency.formatFor(_vendorCountry, _deliveryFee)
                        : 'Free'),
              const Divider(height: 20, color: Colors.white24),
              _feeRow('Total to pay vendor',
                  Currency.formatFor(_vendorCountry, _orderTotal),
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
                  Text('How payment works',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Color(0xFF166534),
                            fontWeight: FontWeight.w700,
                          )),
                ],
              ),
              const SizedBox(height: 10),
              _explainerRow(
                  'Pay the vendor when your gas is delivered — cash or ${MobileMoney.primaryLabelFor(_vendorCountry)} to the vendor'),
              _explainerRow('No prepayment, no extra charges for you'),
              _explainerRow(
                  'Confirm delivery with your PIN only after you receive your gas'),
            ],
          ),
        ),
        _buildFlexiblePaymentNote(),
        // Pezesha BNPL — only where Pezesha is live (KE/UG) and only
        // if the customer already has an offer cached from tapping
        // "Check my limit" on the home card. BnplCheckoutSection does
        // not register here, so a customer who never opened that card
        // sees cash only. Renders nothing when there is no offer.
        //
        // Hidden entirely once the customer has ticked flexible
        // payment: taking a Pezesha loan for an order they have just
        // arranged to split with the vendor is the one combination
        // nobody wants, and OrderProvider.placeOrder would drop the
        // arrangement anyway (Pezesha pays the vendor in full, so
        // there is no balance left to arrange).
        if (!_usePartialPayment &&
            PezeshaConfig.isAvailableFor(_vendorCountry) &&
            _selectedVendor != null &&
            _selectedListing != null)
          BnplCheckoutSection(
            vendor: _selectedVendor!,
            listing: _selectedListing!,
            country: _vendorCountry,
            orderId: _orderId,
            onApproved: _placeBnplOrder,
          ),
      ],
    );
  }

  /// The selected vendor's flexible-payment terms, and the switch that
  /// lets the customer say they intend to use them.
  ///
  /// Shows an exact computed split ("Pay X now, Y due by `<date>`")
  /// when the vendor picked a structured preset, or falls back to their
  /// free-text note verbatim when they wrote Custom terms — or greys
  /// out entirely for a first-time customer under partialRepeatOnly.
  /// Renders nothing when the vendor isn't offering flexible payment.
  ///
  /// Ticking the switch does exactly one thing: it records on the order
  /// that the customer intends to take the vendor up on this, along
  /// with the figures they were shown, so the vendor learns about it at
  /// order time instead of at the door. MobiGas computes the arithmetic
  /// and passes it on. It does not hold the money, split the payment,
  /// track a balance, chase a due date, or take any position on whether
  /// the arrangement is honoured — that is between the customer and the
  /// vendor. The order is never blocked either way, and remains payable
  /// in full at the total shown above.
  Widget _buildFlexiblePaymentNote() {
    final vendor = _selectedVendor;
    if (vendor == null || !vendor.acceptsPartialPayment) {
      return const SizedBox.shrink();
    }
    // Once ticked, show the FROZEN split rather than recomputing — the
    // customer should keep seeing the same due date they agreed to.
    final split = _agreedSplit ?? vendor.partialPaymentSplitFor(_orderTotal);
    final hasNote = vendor.partialPaymentNote.trim().isNotEmpty;
    if (split == null && !hasNote) {
      return const SizedBox.shrink();
    }

    final orders = context.watch<OrderProvider>();
    final gated = vendor.partialRepeatOnly &&
        !_hasOrderedFromSelectedVendor(orders);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: gated ? 0.04 : 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.orange
                .withValues(alpha: _usePartialPayment ? 0.6 : 0.25),
            width: _usePartialPayment ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.handshake_outlined,
                  size: 16,
                  color: gated ? AppColors.gray400 : AppColors.orange),
              const SizedBox(width: 8),
              Text('Flexible payment',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: gated ? AppColors.gray600 : AppColors.orangeDeep,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      )),
            ],
          ),
          const SizedBox(height: 8),
          if (gated)
            Text(
              'This vendor offers flexible payment to returning customers. '
              'Order at full price now — it may be available on your '
              'next order with them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray600,
                    fontSize: 12,
                    height: 1.45,
                  ),
            )
          else if (split != null) ...[
            // Structured preset — show the exact numbers rather than
            // making the customer do the arithmetic on the note.
            Text(
              'Pay ${Currency.formatFor(vendor.country, split.upfrontAmount)} now, '
              'balance of ${Currency.formatFor(vendor.country, split.balanceAmount)} '
              'due by ${_formatDate(split.dueDate)}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.4,
                  ),
            ),
            if (hasNote) ...[
              const SizedBox(height: 4),
              Text(
                '(${vendor.partialPaymentNote.trim()})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray600,
                      fontSize: 11,
                      height: 1.4,
                    ),
              ),
            ],
          ] else
            // Custom free-text terms — nothing to compute, show as-is.
            Text(
              vendor.partialPaymentNote.trim(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.navy,
                    fontSize: 12,
                    height: 1.45,
                  ),
            ),
          if (!gated) ...[
            const SizedBox(height: 12),
            // THE OPT-IN. Without it nothing anywhere knows the
            // customer intends to use these terms, and the vendor's
            // rider turns up expecting the full amount.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'I\'ll arrange this with the vendor',
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                    ),
                  ),
                  Switch(
                    value: _usePartialPayment,
                    activeTrackColor: AppColors.orange,
                    onChanged: (v) => _setPartialPayment(v, vendor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'MobiGas passes this to the vendor but isn\'t party to the '
              'arrangement and won\'t collect or chase the balance.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                    fontSize: 10.5,
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ],
      ),
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
                    _summaryRow(
                        'Payment',
                        _usePartialPayment
                            ? 'Flexible payment with vendor'
                            : 'Cash / ${MobileMoney.primaryLabelFor(_vendorCountry)} on delivery'),
                    _summaryRow(
                        'Product',
                        _shortTypeLabel(_selectedListing?.productType ??
                            GasProductType.refill)),
                    _summaryRow('Gas size', _selectedListing?.size ?? ''),
                    if ((_selectedListing?.brand ?? '').isNotEmpty)
                      _summaryRow('Brand', _selectedListing!.brand),
                    _summaryRow('Vendor', _selectedVendor?.businessName ?? ''),
                    const Divider(height: 24, color: AppColors.gray200),
                    // Break the total out into gas + delivery only when
                    // there IS a delivery fee — otherwise the single
                    // total line is the whole story and an extra two
                    // rows just add noise.
                    if (_deliveryFee > 0) ...[
                      _summaryRow('Gas price',
                          Currency.formatFor(_vendorCountry, _gasPrice)),
                      _summaryRow('Delivery',
                          Currency.formatFor(_vendorCountry, _deliveryFee)),
                    ] else if (_deliveryFeeKnown)
                      _summaryRow('Delivery', 'Free'),
                    // The order is worth the same either way — a
                    // flexible arrangement changes when the customer
                    // hands it over, not what it costs. Only the label
                    // changes, so the total never reads as an amount
                    // due at the door when it isn't.
                    _summaryRow(
                        _usePartialPayment
                            ? 'Order total'
                            : 'Pay vendor on delivery',
                        Currency.formatFor(_vendorCountry, _orderTotal),
                        isBold: true, valueColor: AppColors.orange),
                    // The arrangement the customer ticked, restated
                    // where they're reviewing the order — the figures
                    // they agreed to, not a second total.
                    if (_usePartialPayment && _agreedSplit != null) ...[
                      const Divider(height: 24, color: AppColors.gray200),
                      _summaryRow(
                          'Paying now',
                          Currency.formatFor(
                              _vendorCountry, _agreedSplit!.upfrontAmount)),
                      _summaryRow(
                          'Balance by ${_formatDate(_agreedSplit!.dueDate)}',
                          Currency.formatFor(
                              _vendorCountry, _agreedSplit!.balanceAmount)),
                    ],
                    const Divider(height: 24, color: AppColors.gray200),
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
        const SizedBox(height: 16),
        if (_usePartialPayment)
          _infoCard(
            icon: Icons.handshake_outlined,
            text: _agreedSplit != null
                ? 'You\'ve chosen ${_selectedVendor?.businessName}\'s flexible payment — have ${Currency.formatFor(_vendorCountry, _agreedSplit!.upfrontAmount)} ready and settle the balance with them directly. We\'ll let them know before they set off. Only share your delivery PIN after you receive your gas.'
                : 'You\'ve chosen ${_selectedVendor?.businessName}\'s flexible payment — settle it with them directly on their own terms. We\'ll let them know before they set off. Only share your delivery PIN after you receive your gas.',
          )
        else
          _infoCard(
            icon: Icons.payments_outlined,
            text:
                'Have ${Currency.formatFor(_vendorCountry, _orderTotal)} ready (cash or ${MobileMoney.primaryLabelFor(_vendorCountry)} to the vendor). Only share your delivery PIN after you receive and pay for your gas.',
          ),
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
          // Flexible rather than a bare Text: the "Balance by
          // dd/MM/yyyy" label is long enough to overflow beside its
          // value on a narrow screen.
          Flexible(
            child: Text(label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray600,
                    ),
                overflow: TextOverflow.ellipsis),
          ),
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
              _usePartialPayment
                  ? '${_selectedListing?.size} $typeLabel · ${Currency.formatFor(_vendorCountry, _orderTotal)} total'
                  : '${_selectedListing?.size} $typeLabel · ${Currency.formatFor(_vendorCountry, _orderTotal)} cash on delivery',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.gray600)),
          if (_deliveryFee > 0) ...[
            const SizedBox(height: 2),
            Text(
                'incl. ${Currency.formatFor(_vendorCountry, _deliveryFee)} delivery',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      fontSize: 11,
                    )),
          ],
          const SizedBox(height: 4),
          Text('from ${_selectedVendor?.businessName}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w600,
                  )),
          if (_usePartialPayment) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.orange.withValues(alpha: 0.25)),
              ),
              child: Text(
                _agreedSplit != null
                    ? 'Flexible payment: ${Currency.formatFor(_vendorCountry, _agreedSplit!.upfrontAmount)} now, balance ${Currency.formatFor(_vendorCountry, _agreedSplit!.balanceAmount)} by ${_formatDate(_agreedSplit!.dueDate)} — arranged directly with the vendor.'
                    : 'Flexible payment — arranged directly with the vendor on their own terms.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orangeDeep,
                      fontSize: 12,
                      height: 1.4,
                    ),
              ),
            ),
          ],
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