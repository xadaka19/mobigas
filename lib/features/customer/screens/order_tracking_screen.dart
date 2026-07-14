import 'dart:async';
import '../../../core/config/mobile_money.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/delivery_notification_service.dart';
import 'package:mobigas/core/services/screen_security_service.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/features/shared/order_chat_screen.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  GoogleMapController? _mapController;
  StreamSubscription? _orderSubscription;

  LatLng? _riderLocation;
  LatLng? _customerLocation;
  OrderModel? _order;
  OrderStatus _status = OrderStatus.pending;
  bool _pinRevealed = false;

  /// The delivered snapshot arrives more than once — Firestore replays
  /// the document on any subsequent field write, and the local-cache
  /// echo fires before the server ack. Without this latch we pushed
  /// /delivery-confirmed on every one of them.
  bool _deliveredHandled = false;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  @override
  void initState() {
    super.initState();
    ScreenSecurityService.enableSecureMode();
    _initTracking();
  }

  Future<void> _initTracking() async {
    final orders = context.read<OrderProvider>();
    final auth = context.read<AuthProvider>();
    final activeOrder = orders.activeOrder;

    // No active order means this screen was reached directly (deep
    // link, stale notification tap). The old code just returned and
    // left a spinner running forever.
    if (activeOrder == null) {
      if (mounted) context.go('/home');
      return;
    }

    // Set _order BEFORE attaching the listener. The first snapshot can
    // land before the trailing setState below runs, and the progress
    // notification reads _order?.vendorName — it used to send an empty
    // vendor name on the very first update.
    _order = activeOrder;

    final customer = auth.customer;
    if (customer != null &&
        customer.latitude != 0 &&
        customer.longitude != 0) {
      _customerLocation = LatLng(customer.latitude, customer.longitude);
    }

    // The customerId filter is not decoration. Under the scoped
    // `orders` rules, a query filtered on orderId alone is rejected —
    // Firestore cannot prove the result belongs to this customer, so
    // it refuses rather than leak someone else's order. Two equality
    // filters need no composite index.
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: activeOrder.orderId)
        .where('customerId', isEqualTo: customer?.id ?? '')
        .limit(1)
        .get();

    if (snap.docs.isNotEmpty) {
      _orderSubscription =
          snap.docs.first.reference.snapshots().listen((doc) {
        if (!mounted) return;

        // A deleted or not-yet-existent doc returns null data — casting
        // it straight to a Map throws inside the stream callback, where
        // nothing catches it.
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) return;

        setState(() {
          _status = OrderStatus.values.firstWhere(
            (e) => e.name == data['status'],
            orElse: () => OrderStatus.pending,
          );

          final riderLoc = data['riderLocation'] as Map<String, dynamic>?;
          if (riderLoc != null) {
            _riderLocation = LatLng(
              (riderLoc['lat'] as num).toDouble(),
              (riderLoc['lng'] as num).toDouble(),
            );
          }
        });

        _updateMap();
        _syncNotifications();
      });
    }

    if (mounted) setState(() {});
    _updateMap();
  }

  /// Keeps the notification shade in step with the order status.
  ///
  /// showDeliveryProgress posts an `ongoing: true` notification under a
  /// fixed id (1001). The old code called it on *every* snapshot,
  /// including the delivered one, and only then cancelled it — two
  /// un-awaited plugin calls against the same id, racing. A sticky
  /// "delivery in progress" notification could survive the delivery.
  void _syncNotifications() {
    final inFlight = _status == OrderStatus.accepted ||
        _status == OrderStatus.outForDelivery;

    if (inFlight) {
      DeliveryNotificationService.showDeliveryProgress(
        vendorName: _order?.vendorName ?? '',
        gasSize: _order?.listing.size ?? '',
        status: _status == OrderStatus.outForDelivery
            ? '🚴 Rider is on the way to you'
            : '✅ Order accepted — preparing your gas',
      );
      return;
    }

    if (_status == OrderStatus.delivered && !_deliveredHandled) {
      _deliveredHandled = true;
      DeliveryNotificationService.cancelDeliveryNotification();
      DeliveryNotificationService.showDeliveryConfirmed(
        gasSize: _order?.listing.size ?? '',
        // Cash on delivery — customerTotal is the gas price, the same
        // figure shown on the vendor card and the PIN panel. Already
        // includes the currency symbol for the order's country.
        amount: Currency.formatFor(_order?.country, _order?.customerTotal ?? 0),
      );
      if (mounted) context.go('/delivery-confirmed');
      return;
    }

    if (_status == OrderStatus.cancelled) {
      DeliveryNotificationService.cancelDeliveryNotification();
    }
  }

  void _updateMap() {
    final markers = <Marker>{};
    final polylines = <Polyline>{};

    if (_customerLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('customer'),
        position: _customerLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Your location'),
      ));
    }

    if (_riderLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('rider'),
        position: _riderLocation!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Rider'),
      ));

      if (_customerLocation != null) {
        polylines.add(Polyline(
          polylineId: const PolylineId('route'),
          points: [_riderLocation!, _customerLocation!],
          color: AppColors.orange,
          width: 4,
          patterns: [
            PatternItem.dash(20),
            PatternItem.gap(10),
          ],
        ));

        _mapController?.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(
                _riderLocation!.latitude < _customerLocation!.latitude
                    ? _riderLocation!.latitude
                    : _customerLocation!.latitude,
                _riderLocation!.longitude < _customerLocation!.longitude
                    ? _riderLocation!.longitude
                    : _customerLocation!.longitude,
              ),
              northeast: LatLng(
                _riderLocation!.latitude > _customerLocation!.latitude
                    ? _riderLocation!.latitude
                    : _customerLocation!.latitude,
                _riderLocation!.longitude > _customerLocation!.longitude
                    ? _riderLocation!.longitude
                    : _customerLocation!.longitude,
              ),
            ),
            80,
          ),
        );
      }
    } else if (_customerLocation != null) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_customerLocation!, 15),
      );
    }

    if (mounted) {
      setState(() {
        _markers = markers;
        _polylines = polylines;
      });
    }
  }

  @override
  void dispose() {
    ScreenSecurityService.disableSecureMode();
    _orderSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _openChat() {
    if (_order == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderChatScreen(
          orderId: _order!.orderId,
          customerId: _order!.customerId,
          vendorId: _order!.vendorId,
          customerName: _order!.customerName,
          vendorName: _order!.vendorName,
          currentUserId: _order!.customerId,
          currentUserType: 'customer',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    if (_customerLocation == null) {
      return Container(
        color: AppColors.navy,
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.orange),
        ),
      );
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _customerLocation!,
        zoom: 15,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
        _updateMap();
      },
      markers: _markers,
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.go('/home'),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_statusLabel(),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.white)),
                  Text(_order?.vendorName ?? '',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray400)),
                ],
              ),
            ),
            if (_order != null)
              GestureDetector(
                onTap: _openChat,
                child: Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      color: AppColors.white, size: 16),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor().withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _statusColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_statusLabel(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _statusColor(),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomCard() {
    final order = _order;
    if (order == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_fire_department_rounded,
                    color: AppColors.orange, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${order.listing.size} gas · ${order.vendorName}',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.navy),
                    ),
                    Text(
                      _riderLocation != null
                          ? 'Rider is on the way'
                          : 'Preparing your order',
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
                    Currency.formatFor(order.country, order.customerTotal),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.orange,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    'Pay on delivery',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.gray200),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.pin_outlined,
                        color: AppColors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Delivery PIN',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: AppColors.white),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _pinRevealed = !_pinRevealed),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _pinRevealed ? 'Hide' : 'Reveal',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _pinRevealed ? order.pin : '• • • •',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 12,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pay the vendor ${Currency.formatFor(order.country, order.customerTotal)} first (cash or ${MobileMoney.primaryLabelFor(order.country)}), then show this PIN',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 11,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel() {
    switch (_status) {
      case OrderStatus.pending:
        return 'Order placed';
      case OrderStatus.accepted:
        return 'Order accepted';
      case OrderStatus.outForDelivery:
        return 'On the way';
      case OrderStatus.delivered:
        return 'Delivered';
      default:
        return 'Processing';
    }
  }

  Color _statusColor() {
    switch (_status) {
      case OrderStatus.outForDelivery:
        return AppColors.orange;
      case OrderStatus.delivered:
        return AppColors.success;
      case OrderStatus.pending:
        return AppColors.warning;
      default:
        return AppColors.gray400;
    }
  }
}