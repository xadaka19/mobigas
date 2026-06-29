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
  int _currentStep = 0; // 0=select vendor+size, 1=repayment info, 2=summary

  VendorModel? _selectedVendor;
  GasListing? _selectedListing;
  String? _creditError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      context.read<VendorProvider>().loadVendors(
            lat: auth.customer?.latitude,
            lng: auth.customer?.longitude,
          );
    });
  }

  void _selectListing(VendorModel vendor, GasListing listing) {
    final customer = context.read<AuthProvider>().customer;
    if (customer == null) return;

    if (!customer.canAfford(listing)) {
      setState(() {
        _creditError =
            'Your available credit is KES ${customer.bankCreditAvailable.toStringAsFixed(0)}. '
            'This order requires KES ${listing.price.toStringAsFixed(0)}. '
            'Please select a smaller size or repay existing balance.';
        _selectedListing = null;
        _selectedVendor = null;
      });
      return;
    }

    setState(() {
      _selectedVendor = vendor;
      _selectedListing = listing;
      _creditError = null;
    });
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_selectedVendor == null || _selectedListing == null) {
        _showError('Please select a vendor and gas size');
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

    if (customer == null || _selectedVendor == null || _selectedListing == null) return;

    Navigator.pop(context); // close sheet

    await orders.placeOrder(
      customer: customer,
      vendor: _selectedVendor!,
      listing: _selectedListing!,
    );

    if (mounted) context.go('/order-tracking');
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
  double get _bankInterest => _gasPrice * MobiGasFees.bankInterestRate;
  double get _totalRepayment => _gasPrice + _bankInterest;

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
                    if (_currentStep == 0) _buildVendorSizeStep(),
                    if (_currentStep == 1) _buildRepaymentStep(),
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
    final titles = ['Select gas & vendor', 'Repayment info', 'Order summary'];
    final subtitles = [
      'Prices set by each vendor',
      'Pay within 30 days via M-Pesa',
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
                context.go('/home');
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

  // ── STEP 1: VENDOR + SIZE ─────────────────────────────────────────
  Widget _buildVendorSizeStep() {
    final customer = context.watch<AuthProvider>().customer;
    final vendorProvider = context.watch<VendorProvider>();
    final vendors = vendorProvider.vendors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Credit card
        if (customer != null) _buildCreditCard(customer),
        const SizedBox(height: 16),
        _infoCard(icon: Icons.swap_horiz_rounded, text: 'Have your empty cylinder ready for exchange on delivery.'),
        const SizedBox(height: 16),
        // Credit error
        if (_creditError != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.errorLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_rounded,
                    color: AppColors.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_creditError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                            height: 1.5,
                          )),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Loading
        if (vendorProvider.isLoading)
          const Center(
              child: CircularProgressIndicator(color: AppColors.orange)),
        // Vendors list
        if (!vendorProvider.isLoading && vendors.isEmpty)
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
        ...vendors.map((v) => _vendorCard(v, customer)),
      ],
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
              Text('Limit: KES ${customer.bankApprovedLimit?.toStringAsFixed(0) ?? "0"}',
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

  Widget _vendorCard(VendorModel vendor, CustomerModel? customer) {
    final isSelected = _selectedVendor?.id == vendor.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.orange : AppColors.gray200,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Vendor header
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      vendor.isOnline ? AppColors.orange : AppColors.gray200,
                  child: Text(vendor.businessName[0],
                      style: TextStyle(
                        color: vendor.isOnline
                            ? AppColors.white
                            : AppColors.gray400,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendor.businessName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontSize: 14,
                                color: vendor.isOnline
                                    ? AppColors.navy
                                    : AppColors.gray400,
                              )),
                      Text('${vendor.estate} · ${vendor.distance}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.gray400)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: vendor.isOnline
                            ? AppColors.successLight
                            : AppColors.gray200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        vendor.isOnline ? 'Online' : 'Offline',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: vendor.isOnline
                                  ? AppColors.success
                                  : AppColors.gray400,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppColors.warning, size: 12),
                        const SizedBox(width: 2),
                        Text('${vendor.rating}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.navy,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                )),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Gas sizes
          if (vendor.isOnline && vendor.isVerified) ...[
            const Divider(height: 1, color: AppColors.gray200),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select size',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          )),
                  const SizedBox(height: 8),
                  Row(
                    children: vendor.listings.map((listing) {
                      final isListingSelected =
                          _selectedListing?.size == listing.size &&
                              _selectedVendor?.id == vendor.id;
                      final canAfford =
                          customer?.canAfford(listing) ?? false;

                      return Expanded(
                        child: GestureDetector(
                          onTap: (!listing.available || !canAfford)
                              ? null
                              : () => _selectListing(vendor, listing),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 6),
                            decoration: BoxDecoration(
                              color: !listing.available
                                  ? AppColors.gray100
                                  : isListingSelected
                                      ? AppColors.orange
                                      : !canAfford
                                          ? AppColors.errorLight
                                          : AppColors.orangeLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isListingSelected
                                    ? AppColors.orange
                                    : !listing.available
                                        ? AppColors.gray200
                                        : !canAfford
                                            ? AppColors.error
                                                .withValues(alpha: 0.3)
                                            : AppColors.orange
                                                .withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  listing.size,
                                  style: TextStyle(
                                    color: !listing.available
                                        ? AppColors.gray400
                                        : isListingSelected
                                            ? AppColors.white
                                            : AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  !listing.available
                                      ? 'N/A'
                                      : 'KES ${listing.price.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    color: !listing.available
                                        ? AppColors.gray400
                                        : isListingSelected
                                            ? AppColors.white
                                                .withValues(alpha: 0.9)
                                            : AppColors.orange,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                if (!listing.available)
                                  Text('Out of stock',
                                      style: TextStyle(
                                          color: AppColors.gray400,
                                          fontSize: 9),
                                      textAlign: TextAlign.center),
                                if (listing.available && !canAfford)
                                  Text('Low credit',
                                      style: TextStyle(
                                          color: AppColors.error, fontSize: 9),
                                      textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // Brands
                  Wrap(
                    spacing: 4,
                    children: vendor.brands
                        .map((b) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.gray100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(b,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.gray600,
                                          fontSize: 10)),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          color: AppColors.gray400, size: 12),
                      const SizedBox(width: 4),
                      Text(vendor.deliveryTime,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppColors.gray400, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              child: Text('This vendor is currently offline',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.gray400),
                  textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }

  // ── STEP 2: REPAYMENT INFO ────────────────────────────────────────
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
              _feeRow('Gas price (${_selectedListing?.size})',
                  'KES ${_gasPrice.toStringAsFixed(0)}'),
              _feeRow('Bank interest (8%)',
                  'KES ${_bankInterest.toStringAsFixed(0)}'),
              const Divider(height: 20, color: Colors.white24),
              _feeRow('Total to repay bank',
                  'KES ${_totalRepayment.toStringAsFixed(0)}',
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
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.gray400,
                    fontWeight:
                        isBold ? FontWeight.w600 : FontWeight.w400,
                  )),
          const Spacer(),
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
                    _summaryRow('Vendor', _selectedVendor?.businessName ?? ''),
                    _summaryRow('Gas size', _selectedListing?.size ?? ''),
                    _summaryRow('Gas price',
                        'KES ${_gasPrice.toStringAsFixed(0)}'),
                    _summaryRow('Bank interest (8%)',
                        'KES ${_bankInterest.toStringAsFixed(0)}'),
                    const Divider(height: 24, color: AppColors.gray200),
                    _summaryRow('Total to repay',
                        'KES ${_totalRepayment.toStringAsFixed(0)}',
                        isBold: true, valueColor: AppColors.orange),
                    const Divider(height: 24, color: AppColors.gray200),
                    _summaryRow('Due date', dueDateStr),
                    _summaryRow('Financed by',
                        customer?.partnerBankName ?? 'Partner bank'),
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
                        'The vendor collects your empty cylinder on delivery.',
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
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: valueColor ?? AppColors.navy,
                    fontWeight:
                        isBold ? FontWeight.w700 : FontWeight.w500,
                    fontSize: isBold ? 16 : 14,
                  )),
        ],
      ),
    );
  }

  // ── CONFIRM SHEET ─────────────────────────────────────────────────
  Widget _buildConfirmSheet() {
    final isLoading = context.watch<OrderProvider>().isLoading;

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
              '${_selectedListing?.size} gas · KES ${_totalRepayment.toStringAsFixed(0)} total',
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
