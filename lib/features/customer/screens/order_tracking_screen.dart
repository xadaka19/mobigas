import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/widgets/map_placeholder.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;

  _TrackingStatus _status = _TrackingStatus.pending;
  bool _pinRevealed = false;

  // Mock order data
  final String _orderId = 'MG-2024-0001';
  final String _vendorName = 'Kamau Gas Supplies';
  final String _vendorPhone = '0722 123 456';
  final String _riderName = 'John';
  final String _riderPhone = '0733 456 789';
  final String _gasSize = '6kg';
  final String _deliveryAddress = 'Mirema Drive, Kasarani';
  final double _totalDue = 1620;
  final String _pin = '4829';
  final String _dueDate = '27/07/2026';
  bool _hasRider = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);


    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _status = _TrackingStatus.accepted);
    });
    Future.delayed(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() {
          _status = _TrackingStatus.outForDelivery;
          _hasRider = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _revealPin() {
    setState(() => _pinRevealed = true);
  }

  void _copyPin() {
    Clipboard.setData(ClipboardData(text: _pin));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('PIN copied to clipboard'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _markDelivered() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _buildDeliveredSheet(),
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildStatusCard(),
                    const SizedBox(height: 16),
                    // Live map — shown when out for delivery
                    if (_status == _TrackingStatus.outForDelivery) ...[
                      MapPlaceholder(
                        customerArea: _deliveryAddress,
                        riderName: _hasRider ? _riderName : null,
                        height: 240,
                        showRiderDot: true,
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildTrackingSteps(),
                    const SizedBox(height: 16),
                    // Rider card
                    if (_status == _TrackingStatus.outForDelivery &&
                        _hasRider)
                      _buildRiderCard(),
                    if (_status == _TrackingStatus.outForDelivery &&
                        _hasRider)
                      const SizedBox(height: 16),
                    if (_status == _TrackingStatus.outForDelivery)
                      _buildPinCard(),
                    if (_status == _TrackingStatus.outForDelivery)
                      const SizedBox(height: 16),
                    _buildOrderDetails(),
                    const SizedBox(height: 16),
                    _buildVendorCard(),
                    const SizedBox(height: 16),
                    _buildRepaymentCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            if (_status == _TrackingStatus.outForDelivery)
              _buildConfirmDeliveryButton(),
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
            onTap: () => context.go('/home'),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Order tracking',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                      fontSize: 18,
                    ),
              ),
              Text(
                _orderId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(
                      alpha: 0.1 + _pulseController.value * 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color:
                          AppColors.success.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(
                            alpha:
                                0.5 + _pulseController.value * 0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Live',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: _statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(_statusIcon, color: _statusColor, size: 28),
              );
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusTitle,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray600,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingSteps() {
    final steps = [
      _TrackingStep(
        title: 'Order placed',
        subtitle: 'Your order has been sent to the vendor',
        status: _TrackingStepStatus.done,
      ),
      _TrackingStep(
        title: 'Vendor accepted',
        subtitle: '$_vendorName confirmed your order',
        status: _status.index >= _TrackingStatus.accepted.index
            ? _TrackingStepStatus.done
            : _TrackingStepStatus.pending,
      ),
      _TrackingStep(
        title: 'Out for delivery',
        subtitle: _hasRider
            ? 'Rider $_riderName is on the way'
            : 'Vendor is on the way to your location',
        status: _status.index >= _TrackingStatus.outForDelivery.index
            ? _TrackingStepStatus.done
            : _status == _TrackingStatus.accepted
                ? _TrackingStepStatus.active
                : _TrackingStepStatus.pending,
      ),
      _TrackingStep(
        title: 'Delivered',
        subtitle: 'Share your PIN to confirm delivery',
        status: _status == _TrackingStatus.delivered
            ? _TrackingStepStatus.done
            : _status == _TrackingStatus.outForDelivery
                ? _TrackingStepStatus.active
                : _TrackingStepStatus.pending,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _stepDot(step.status),
                  if (i < steps.length - 1)
                    Container(
                      width: 2,
                      height: 36,
                      color: step.status == _TrackingStepStatus.done
                          ? AppColors.success
                          : AppColors.gray200,
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 14,
                              color: step.status ==
                                      _TrackingStepStatus.pending
                                  ? AppColors.gray400
                                  : AppColors.navy,
                              fontWeight:
                                  step.status ==
                                          _TrackingStepStatus.active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        step.subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: step.status ==
                                      _TrackingStepStatus.pending
                                  ? AppColors.gray200
                                  : AppColors.gray400,
                              fontSize: 12,
                            ),
                      ),
                      if (i < steps.length - 1)
                        const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _stepDot(_TrackingStepStatus status) {
    switch (status) {
      case _TrackingStepStatus.done:
        return Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded,
              color: AppColors.white, size: 14),
        );
      case _TrackingStepStatus.active:
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) => Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(
                  alpha: 0.5 + _pulseController.value * 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.radio_button_checked_rounded,
                color: AppColors.white, size: 14),
          ),
        );
      case _TrackingStepStatus.pending:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.gray200, width: 2),
          ),
        );
    }
  }

  // ── RIDER CARD ────────────────────────────────────────────────────
  Widget _buildRiderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.delivery_dining_rounded,
                  color: AppColors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'Your rider',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'On the way',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.success,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.orange,
                child: Text(
                  _riderName[0],
                  style: const TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _riderName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: AppColors.white,
                            fontSize: 15,
                          ),
                    ),
                    Text(
                      'Rider · $_riderPhone',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray400),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.phone_rounded,
                      color: AppColors.success, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.gray400, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Share your PIN only when the rider arrives at your door with your gas cylinder.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 11,
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── PIN CARD ──────────────────────────────────────────────────────
  Widget _buildPinCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.pin_outlined,
                  color: AppColors.orange, size: 22),
              const SizedBox(width: 10),
              Text(
                'Your delivery PIN',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Share this PIN ONLY when the ${_hasRider ? "rider" : "vendor"} is at your door with your gas.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pinRevealed ? _copyPin : _revealPin,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.orange.withValues(alpha: 0.4)),
              ),
              child: _pinRevealed
                  ? Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _pin.split('').map((digit) {
                            return Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 6),
                              width: 52,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.orange
                                    .withValues(alpha: 0.15),
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.orange,
                                    width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  digit,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displayLarge
                                      ?.copyWith(
                                        color: AppColors.orange,
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.copy_rounded,
                                color: AppColors.gray400, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'Tap to copy PIN',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.gray400,
                                    fontSize: 12,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            4,
                            (i) => Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 6),
                              width: 52,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppColors.white
                                    .withValues(alpha: 0.05),
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                    color: AppColors.gray600,
                                    width: 1),
                              ),
                              child: const Center(
                                child: Icon(
                                    Icons.remove_rounded,
                                    color: AppColors.gray600,
                                    size: 20),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.touch_app_rounded,
                                color: AppColors.orange, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Tap to reveal your PIN',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Never share this PIN before the ${_hasRider ? "rider" : "vendor"} arrives. The PIN triggers instant payment.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: AppColors.error,
                          fontSize: 11,
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order details',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 14),
          _detailRow('Order ID', _orderId),
          _detailRow('Gas size', _gasSize),
          _detailRow('Delivery to', _deliveryAddress),
          _detailRow('Total due',
              'KES ${_totalDue.toStringAsFixed(0)}'),
          _detailRow('Due date', _dueDate),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
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
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.orange,
            child: Text(
              _vendorName[0],
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _vendorName,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                        fontSize: 14,
                        color: AppColors.navy,
                      ),
                ),
                Text(
                  _vendorPhone,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray600,
                      ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.phone_rounded,
                  color: AppColors.success, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepaymentCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: AppColors.orange, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Repayment due by $_dueDate',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  'KES ${_totalDue.toStringAsFixed(0)} — pay anytime via M-Pesa',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmDeliveryButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _markDelivered,
        icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
        label: const Text('I have received my gas'),
      ),
    );
  }

  Widget _buildDeliveredSheet() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 32),
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
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_fire_department_rounded,
                color: AppColors.success, size: 44),
          ),
          const SizedBox(height: 20),
          Text(
            'Confirm delivery',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.navy,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'By confirming, you acknowledge that you received your $_gasSize gas cylinder and shared your PIN with the ${_hasRider ? "rider" : "vendor"}.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray600,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'The vendor will be paid KES ${_totalDue.toStringAsFixed(0)} immediately.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _status = _TrackingStatus.delivered);
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) context.go('/delivery-confirmed');
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Yes, I received my gas'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Not yet',
              style: TextStyle(color: AppColors.gray600),
            ),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    switch (_status) {
      case _TrackingStatus.pending:
        return AppColors.warning;
      case _TrackingStatus.accepted:
        return AppColors.navy;
      case _TrackingStatus.outForDelivery:
        return AppColors.orange;
      case _TrackingStatus.delivered:
        return AppColors.success;
    }
  }

  IconData get _statusIcon {
    switch (_status) {
      case _TrackingStatus.pending:
        return Icons.hourglass_top_rounded;
      case _TrackingStatus.accepted:
        return Icons.store_rounded;
      case _TrackingStatus.outForDelivery:
        return Icons.delivery_dining_rounded;
      case _TrackingStatus.delivered:
        return Icons.check_circle_rounded;
    }
  }

  String get _statusTitle {
    switch (_status) {
      case _TrackingStatus.pending:
        return 'Waiting for vendor';
      case _TrackingStatus.accepted:
        return 'Order accepted';
      case _TrackingStatus.outForDelivery:
        return _hasRider ? 'Rider on the way' : 'Out for delivery';
      case _TrackingStatus.delivered:
        return 'Delivered';
    }
  }

  String get _statusMessage {
    switch (_status) {
      case _TrackingStatus.pending:
        return 'Sending your order to $_vendorName...';
      case _TrackingStatus.accepted:
        return '$_vendorName has accepted your order and is preparing delivery.';
      case _TrackingStatus.outForDelivery:
        return _hasRider
            ? 'Rider $_riderName is heading to $_deliveryAddress. Reveal your PIN when they arrive.'
            : 'Vendor is heading to $_deliveryAddress. Reveal your PIN when they arrive.';
      case _TrackingStatus.delivered:
        return 'Your gas has been delivered. Remember to repay by $_dueDate.';
    }
  }
}

enum _TrackingStatus { pending, accepted, outForDelivery, delivered }
enum _TrackingStepStatus { pending, active, done }

class _TrackingStep {
  final String title;
  final String subtitle;
  final _TrackingStepStatus status;
  const _TrackingStep({
    required this.title,
    required this.subtitle,
    required this.status,
  });
}
