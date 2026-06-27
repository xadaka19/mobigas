import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/widgets/map_placeholder.dart';
import 'package:mobigas/features/vendor/models/vendor_models.dart';

class VendorOrderScreen extends StatefulWidget {
  final IncomingOrder order;
  const VendorOrderScreen({super.key, required this.order});

  @override
  State<VendorOrderScreen> createState() => _VendorOrderScreenState();
}

class _VendorOrderScreenState extends State<VendorOrderScreen> {
  _DeliveryStep _step = _DeliveryStep.navigating;
  bool _isVerifying = false;
  bool _pinError = false;
  bool _useRider = false;

  final _riderNameController = TextEditingController();
  final _riderPhoneController = TextEditingController();
  bool _riderAssigned = false;

  final String _correctPin = '4829';

  @override
  void dispose() {
    _riderNameController.dispose();
    _riderPhoneController.dispose();
    super.dispose();
  }

  Future<void> _verifyPin(String pin) async {
    setState(() {
      _isVerifying = true;
      _pinError = false;
    });
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    if (pin == _correctPin) {
      setState(() {
        _isVerifying = false;
        _step = _DeliveryStep.confirmed;
      });
    } else {
      setState(() {
        _isVerifying = false;
        _pinError = true;
      });
    }
  }

  void _assignRider() {
    if (_riderNameController.text.trim().isEmpty) {
      _showError('Enter rider name');
      return;
    }
    if (_riderPhoneController.text.trim().length < 9) {
      _showError('Enter a valid rider phone number');
      return;
    }
    setState(() {
      _riderAssigned = true;
      _useRider = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${_riderNameController.text} assigned. Location shared via SMS.'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
                    _buildOrderSummaryCard(),
                    const SizedBox(height: 16),
                    if (_step == _DeliveryStep.navigating) ...[
                      _buildNavigatingStep(),
                      const SizedBox(height: 16),
                      _buildRiderSection(),
                    ],
                    if (_step == _DeliveryStep.arrived) ...[
                      // Show map when arrived
                      MapPlaceholder(
                        customerArea: widget.order.customerArea,
                        riderName: _riderAssigned
                            ? _riderNameController.text
                            : null,
                        height: 200,
                        showRiderDot: false,
                      ),
                      const SizedBox(height: 16),
                      _buildPinEntryStep(),
                    ],
                    if (_step == _DeliveryStep.confirmed)
                      _buildConfirmedStep(),
                  ],
                ),
              ),
            ),
            if (_step == _DeliveryStep.navigating)
              _buildArrivedButton(),
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
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivering order',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                      fontSize: 18,
                    ),
              ),
              Text(
                widget.order.orderId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _stepColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _stepLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _stepColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Color get _stepColor {
    switch (_step) {
      case _DeliveryStep.navigating:
        return AppColors.orange;
      case _DeliveryStep.arrived:
        return AppColors.warning;
      case _DeliveryStep.confirmed:
        return AppColors.success;
    }
  }

  String get _stepLabel {
    switch (_step) {
      case _DeliveryStep.navigating:
        return 'On the way';
      case _DeliveryStep.arrived:
        return 'Arrived';
      case _DeliveryStep.confirmed:
        return 'Delivered';
    }
  }

  Widget _buildOrderSummaryCard() {
    return Container(
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
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.navy,
                child: Text(
                  widget.order.customerName[0],
                  style: const TextStyle(
                    color: AppColors.white,
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
                      widget.order.customerName,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontSize: 15,
                            color: AppColors.navy,
                          ),
                    ),
                    Text(
                      widget.order.customerArea,
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
                  Text(
                    widget.order.gasSize,
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.orange,
                              fontWeight: FontWeight.w700,
                              fontSize: 20,
                            ),
                  ),
                  Text(
                    'KES ${widget.order.amount.toStringAsFixed(0)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray600),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20, color: AppColors.gray200),
          Row(
            children: [
              const Icon(Icons.place_rounded,
                  color: AppColors.orange, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.order.customerArea,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.navy,
                      ),
                ),
              ),
              Text(
                widget.order.distance,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── RIDER SECTION ─────────────────────────────────────────────────
  Widget _buildRiderSection() {
    if (_riderAssigned) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delivery_dining_rounded,
                  color: AppColors.success, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rider assigned',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontSize: 14,
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    '${_riderNameController.text} · ${_riderPhoneController.text}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray600,
                        ),
                  ),
                  Text(
                    'Customer location sent via SMS',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                _riderAssigned = false;
                _riderNameController.clear();
                _riderPhoneController.clear();
              }),
              child: const Icon(Icons.edit_rounded,
                  color: AppColors.gray400, size: 18),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _useRider = !_useRider),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _useRider
                  ? AppColors.orange.withValues(alpha: 0.08)
                  : AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    _useRider ? AppColors.orange : AppColors.gray200,
                width: _useRider ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _useRider
                        ? AppColors.orange.withValues(alpha: 0.15)
                        : AppColors.gray100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.delivery_dining_rounded,
                    color: _useRider
                        ? AppColors.orange
                        : AppColors.gray400,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send with a rider',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 14,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        'Assign a rider — they receive customer location via SMS',
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
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _useRider
                        ? AppColors.orange
                        : AppColors.white,
                    border: Border.all(
                      color: _useRider
                          ? AppColors.orange
                          : AppColors.gray200,
                      width: 2,
                    ),
                  ),
                  child: _useRider
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.white, size: 14)
                      : null,
                ),
              ],
            ),
          ),
        ),
        if (_useRider) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rider details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        color: AppColors.navy,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _riderNameController,
                  textCapitalization: TextCapitalization.words,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.navy,
                      ),
                  decoration: const InputDecoration(
                    hintText: 'Rider full name',
                    prefixIcon: Icon(Icons.person_outline_rounded,
                        color: AppColors.gray400, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _riderPhoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.navy,
                      ),
                  decoration: const InputDecoration(
                    hintText: 'Rider phone number',
                    prefixIcon: Icon(Icons.phone_outlined,
                        color: AppColors.gray400, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.orangeLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sms_outlined,
                          color: AppColors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The rider will receive an SMS with the customer\'s name, address, and a Google Maps link to their exact location.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.orangeDeep,
                                fontSize: 11,
                                height: 1.4,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: _assignRider,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Assign rider & send location'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNavigatingStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.local_shipping_rounded,
              color: AppColors.orange, size: 48),
          const SizedBox(height: 16),
          Text(
            'Head to customer location',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.white,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Navigate to ${widget.order.customerArea}. Tap "I have arrived" when you are at the customer\'s door.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    color: AppColors.warning, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Collect the customer\'s empty cylinder when delivering the new one.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Color(0xFF92400E),
                          height: 1.4,
                          fontSize: 12,
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

  Widget _buildPinEntryStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const Icon(Icons.pin_outlined,
              color: AppColors.orange, size: 48),
          const SizedBox(height: 16),
          Text(
            'Enter customer PIN',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.white,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ask the customer for their 4-digit PIN to confirm delivery and receive payment instantly.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 28),
          MaterialPinField(
            length: 4,
            onCompleted: _verifyPin,
            keyboardType: TextInputType.number,
            theme: MaterialPinTheme(
              shape: MaterialPinShape.outlined,
              cellSize: const Size(56, 60),
              textStyle: const TextStyle(
                color: AppColors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (_pinError) ...[
            const SizedBox(height: 12),
            Text(
              'Incorrect PIN. Ask the customer to check again.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
          if (_isVerifying) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: AppColors.orange),
            const SizedBox(height: 8),
            Text(
              'Verifying PIN...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                  ),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.payments_outlined,
                    color: AppColors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'KES ${widget.order.amount.toStringAsFixed(0)} sent to your M-Pesa immediately after PIN confirmed.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.orangeDeep,
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

  Widget _buildConfirmedStep() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 56),
          ),
          const SizedBox(height: 20),
          Text(
            'Payment received!',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white,
                  fontSize: 26,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'KES ${widget.order.amount.toStringAsFixed(0)} sent to your M-Pesa',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'for ${widget.order.gasSize} delivery to ${widget.order.customerName}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
            child: const Text('Back to orders'),
          ),
        ],
      ),
    );
  }

  Widget _buildArrivedButton() {
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
        onPressed: () => setState(() => _step = _DeliveryStep.arrived),
        icon: const Icon(Icons.location_on_rounded, size: 20),
        label: const Text('I have arrived at customer location'),
      ),
    );
  }
}

enum _DeliveryStep { navigating, arrived, confirmed }
