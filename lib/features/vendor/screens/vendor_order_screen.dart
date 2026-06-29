import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/location_service.dart';
import 'package:mobigas/core/models/app_models.dart';

class VendorOrderScreen extends StatefulWidget {
  final OrderModel order;
  const VendorOrderScreen({super.key, required this.order});

  @override
  State<VendorOrderScreen> createState() => _VendorOrderScreenState();
}

class _VendorOrderScreenState extends State<VendorOrderScreen> {
  _Step _step = _Step.prepare;
  bool _isLoading = false;
  bool _pinError = false;
  bool _useRider = false;
  final _riderNameController = TextEditingController();
  final _riderPhoneController = TextEditingController();
  GoogleMapController? _mapController;
  double? _vendorLat;
  double? _vendorLng;
  double? _customerLat;
  double? _customerLng;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    try {
      final pos = await LocationService.getCurrentPosition();
      if (mounted) {
        setState(() {
          _vendorLat = pos.latitude;
          _vendorLng = pos.longitude;
        });
      }
    } catch (_) {}

    // Load customer coordinates from Firestore
    try {
      final snap = await FirebaseService.orders
          .where('orderId', isEqualTo: widget.order.orderId)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data() as Map<String, dynamic>;
        final cLat = (data['customerLatitude'] ?? 0.0).toDouble();
        final cLng = (data['customerLongitude'] ?? 0.0).toDouble();
        if (cLat != 0 && mounted) {
          setState(() {
            _customerLat = cLat;
            _customerLng = cLng;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _updateStatus(OrderStatus status,
      {Map<String, dynamic>? extra}) async {
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: widget.order.orderId)
        .get();
    if (snap.docs.isNotEmpty) {
      await snap.docs.first.reference.update({
        'status': status.name,
        'updatedAt': FieldValue.serverTimestamp(),
        if (_useRider && _riderNameController.text.isNotEmpty)
          'riderName': _riderNameController.text.trim(),
        if (_useRider && _riderPhoneController.text.isNotEmpty)
          'riderPhone': _riderPhoneController.text.trim(),
        ...?extra,
      });
    }
  }

  Future<void> _startTrip() async {
    setState(() => _isLoading = true);
    await _updateStatus(OrderStatus.outForDelivery);
    await LocationService.startTracking(widget.order.orderId);
    setState(() {
      _step = _Step.enRoute;
      _isLoading = false;
    });
  }

  Future<void> _markArrived() async {
    setState(() => _isLoading = true);
    await _updateStatus(OrderStatus.outForDelivery,
        extra: {'arrivedAt': FieldValue.serverTimestamp()});
    setState(() {
      _step = _Step.arrived;
      _isLoading = false;
    });
  }

  Future<void> _verifyPin(String pin) async {
    setState(() {
      _isLoading = true;
      _pinError = false;
    });

    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: widget.order.orderId)
        .get();

    if (snap.docs.isEmpty) {
      setState(() {
        _pinError = true;
        _isLoading = false;
      });
      return;
    }

    final data = snap.docs.first.data() as Map<String, dynamic>;
    if (pin == data['pin']) {
      await snap.docs.first.reference.update({
        'status': OrderStatus.delivered.name,
        'deliveredAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      LocationService.stopTracking();
      setState(() {
        _step = _Step.confirmed;
        _isLoading = false;
      });
    } else {
      setState(() {
        _pinError = true;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _riderNameController.dispose();
    _riderPhoneController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStepBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStep(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                Text('Order ${widget.order.orderId}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.white)),
                Text(widget.order.customerName,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  Widget _buildStepBar() {
    final steps = ['Prepare', 'En Route', 'Arrived', 'Done'];
    final current = _step.index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final i = e.key;
          final done = i < current;
          final active = i == current;
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
                          color: done
                              ? AppColors.success
                              : active
                                  ? AppColors.orange
                                  : AppColors.white
                                      .withValues(alpha: 0.1),
                        ),
                        child: Center(
                          child: done
                              ? const Icon(Icons.check_rounded,
                                  color: AppColors.white, size: 14)
                              : Text('${i + 1}',
                                  style: TextStyle(
                                    color: active
                                        ? AppColors.white
                                        : AppColors.gray600,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  )),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(e.value,
                          style: TextStyle(
                            color: active
                                ? AppColors.orange
                                : done
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
                      color: done
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

  Widget _buildStep() {
    switch (_step) {
      case _Step.prepare:
        return _buildPrepare();
      case _Step.enRoute:
        return _buildEnRoute();
      case _Step.arrived:
        return _buildArrived();
      case _Step.confirmed:
        return _buildConfirmed();
    }
  }

  // ── STEP 1: PREPARE ──────────────────────────────────────────────
  Widget _buildPrepare() {
    return Column(
      children: [
        _card(child: Column(children: [
          _row(Icons.person_outline_rounded, 'Customer',
              widget.order.customerName),
          _divider(),
          _row(Icons.location_on_outlined, 'Deliver to',
              widget.order.customerArea),
          _divider(),
          _row(Icons.local_fire_department_outlined, 'Gas',
              '${widget.order.listing.size} · ${widget.order.listing.productType.label}'),
          _divider(),
          _row(Icons.account_balance_outlined, 'You receive',
              'KES ${widget.order.bankDisbursementAmount.toStringAsFixed(0)} on delivery'),
        ])),
        const SizedBox(height: 20),
        // Rider assignment
        _card(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Assign a rider (optional)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white, fontSize: 14)),
              const Spacer(),
              Switch(
                value: _useRider,
                onChanged: (v) => setState(() => _useRider = v),
                activeTrackColor: AppColors.orange,
              ),
            ]),
            if (_useRider) ...[
              const SizedBox(height: 12),
              _textField(_riderNameController, 'Rider name',
                  Icons.person_outline_rounded),
              const SizedBox(height: 10),
              _textField(_riderPhoneController, 'Rider phone',
                  Icons.phone_outlined,
                  type: TextInputType.phone),
            ],
          ],
        )),
        const SizedBox(height: 20),
        // Map showing vendor location
        if (_vendorLat != null)
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(_vendorLat!, _vendorLng!),
                  zoom: 13,
                ),
                onMapCreated: (c) {
                  _mapController = c;
                  // Fit both markers if customer location available
                  if (_customerLat != null) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      _mapController?.animateCamera(
                        CameraUpdate.newLatLngBounds(
                          LatLngBounds(
                            southwest: LatLng(
                              _vendorLat! < _customerLat! ? _vendorLat! : _customerLat!,
                              _vendorLng! < _customerLng! ? _vendorLng! : _customerLng!,
                            ),
                            northeast: LatLng(
                              _vendorLat! > _customerLat! ? _vendorLat! : _customerLat!,
                              _vendorLng! > _customerLng! ? _vendorLng! : _customerLng!,
                            ),
                          ),
                          80,
                        ),
                      );
                    });
                  }
                },
                markers: {
                  Marker(
                    markerId: const MarkerId('vendor'),
                    position: LatLng(_vendorLat!, _vendorLng!),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange),
                    infoWindow: const InfoWindow(title: 'You'),
                  ),
                  if (_customerLat != null)
                    Marker(
                      markerId: const MarkerId('customer'),
                      position: LatLng(_customerLat!, _customerLng!),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueBlue),
                      infoWindow: InfoWindow(
                          title: widget.order.customerName,
                          snippet: widget.order.customerArea),
                    ),
                },
                polylines: _customerLat != null ? {
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: [
                      LatLng(_vendorLat!, _vendorLng!),
                      LatLng(_customerLat!, _customerLng!),
                    ],
                    color: AppColors.orange,
                    width: 4,
                    patterns: [PatternItem.dash(20), PatternItem.gap(10)],
                  ),
                } : {},
                myLocationEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
        const SizedBox(height: 24),
        _infoBox(Icons.inventory_2_outlined,
            'Load the gas onto your delivery vehicle before starting the trip. Customer will see you move in real-time.'),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _startTrip,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.white))
              : const Icon(Icons.navigation_rounded, size: 20),
          label: Text(_isLoading ? 'Starting...' : 'Start trip'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: AppColors.success,
          ),
        ),
      ],
    );
  }

  // ── STEP 2: EN ROUTE ─────────────────────────────────────────────
  Widget _buildEnRoute() {
    return Column(
      children: [
        _card(child: Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.navigation_rounded,
                  color: AppColors.success, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trip started!',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppColors.success)),
                    Text(
                        'Customer can see you moving in real-time',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray400)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _row(Icons.location_on_outlined, 'Heading to',
              widget.order.customerArea),
          _divider(),
          _row(Icons.local_fire_department_outlined, 'Delivering',
              widget.order.listing.size),
        ])),
        const SizedBox(height: 16),
        // Live map
        if (_vendorLat != null)
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(_vendorLat!, _vendorLng!),
                  zoom: 15,
                ),
                onMapCreated: (c) => _mapController = c,
                myLocationEnabled: true,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
        const SizedBox(height: 20),
        _infoBox(Icons.location_on_rounded,
            'Your location is being shared with the customer. Tap "I have arrived" when you reach the customer.'),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _isLoading ? null : _markArrived,
          icon: const Icon(Icons.location_on_rounded, size: 20),
          label: const Text('I have arrived'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
          ),
        ),
      ],
    );
  }

  // ── STEP 3: ARRIVED ──────────────────────────────────────────────
  Widget _buildArrived() {
    return Column(
      children: [
        _card(child: Column(children: [
          const Icon(Icons.location_on_rounded,
              color: AppColors.orange, size: 48),
          const SizedBox(height: 12),
          Text('You have arrived!',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.white)),
          const SizedBox(height: 8),
          Text(widget.order.customerArea,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.gray400),
              textAlign: TextAlign.center),
        ])),
        const SizedBox(height: 16),
        _infoBox(Icons.swap_horiz_rounded,
            'Collect the empty cylinder from customer before handing over the new gas.'),
        const SizedBox(height: 16),
        _card(child: Column(children: [
          const Icon(Icons.pin_outlined, color: AppColors.orange, size: 40),
          const SizedBox(height: 12),
          Text('Enter customer PIN',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
              'Ask ${widget.order.customerName} for their 4-digit delivery PIN',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400, height: 1.5)),
          const SizedBox(height: 20),
          MaterialPinField(
            length: 4,
            keyboardType: TextInputType.number,
            theme: MaterialPinTheme(shape: MaterialPinShape.outlined),
            onCompleted: (pin) => _verifyPin(pin),
            onChanged: (_) {
              if (_pinError) setState(() => _pinError = false);
            },
          ),
          if (_pinError) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 16),
                const SizedBox(width: 8),
                Text('Incorrect PIN. Ask customer to check.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.error)),
              ]),
            ),
          ],
          if (_isLoading) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: AppColors.orange),
          ],
          const SizedBox(height: 12),
          _row(Icons.payments_rounded, 'You receive',
              'KES ${widget.order.bankDisbursementAmount.toStringAsFixed(0)} after PIN confirmed'),
        ])),
      ],
    );
  }

  // ── STEP 4: CONFIRMED ────────────────────────────────────────────
  Widget _buildConfirmed() {
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
        Text('Delivery complete!',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white, fontSize: 26)),
        const SizedBox(height: 8),
        Text(
            '${widget.order.listing.size} delivered to ${widget.order.customerName}',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.gray400, height: 1.5)),
        const SizedBox(height: 28),
        _card(child: Column(children: [
          Row(children: [
            const Icon(Icons.payments_rounded,
                color: AppColors.success, size: 24),
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
                  Text('Instantly sent to your M-Pesa by ${widget.order.partnerBankName}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray400)),
                ],
              ),
            ),
          ]),
          _divider(),
          _row(Icons.receipt_outlined, 'Order', widget.order.orderId),
          _divider(),
          _row(Icons.person_outline_rounded, 'Customer',
              widget.order.customerName),
        ])),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Back to dashboard'),
        ),
      ],
    );
  }

  // ── HELPERS ──────────────────────────────────────────────────────
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.white.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, color: AppColors.orange, size: 18),
        const SizedBox(width: 10),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.gray400)),
        const Spacer(),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.right,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _divider() =>
      const Divider(height: 20, color: Colors.white12);

  Widget _infoBox(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orange,
                      height: 1.5,
                    )),
          ),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    TextInputType type = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      style: const TextStyle(color: AppColors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.gray600),
        prefixIcon:
            Icon(icon, color: AppColors.gray400, size: 20),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange),
        ),
      ),
    );
  }
}

enum _Step { prepare, enRoute, arrived, confirmed }
