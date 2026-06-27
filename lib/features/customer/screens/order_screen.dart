import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  int _currentStep = 0;

  // Step 1 — Gas size
  _GasSize? _selectedSize;

  // Step 2 — Repayment
  final int _repaymentDays = 30;

  // Step 3 — Vendor
  _Vendor? _selectedVendor;

  final List<_GasSize> _sizes = [
    _GasSize(
      kg: 3,
      price: 750,
      label: '3kg',
      description: 'Small household · 1–2 weeks',
      icon: Icons.whatshot_outlined,
    ),
    _GasSize(
      kg: 6,
      price: 1500,
      label: '6kg',
      description: 'Standard household · 3–4 weeks',
      icon: Icons.local_fire_department_outlined,
      isPopular: true,
    ),
    _GasSize(
      kg: 13,
      price: 3200,
      label: '13kg',
      description: 'Large household / business',
      icon: Icons.local_fire_department_rounded,
    ),
  ];

  // Mock vendors
  final List<_Vendor> _vendors = [
    _Vendor(
      name: 'Kamau Gas Supplies',
      area: 'Mirema Drive, Kasarani',
      distance: '0.4 km',
      rating: 4.8,
      reviews: 124,
      deliveryTime: '20–35 min',
      brands: ['Total', 'K-Gas'],
      isOnline: true,
    ),
    _Vendor(
      name: 'Wanjiku Petroleum',
      area: 'Bypass Road, Kasarani',
      distance: '1.1 km',
      rating: 4.6,
      reviews: 89,
      deliveryTime: '30–45 min',
      brands: ['Orion', 'Afrigaz'],
      isOnline: true,
    ),
    _Vendor(
      name: 'Mwangi Gas Centre',
      area: 'Mirema Estate',
      distance: '1.8 km',
      rating: 4.5,
      reviews: 67,
      deliveryTime: '35–50 min',
      brands: ['K-Gas', 'Total'],
      isOnline: false,
    ),
  ];

  double get _serviceFee =>
      _selectedSize != null ? _selectedSize!.price * 0.08 : 0;
  double get _totalDue =>
      _selectedSize != null ? _selectedSize!.price + _serviceFee : 0;

  void _nextStep() {
    if (_currentStep == 0 && _selectedSize == null) {
      _showError('Please select a gas size');
      return;
    }
    if (_currentStep == 2 && _selectedVendor == null) {
      _showError('Please select a vendor');
      return;
    }
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      _confirmOrder();
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _confirmOrder() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildConfirmSheet(),
    );
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
                    if (_currentStep == 0) _buildSizeStep(),
                    if (_currentStep == 1) _buildRepaymentStep(),
                    if (_currentStep == 2) _buildVendorStep(),
                    if (_currentStep == 3) _buildSummaryStep(),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _stepTitle(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                      fontSize: 18,
                    ),
              ),
              Text(
                _stepSubtitle(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_currentStep + 1}/4',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  String _stepTitle() {
    switch (_currentStep) {
      case 0: return 'Choose gas size';
      case 1: return 'Repayment plan';
      case 2: return 'Select vendor';
      case 3: return 'Order summary';
      default: return '';
    }
  }

  String _stepSubtitle() {
    switch (_currentStep) {
      case 0: return 'Remember to have an empty cylinder ready';
      case 1: return 'Pay anytime within your chosen period';
      case 2: return 'Nearest available vendors shown first';
      case 3: return 'Review before confirming';
      default: return '';
    }
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(4, (i) {
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
                if (i < 3) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── STEP 1: GAS SIZE ──────────────────────────────────────────────
  Widget _buildSizeStep() {
    return Column(
      children: [
        _infoCard(
          icon: Icons.swap_horiz_rounded,
          text: 'You must have an empty cylinder to exchange. The vendor will collect your empty cylinder on delivery.',
        ),
        const SizedBox(height: 20),
        ..._sizes.map((size) => _sizeTile(size)),
      ],
    );
  }

  Widget _sizeTile(_GasSize size) {
    final isSelected = _selectedSize?.kg == size.kg;
    return GestureDetector(
      onTap: () => setState(() => _selectedSize = size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.orange.withValues(alpha: 0.08)
              : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.orange : AppColors.gray200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.orange
                    : AppColors.gray100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                size.icon,
                color: isSelected ? AppColors.white : AppColors.gray400,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        size.label,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                      ),
                      if (size.isPopular) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.orange,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'Popular',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    size.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray600,
                        ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'KES ${size.price}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: isSelected
                            ? AppColors.orange
                            : AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '+KES ${(size.price * 0.08).toStringAsFixed(0)} fee',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── STEP 2: REPAYMENT ─────────────────────────────────────────────
  Widget _buildRepaymentStep() {
    final dueDate = DateTime.now().add(const Duration(days: 30));
    final dueDateStr =
        '${dueDate.day}/${dueDate.month}/${dueDate.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedSize != null) _buildAmountDueCard(),
        const SizedBox(height: 20),
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
                  Text(
                    'Repayment due by',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray600,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    dueDateStr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const Divider(height: 24, color: AppColors.gray200),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      color: AppColors.orange, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Maximum repayment period',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray600,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '30 days',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildRepaymentExplainer(),
      ],
    );
  }

  Widget _buildAmountDueCard() {
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
                Text(
                  'Total to repay',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'KES ${_totalDue.toStringAsFixed(0)}',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(
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
              _amountRow('Gas', 'KES ${_selectedSize!.price}'),
              _amountRow(
                  'Fee (8%)', 'KES ${_serviceFee.toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amountRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  fontSize: 11,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepaymentExplainer() {
    return Container(
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
              Text(
                'How repayment works',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Color(0xFF166534),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _explainerRow('Pay any amount, any time within your window'),
          _explainerRow('M-Pesa STK push sent when payment is due'),
          _explainerRow('Pay it all at once or spread it across days'),
          _explainerRow('On-time repayment grows your credit limit'),
          _explainerRow('Late payment blocks new orders until cleared'),
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
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Color(0xFF166534),
                    fontSize: 12,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 3: VENDOR ────────────────────────────────────────────────
  Widget _buildVendorStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoCard(
          icon: Icons.location_on_outlined,
          text: 'Showing vendors near Mirema Drive, Kasarani. Only online vendors who stock ${_selectedSize?.label ?? 'your selected size'} are shown.',
        ),
        const SizedBox(height: 16),
        ..._vendors.map((v) => _vendorTile(v)),
      ],
    );
  }

  Widget _vendorTile(_Vendor vendor) {
    final isSelected = _selectedVendor?.name == vendor.name;
    return GestureDetector(
      onTap: vendor.isOnline
          ? () => setState(() => _selectedVendor = vendor)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: !vendor.isOnline
              ? AppColors.gray100
              : isSelected
                  ? AppColors.orange.withValues(alpha: 0.08)
                  : AppColors.white,
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isSelected
                      ? AppColors.orange
                      : AppColors.gray200,
                  child: Text(
                    vendor.name[0],
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.white
                          : AppColors.gray600,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor.name,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 14,
                              color: vendor.isOnline
                                  ? AppColors.navy
                                  : AppColors.gray400,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        vendor.area,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray400),
                      ),
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
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: vendor.isOnline
                                  ? AppColors.success
                                  : AppColors.gray400,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vendor.distance,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.gray400,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${vendor.rating}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  ' (${vendor.reviews} reviews)',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
                const Spacer(),
                const Icon(Icons.access_time_rounded,
                    color: AppColors.gray400, size: 14),
                const SizedBox(width: 4),
                Text(
                  vendor.deliveryTime,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray600,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: vendor.brands
                  .map((b) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.orangeLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          b,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.orangeDeep,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  // ── STEP 4: SUMMARY ───────────────────────────────────────────────
  Widget _buildSummaryStep() {
    return Column(
      children: [
        _summaryCard(),
        const SizedBox(height: 16),
        _cylinderReminderCard(),
      ],
    );
  }

  Widget _summaryCard() {
    return Container(
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
                Text(
                  'Order summary',
                  style:
                      Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.white,
                          ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _summaryRow('Gas size', _selectedSize?.label ?? ''),
                _summaryRow(
                    'Gas price', 'KES ${_selectedSize?.price ?? 0}'),
                _summaryRow('Service fee (8%)',
                    'KES ${_serviceFee.toStringAsFixed(0)}'),
                const Divider(height: 24, color: AppColors.gray200),
                _summaryRow(
                  'Total to repay',
                  'KES ${_totalDue.toStringAsFixed(0)}',
                  isBold: true,
                  valueColor: AppColors.orange,
                ),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.gray200),
                const SizedBox(height: 16),
                _summaryRow('Repayment window',
                    '$_repaymentDays days'),
                _summaryRow('Vendor', _selectedVendor?.name ?? ''),
                _summaryRow(
                    'Delivery to', _selectedVendor?.area ?? ''),
                _summaryRow(
                    'Est. delivery', _selectedVendor?.deliveryTime ?? ''),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray600,
                ),
          ),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: valueColor ?? AppColors.navy,
                  fontWeight:
                      isBold ? FontWeight.w700 : FontWeight.w500,
                  fontSize: isBold ? 16 : 14,
                ),
          ),
        ],
      ),
    );
  }

  Widget _cylinderReminderCard() {
    return Container(
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
                Text(
                  'Have your empty cylinder ready',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        color: Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The vendor will collect your empty cylinder when delivering the new one. No empty cylinder = no delivery.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Color(0xFF92400E),
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── CONFIRM SHEET ─────────────────────────────────────────────────
  Widget _buildConfirmSheet() {
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
          Text(
            'Confirm your order',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.navy,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedSize?.label} gas · KES ${_totalDue.toStringAsFixed(0)} total · $_repaymentDays day repayment',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'from ${_selectedVendor?.name}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/order-tracking');
            },
            child: const Text('Place order'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.gray600),
            ),
          ),
        ],
      ),
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
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.orangeDeep,
                    height: 1.5,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    return ElevatedButton(
      onPressed: _nextStep,
      child: Text(
        _currentStep < 3 ? 'Continue' : 'Review & confirm',
      ),
    );
  }
}

class _GasSize {
  final int kg;
  final int price;
  final String label;
  final String description;
  final IconData icon;
  final bool isPopular;

  const _GasSize({
    required this.kg,
    required this.price,
    required this.label,
    required this.description,
    required this.icon,
    this.isPopular = false,
  });
}

class _Vendor {
  final String name;
  final String area;
  final String distance;
  final double rating;
  final int reviews;
  final String deliveryTime;
  final List<String> brands;
  final bool isOnline;

  const _Vendor({
    required this.name,
    required this.area,
    required this.distance,
    required this.rating,
    required this.reviews,
    required this.deliveryTime,
    required this.brands,
    required this.isOnline,
  });
}
