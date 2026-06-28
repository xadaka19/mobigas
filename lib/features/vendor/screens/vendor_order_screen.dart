import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/location_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class VendorOrderScreen extends StatefulWidget {
  final OrderModel order;
  const VendorOrderScreen({super.key, required this.order});

  @override
  State<VendorOrderScreen> createState() => _VendorOrderScreenState();
}

class _VendorOrderScreenState extends State<VendorOrderScreen> {
  _DeliveryStep _step = _DeliveryStep.navigating;
  bool _isVerifying = false;
  bool _pinError = false;
  final _riderNameController = TextEditingController();
  final _riderPhoneController = TextEditingController();
  bool _riderAssigned = false;
  bool _useRider = false;
  double? _vendorLat;
  double? _vendorLng;

  @override
  void dispose() {
    _riderNameController.dispose();
    _riderPhoneController.dispose();
    super.dispose();
  }

  Future<void> _updateOrderStatus(OrderStatus status) async {
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: widget.order.orderId)
        .get();
    if (snap.docs.isNotEmpty) {
      await snap.docs.first.reference.update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
        if (_riderAssigned) 'riderName': _riderNameController.text.trim(),
        if (_riderAssigned) 'riderPhone': _riderPhoneController.text.trim(),
      });
    }
  }

  Future<void> _verifyPin(String enteredPin) async {
    setState(() {
      _isVerifying = true;
      _pinError = false;
    });

    // Verify PIN directly from Firestore
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: widget.order.orderId)
        .get();

    if (snap.docs.isEmpty) {
      setState(() {
        _pinError = true;
        _isVerifying = false;
      });
      return;
    }

    final data = snap.docs.first.data() as Map<String, dynamic>;
    final correctPin = data['pin'] as String? ?? '';

    if (enteredPin == correctPin) {
      // PIN correct — mark delivered, trigger bank disbursement
      await snap.docs.first.reference.update({
        'status': OrderStatus.delivered.name,
        'deliveredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // TODO: Backend webhook triggered here to instruct bank to pay vendor

      LocationService.stopTracking();
      setState(() {
        _step = _DeliveryStep.confirmed;
        _isVerifying = false;
      });
    } else {
      setState(() {
        _pinError = true;
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildCurrentStep(),
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
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delivery — ${widget.order.orderId}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                      ),
                ),
                Text(
                  widget.order.customerName,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'KES ${widget.order.bankDisbursementAmount.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.orange,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['Navigate', 'Arrived', 'PIN', 'Done'];
    final currentIndex = _step.index;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final i = e.key;
          final isDone = i < currentIndex;
          final isActive = i == currentIndex;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? AppColors.success
                              : isActive
                                  ? AppColors.orange
                                  : AppColors.white.withValues(alpha: 0.1),
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check_rounded,
                                  color: AppColors.white, size: 14)
                              : Text('${i + 1}',
                                  style: TextStyle(
                                    color: isActive
                                        ? AppColors.white
                                        : AppColors.gray600,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  )),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(e.value,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: isActive
                                    ? AppColors.orange
                                    : isDone
                                        ? AppColors.success
                                        : AppColors.gray600,
                                fontSize: 10,
                              )),
                    ],
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: isDone
                          ? AppColors.success
                          : AppColors.white.withValues(alpha: 0.1),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _DeliveryStep.navigating:
        return _buildNavigatingStep();
      case _DeliveryStep.arrived:
        return _buildArrivedStep();
      case _DeliveryStep.pinEntry:
        return _buildPinStep();
      case _DeliveryStep.confirmed:
        return _buildConfirmedStep();
    }
  }

  // ── STEP 1: NAVIGATING ────────────────────────────────────────────
  Widget _buildNavigatingStep() {
    return Column(
      children: [
        // Customer info card
        _infoCard(
          child: Column(
            children: [
              _infoRow(Icons.person_outline_rounded, 'Customer',
                  widget.order.customerName),
              const Divider(color: Colors.white12, height: 20),
              _infoRow(Icons.location_on_outlined, 'Deliver to',
                  widget.order.customerArea),
              const Divider(color: Colors.white12, height: 20),
              _infoRow(Icons.local_fire_department_outlined, 'Gas size',
                  widget.order.listing.size),
              const Divider(color: Colors.white12, height: 20),
              _infoRow(Icons.account_balance_outlined, 'Payment',
                  'Bank pays on PIN confirmation'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Rider assignment
        _riderSection(),
        const SizedBox(height: 20),
        // Live Google Map
        Container(
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppColors.white.withValues(alpha: 0.1)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _vendorLat != null
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(_vendorLat!, _vendorLng!),
                      zoom: 15,
                    ),
                    onMapCreated: (_) {},
                    markers: {
                      Marker(
                        markerId: const MarkerId('vendor'),
                        position: LatLng(_vendorLat!, _vendorLng!),
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                            BitmapDescriptor.hueOrange),
                        infoWindow: InfoWindow(
                            title: 'You',
                            snippet: widget.order.customerArea),
                      ),
                    },
                    myLocationEnabled: true,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                  )
                : Container(
                    color: AppColors.white.withValues(alpha: 0.05),
                    child: const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.orange),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () async {
            await _updateOrderStatus(OrderStatus.outForDelivery);
            // Start live location tracking
            await LocationService.startTracking(widget.order.orderId);
            setState(() => _step = _DeliveryStep.arrived);
          },
          child: const Text('I have arrived at customer'),
        ),
      ],
    );
  }

  Widget _riderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Assign rider (optional)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                        fontSize: 14,
                      )),
              const Spacer(),
              Switch(
                value: _useRider,
                onChanged: (v) => setState(() => _useRider = v),
                activeThumbColor: AppColors.orange,
              ),
            ],
          ),
          if (_useRider) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _riderNameController,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Rider name',
                hintStyle: TextStyle(color: AppColors.gray600),
                prefixIcon: const Icon(Icons.person_outline_rounded,
                    color: AppColors.gray400, size: 20),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppColors.white.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.orange),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _riderPhoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: AppColors.white),
              decoration: InputDecoration(
                hintText: 'Rider phone',
                hintStyle: TextStyle(color: AppColors.gray600),
                prefixIcon: const Icon(Icons.phone_outlined,
                    color: AppColors.gray400, size: 20),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppColors.white.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.orange),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                if (_riderNameController.text.isNotEmpty &&
                    _riderPhoneController.text.isNotEmpty) {
                  setState(() => _riderAssigned = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Rider ${_riderNameController.text} assigned'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange.withValues(alpha: 0.3),
              ),
              child: Text(
                  _riderAssigned ? 'Rider assigned ✓' : 'Assign rider'),
            ),
          ],
        ],
      ),
    );
  }

  // ── STEP 2: ARRIVED ───────────────────────────────────────────────
  Widget _buildArrivedStep() {
    return Column(
      children: [
        _infoCard(
          child: Column(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.orange, size: 48),
              const SizedBox(height: 12),
              Text(
                'You have arrived at',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.order.customerArea,
                style:
                    Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _infoCard(
          child: Column(
            children: [
              _infoRow(Icons.swap_horiz_rounded, 'Collect empty cylinder',
                  'Before handing over new gas'),
              const Divider(color: Colors.white12, height: 20),
              _infoRow(Icons.local_fire_department_outlined,
                  'Hand over', '${widget.order.listing.size} gas cylinder'),
              const Divider(color: Colors.white12, height: 20),
              _infoRow(Icons.pin_outlined, 'Ask customer for',
                  '4-digit PIN to confirm delivery'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => setState(() => _step = _DeliveryStep.pinEntry),
          child: const Text('Ready for PIN confirmation'),
        ),
      ],
    );
  }

  // ── STEP 3: PIN ENTRY ─────────────────────────────────────────────
  Widget _buildPinStep() {
    return Column(
      children: [
        _infoCard(
          child: Column(
            children: [
              const Icon(Icons.pin_outlined,
                  color: AppColors.orange, size: 48),
              const SizedBox(height: 16),
              Text(
                'Enter customer PIN',
                style:
                    Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask ${widget.order.customerName} for their 4-digit PIN to confirm delivery and trigger payment.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray400,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 24),
              MaterialPinField(
                length: 4,
                keyboardType: TextInputType.number,
                theme: MaterialPinTheme(
                  shape: MaterialPinShape.outlined,
                ),
                onCompleted: (pin) => _verifyPin(pin),
                onChanged: (_) {
                  if (_pinError) setState(() => _pinError = false);
                },
              ),
              if (_pinError) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Incorrect PIN. Ask the customer to check again.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ],
              if (_isVerifying) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(color: AppColors.orange),
                const SizedBox(height: 8),
                Text('Verifying PIN...',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _infoCard(
          child: Row(
            children: [
              const Icon(Icons.account_balance_outlined,
                  color: AppColors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'KES ${widget.order.bankDisbursementAmount.toStringAsFixed(0)} will be sent to your M-Pesa immediately after PIN is confirmed.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        height: 1.5,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── STEP 4: CONFIRMED ─────────────────────────────────────────────
  Widget _buildConfirmedStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 64),
        ),
        const SizedBox(height: 24),
        Text(
          'Delivery confirmed!',
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                color: AppColors.white,
                fontSize: 28,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.order.listing.size} gas delivered to ${widget.order.customerName}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.gray400,
                height: 1.5,
              ),
        ),
        const SizedBox(height: 32),
        _infoCard(
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.payments_rounded,
                      color: AppColors.success, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'KES ${widget.order.bankDisbursementAmount.toStringAsFixed(0)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: AppColors.success,
                                fontWeight: FontWeight.w800,
                                fontSize: 24,
                              ),
                        ),
                        Text(
                          'Being processed by ${widget.order.partnerBankName}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.gray400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              _infoRow(Icons.receipt_outlined, 'Order',
                  widget.order.orderId),
              const SizedBox(height: 8),
              _infoRow(Icons.person_outline_rounded, 'Customer',
                  widget.order.customerName),
            ],
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to dashboard'),
        ),
      ],
    );
  }

  Widget _infoCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.white.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: AppColors.orange, size: 18),
        const SizedBox(width: 10),
        Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                )),
        const Spacer(),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                  )),
        ),
      ],
    );
  }
}

enum _DeliveryStep { navigating, arrived, pinEntry, confirmed }
