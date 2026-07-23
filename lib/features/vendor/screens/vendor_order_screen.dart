import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobigas/core/services/screen_security_service.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/location_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/features/shared/order_chat_screen.dart';

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
  // One-time rider tracking link (Option B — web page, no rider
  // app). Minted lazily the first time details are sent, cached for
  // the rest of this screen's lifetime so SMS + WhatsApp share one.
  String? _riderTrackingUrl;
  // Live rider position (rider deliveries only) — read from the same
  // riderLocation field on the order doc that the customer app
  // watches, written by the rider's tracking page.
  LatLng? _riderLivePosition;
  StreamSubscription? _riderPositionSub;
  // One-shot guard so the rider-arrived prompt can't re-fire on
  // every subsequent snapshot of the order doc.
  bool _riderArrivedHandled = false;
  GoogleMapController? _mapController;
  double? _vendorLat;
  double? _vendorLng;
  double? _customerLat;
  double? _customerLng;

  bool get _isRefill =>
      widget.order.listing.productType == GasProductType.refill;

  // BUG FIX: this was `widget.order.listing.price` — the GAS price,
  // not what the customer owes. On an order from a vendor who charges
  // for delivery, the customer is billed listing.price + deliveryFee
  // (OrderModel.customerTotal, which is exactly what the customer app
  // shows them at checkout and on their order tile), while every use
  // site below — the header badge, "You receive", the Arrived screen,
  // the completion screen, and worst of all the SMS/WhatsApp message
  // handed to the rider — quoted the gas price alone. A KSh 50
  // delivery fee meant the rider knocked on the door asking for KSh 50
  // less than the customer was expecting to pay, every single time.
  //
  // customerTotal is deliberately NOT reduced when the customer has
  // arranged flexible payment with this vendor: the order is worth what
  // it is worth, and how it gets paid is the vendor's own arrangement.
  // See _partialPaymentNotice below.
  String get _amount =>
      Currency.formatFor(widget.order.country, widget.order.customerTotal);

  /// The gas price on its own, and the delivery fee on its own — shown
  /// as a breakdown wherever the vendor benefits from seeing why the
  /// total is what it is. Only rendered when there IS a delivery fee;
  /// a two-line breakdown of "gas + 0" is noise.
  String get _gasAmount =>
      Currency.formatFor(widget.order.country, widget.order.listing.price);
  String get _deliveryAmount =>
      Currency.formatFor(widget.order.country, widget.order.deliveryFee);
  bool get _hasDeliveryFee => widget.order.deliveryFee > 0;

  /// dd/MM/yyyy, matching the format the customer saw at checkout.
  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  void initState() {
    super.initState();
    _initLocation();
    _watchRiderPosition();
    ScreenSecurityService.enableSecureMode();
  }

  /// Every read of the order document must prove to Firestore that
  /// this vendor is a party to it. Under the scoped `orders` rules a
  /// query filtered on orderId ALONE is rejected outright — Firestore
  /// cannot know the result belongs to you, so it refuses rather than
  /// leak. Two equality filters need no composite index.
  Future<DocumentReference?> _orderRef() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: widget.order.orderId)
        .where('vendorId', isEqualTo: uid)
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.reference;
  }

  /// Watches riderLocation on the order doc — the field the rider's
  /// tracking page writes — so the vendor sees their rider moving on
  /// the en-route map exactly like the customer does.
  void _watchRiderPosition() {
    _orderRef().then((ref) {
      if (ref == null || !mounted) return;
      _riderPositionSub = ref.snapshots().listen((doc) {
        if (!mounted) return;
        final data = doc.data() as Map<String, dynamic>?;
        final loc = data?['riderLocation'] as Map<String, dynamic>?;
        // Only treat it as RIDER movement when it came from the
        // tracking link — when the vendor delivers themselves, this
        // same field carries their own phone's GPS, already shown
        // via myLocationEnabled.
        if (loc != null && data?['riderLocationSource'] == 'rider_link') {
          setState(() {
            _riderLivePosition = LatLng(
              (loc['lat'] as num).toDouble(),
              (loc['lng'] as num).toDouble(),
            );
          });
        }
        // Rider tapped "I have arrived" on the tracking page.
        if (data?['riderArrivedSignal'] == true &&
            !_riderArrivedHandled &&
            _step == _Step.enRoute) {
          _riderArrivedHandled = true;
          _showRiderArrivedDialog();
        }
      });
    });
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
      final ref = await _orderRef();
      final doc = await ref?.get();
      final data = doc?.data() as Map<String, dynamic>?;
      if (data != null) {
        final cLat = (data['customerLatitude'] ?? 0.0).toDouble();
        final cLng = (data['customerLongitude'] ?? 0.0).toDouble();
        if (cLat != 0 && mounted) {
          setState(() {
            _customerLat = cLat;
            _customerLng = cLng;
          });
        }
      }
    } catch (e) {
      // Not silent. A permission-denied here means the orders rules
      // reject this vendor's read, and the delivery map will open on
      // nothing with no explanation.
      debugPrint('VendorOrderScreen: could not load customer coords — $e');
    }
  }

  Future<void> _updateStatus(OrderStatus status,
      {Map<String, dynamic>? extra}) async {
    final ref = await _orderRef();
    if (ref != null) {
      await ref.update({
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

  /// Hands off to Google Maps for turn-by-turn navigation to the
  /// customer. Falls back to the Maps website if the app intent
  /// can't launch.
  Future<void> _openNavigation() async {
    if (_customerLat == null || _customerLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Customer location not available for this order.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    final appUri = Uri.parse(
        'google.navigation:q=$_customerLat,$_customerLng&mode=d');
    final webUri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$_customerLat,$_customerLng&travelmode=driving');
    try {
      final launched =
          await launchUrl(appUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  void _openChat() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderChatScreen(
          orderId: widget.order.orderId,
          customerId: widget.order.customerId,
          vendorId: widget.order.vendorId,
          customerName: widget.order.customerName,
          vendorName: widget.order.vendorName,
          currentUserId: uid,
          currentUserType: 'vendor',
        ),
      ),
    );
  }

  /// Mints (or reuses) the one-time rider tracking link for this
  /// order via the createRiderTrackingToken Cloud Function. Never
  /// throws — a minting failure just means the message goes out
  /// without a tracking link rather than not at all.
  Future<void> _ensureRiderTrackingUrl() async {
    if (_riderTrackingUrl != null) return;
    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('createRiderTrackingToken');
      final result =
          await callable.call({'orderId': widget.order.orderId});
      final url = (result.data as Map)['url'] as String?;
      if (url != null && mounted) {
        setState(() => _riderTrackingUrl = url);
      }
    } catch (e) {
      // Tracking link is an enhancement, not a requirement — the
      // rider still gets address + Maps directions without it. But
      // surface the failure so it's diagnosable: NOT_FOUND here
      // almost always means createRiderTrackingToken isn't deployed
      // yet (firebase deploy --only functions).
      debugPrint('Rider tracking link failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Live tracking link unavailable — message sent without it.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  /// Builds the rider handoff message — shared by SMS and WhatsApp.
  /// Riders aren't MobiGas app users, so this pre-fills the vendor's
  /// own SMS/WhatsApp with everything the rider needs: address,
  /// directions, what the order is worth, and the live-tracking link.
  ///
  /// On a flexible-payment order this message deliberately does NOT
  /// tell the rider a figure to collect. MobiGas does not know what the
  /// vendor and customer settled on, is not party to it, and has no
  /// business instructing someone else's rider on debt collection. It
  /// states the order's value, notes that the customer asked for the
  /// vendor's own flexible terms, and hands the decision back to the
  /// vendor — who is the one sending this message in the first place
  /// and can add whatever instruction they actually want.
  String _riderMessageBody() {
    final mapsLink = (_customerLat != null && _customerLng != null)
        ? 'https://www.google.com/maps/dir/?api=1&destination=$_customerLat,$_customerLng&travelmode=driving'
        : null;
    final o = widget.order;
    final l = o.listing;
    final item = l.brand.isNotEmpty
        ? '${l.brand} · ${l.size} ${l.productType.label}'
        : '${l.size} ${l.productType.label}';
    final body = StringBuffer()
      ..writeln('MobiGas delivery for ${o.customerName}');
    if (o.customerPhone.isNotEmpty) {
      body.writeln('Customer phone: ${o.customerPhone}');
    }
    body
      ..writeln('Deliver to: ${o.customerArea}')
      ..writeln('Item: $item');
    if (_hasDeliveryFee) {
      body.writeln('Order value: $_amount ($_gasAmount gas + '
          '$_deliveryAmount delivery)');
    } else {
      body.writeln('Order value: $_amount');
    }
    if (o.partialPayment) {
      body.write(
          'NOTE: the customer asked to use your flexible payment terms on '
          'this order. Collect whatever you have agreed with them, then '
          'take the PIN.');
    } else {
      body.write(
          'Payment: customer pays $_amount (cash or mobile money to the '
          'vendor). Confirm payment is received before taking the PIN.');
    }
    // ONE link, one instruction. The tracking page has the map AND a
    // "Navigate with Google Maps" button built in — sending a
    // separate raw Maps link alongside it just invites the rider to
    // tap that one instead and never start tracking. The raw Maps
    // link only goes out as a fallback when the tracking link
    // couldn't be minted.
    if (_riderTrackingUrl != null) {
      body.writeln();
      body.write(
          'OPEN THIS LINK to start the delivery — it shows you the map, gives you Google Maps directions, and lets the customer see you coming: $_riderTrackingUrl');
    } else if (mapsLink != null) {
      body.writeln();
      body.write('Directions: $mapsLink');
    }
    return body.toString();
  }

  /// Normalizes a Kenyan number to international format for wa.me
  /// links, which require it (unlike the sms: scheme).
  String _waPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('254')) return digits;
    if (digits.startsWith('0')) return '254${digits.substring(1)}';
    return digits;
  }

  bool _requireRiderPhone() {
    if (_riderPhoneController.text.trim().isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Enter the rider\'s phone number first.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
    return false;
  }

  Future<void> _sendRiderDetailsSms() async {
    if (!_requireRiderPhone()) return;
    await _ensureRiderTrackingUrl();
    final uri = Uri(
      scheme: 'sms',
      path: _riderPhoneController.text.trim(),
      queryParameters: {'body': _riderMessageBody()},
    );
    try {
      await launchUrl(uri);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open the SMS app.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _sendRiderDetailsWhatsApp() async {
    if (!_requireRiderPhone()) return;
    await _ensureRiderTrackingUrl();
    // wa.me is WhatsApp's own universal link — opens the chat with
    // this number, message pre-filled. The sms: scheme can never
    // reach WhatsApp, which is why SMS-only "refused" for it.
    final uri = Uri.parse(
        'https://wa.me/${_waPhone(_riderPhoneController.text.trim())}'
        '?text=${Uri.encodeComponent(_riderMessageBody())}');
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Could not open WhatsApp. Is it installed?'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Could not open WhatsApp. Is it installed?'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  /// Shown once when the rider's tracking page sends the "arrived"
  /// signal — offers to advance this screen to the Arrived step so
  /// the vendor can enter the PIN.
  void _showRiderArrivedDialog() {
    final rider = _riderNameController.text.trim();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navy,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.two_wheeler_rounded,
              color: AppColors.success, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Rider has arrived!',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Text(
            widget.order.partialPayment
                ? '${rider.isNotEmpty ? rider : 'Your rider'} is at ${widget.order.customerName}\'s location. Once you\'re satisfied with what was collected, move to the Arrived step to enter the PIN.'
                : '${rider.isNotEmpty ? rider : 'Your rider'} is at ${widget.order.customerName}\'s location. Confirm payment is received, then move to the Arrived step to enter the PIN.',
            style: Theme.of(ctx)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.gray400, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not yet',
                style: TextStyle(color: AppColors.gray400)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markArrived();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success),
            child: const Text('Mark as Arrived'),
          ),
        ],
      ),
    );
  }

  Future<void> _startTrip() async {
    setState(() => _isLoading = true);
    await _updateStatus(OrderStatus.outForDelivery);
    // When a rider is doing the delivery, the vendor's phone stays
    // at the shop — streaming ITS GPS would overwrite the rider's
    // live position (written via the tracking link) on every tick,
    // making the customer's map show the stationary shop instead of
    // the moving rider. Only track this phone when the vendor
    // themselves is delivering.
    if (!_useRider) {
      final result = await LocationService.startTracking(widget.order.orderId);
      // The trip still starts — a delivery without a live map is
      // degraded, not broken. But the old code advanced to enRoute
      // regardless, so a vendor who denied the location permission
      // saw a normal delivery while the customer's map never moved.
      if (result != TrackingResult.started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(switch (result) {
            TrackingResult.locationServicesOff =>
              'Turn on location — the customer cannot see you on the map.',
            TrackingResult.permissionDeniedForever =>
              'Location is blocked. Enable it in Settings > Apps > MobiGas Vendor.',
            TrackingResult.permissionDenied =>
              'Without location the customer cannot track your delivery.',
            TrackingResult.notSignedIn => 'You are signed out.',
            TrackingResult.orderNotFound => 'Could not find this order.',
            TrackingResult.started => '',
          }),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
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

  /// The PIN is checked on the SERVER, by the confirmDelivery callable.
  ///
  /// It used to be compared here, in Dart, against a `pin` field this
  /// phone had already downloaded — so nothing anywhere verified the
  /// customer had ever produced it, and a modified client could
  /// confirm its own deliveries (and accrue the finder fee) with no
  /// customer present. Firestore rules cannot close that: a rule can
  /// only inspect values the client chooses to send.
  ///
  /// confirmDelivery is now the only writer of status 'delivered'. It
  /// also clears riderLocation and rate-limits PIN attempts.
  Future<void> _verifyPin(String pin) async {
    setState(() {
      _isLoading = true;
      _pinError = false;
    });

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('confirmDelivery');
      await callable.call({
        'orderId': widget.order.orderId,
        'pin': pin,
      });

      await LocationService.stopTracking();
      if (!mounted) return;
      setState(() {
        _step = _Step.confirmed;
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // invalid-argument is a wrong PIN — show it on the field, the
      // way a wrong PIN always looked. Everything else is a real
      // failure the vendor needs told about.
      final wrongPin = e.code == 'invalid-argument';
      setState(() {
        _pinError = wrongPin;
        _isLoading = false;
      });
      if (!wrongPin) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message ?? 'Could not confirm delivery.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pinError = false;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No connection. Try confirming again.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  void dispose() {
    ScreenSecurityService.disableSecureMode();
    _riderPositionSub?.cancel();
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
          GestureDetector(
            onTap: _openChat,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.white, size: 18),
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
              '$_amount 💵',
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

  /// The customer opted into THIS VENDOR'S OWN published flexible-payment
  /// terms at checkout. This box tells the vendor that, and shows the
  /// exact figures the customer was shown, so both sides are looking at
  /// the same numbers instead of two different recollections.
  ///
  /// That is the entire job. It is deliberately NOT a collection
  /// instruction: it does not say "collect X", it does not appear in the
  /// order's value anywhere, and there is no control here or anywhere
  /// else to mark a balance received. MobiGas is not party to the
  /// arrangement and does not track it — how and when the vendor
  /// collects is between the vendor and their customer, and the vendor
  /// is the only one who knows what they actually settled on.
  ///
  /// Renders nothing on a normal order.
  Widget _partialPaymentNotice() {
    final o = widget.order;
    if (!o.partialPayment) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.handshake_outlined,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Text('Customer chose your flexible payment',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w700,
                    )),
          ]),
          const SizedBox(height: 10),
          if (o.hasPartialFigures)
            Text(
              'At checkout they were shown: pay '
              '${Currency.formatFor(o.country, o.partialUpfront)} now, '
              'balance of '
              '${Currency.formatFor(o.country, o.partialBalance)}'
              '${o.partialDueBy != null ? ' by ${_formatDate(o.partialDueBy!)}' : ''}.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
            )
          else if (o.partialTerms.trim().isNotEmpty)
            Text(
              'At checkout they were shown your terms: '
              '"${o.partialTerms.trim()}"',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
            )
          else
            Text(
              'They asked to use the flexible payment terms on your '
              'profile for this order.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
            ),
          if (o.hasPartialFigures && o.partialTerms.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('(${o.partialTerms.trim()})',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      fontSize: 11,
                      height: 1.4,
                    )),
          ],
          const SizedBox(height: 10),
          Text(
            'This order is still worth $_amount. What you collect at the '
            'door, and when you collect the rest, is between you and your '
            'customer — MobiGas is only passing on what they were shown, '
            'and doesn\'t hold, split, or keep track of any of it.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  height: 1.45,
                  fontSize: 11.5,
                ),
          ),
        ],
      ),
    );
  }

  // ── STEP 1: PREPARE ──────────────────────────────────────────────
  Widget _buildPrepare() {
    return Column(
      children: [
        _card(child: Column(children: [
          _row(Icons.person_outline_rounded, 'Customer',
              widget.order.customerName),
          if (widget.order.customerPhone.isNotEmpty) ...[
            _divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.phone_outlined,
                    color: AppColors.orange, size: 18),
                const SizedBox(width: 10),
                Text('Phone',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.gray400)),
                const Spacer(),
                Text(widget.order.customerPhone,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.white, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => launchUrl(
                      Uri(scheme: 'tel', path: widget.order.customerPhone)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.success,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.call_rounded,
                          size: 13, color: AppColors.white),
                      const SizedBox(width: 4),
                      Text('Call',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: AppColors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ]),
            ),
          ],
          _divider(),
          _row(Icons.location_on_outlined, 'Deliver to',
              widget.order.customerArea),
          _divider(),
          _row(
              widget.order.listing.productType.isAccessoryOnly
                  ? Icons.build_outlined
                  : Icons.local_fire_department_outlined,
              widget.order.listing.productType.isAccessoryOnly
                  ? 'Product'
                  : 'Gas',
              widget.order.listing.brand.isNotEmpty
                  ? '${widget.order.listing.brand} · ${widget.order.listing.size} · ${widget.order.listing.productType.label}'
                  : '${widget.order.listing.size} · ${widget.order.listing.productType.label}'),
          // Break the total down only when there IS a delivery fee —
          // the vendor should be able to see why the figure below is
          // more than their listed gas price, without three rows of
          // arithmetic on every free-delivery order.
          if (_hasDeliveryFee) ...[
            _divider(),
            _row(Icons.sell_outlined, 'Gas price', _gasAmount),
            _divider(),
            _row(Icons.local_shipping_outlined, 'Your delivery fee',
                _deliveryAmount),
          ],
          _divider(),
          _row(Icons.payments_rounded, 'Order value',
              '$_amount from customer on delivery'),
        ])),
        const SizedBox(height: 16),
        if (widget.order.partialPayment)
          _partialPaymentNotice()
        else
          _infoBox(Icons.payments_rounded,
              'Confirm payment of $_amount is received (cash or mobile money to you) before the customer shares the PIN — the PIN completes the delivery.'),
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
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sendRiderDetailsSms,
                    icon: const Icon(Icons.sms_outlined, size: 16),
                    // FittedBox + tight padding: the default button
                    // padding made the label overflow its half-width
                    // slot on narrower screens, wrapping/clipping the
                    // text. Scale down instead of ever wrapping.
                    label: const FittedBox(child: Text('SMS')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      side: const BorderSide(color: AppColors.orange),
                      minimumSize: const Size(0, 44),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sendRiderDetailsWhatsApp,
                    icon: const Icon(Icons.chat_rounded, size: 16),
                    label: const FittedBox(child: Text('WhatsApp')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      minimumSize: const Size(0, 44),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                  widget.order.partialPayment
                      ? 'Send the delivery details to your rider — the message notes the flexible payment but leaves the amount to you'
                      : 'Send the delivery details to your rider',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400, fontSize: 11)),
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
              widget.order.listing.brand.isNotEmpty
                  ? '${widget.order.listing.brand} · ${widget.order.listing.size}'
                  : widget.order.listing.size),
          _divider(),
          _row(
              Icons.payments_rounded,
              'Order value',
              widget.order.partialPayment
                  ? '$_amount — flexible payment arranged'
                  : '$_amount — confirm received before PIN'),
          // BUG FIX: rider info was captured on the Prepare step and
          // then never shown again anywhere — the vendor had no way
          // to confirm who they'd actually assigned.
          if (_useRider && _riderNameController.text.trim().isNotEmpty) ...[
            _divider(),
            _row(Icons.two_wheeler_outlined, 'Rider',
                '${_riderNameController.text.trim()} · ${_riderPhoneController.text.trim()}'),
          ],
        ])),
        if (widget.order.partialPayment) ...[
          const SizedBox(height: 16),
          _partialPaymentNotice(),
        ],
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
                myLocationEnabled: !_useRider,
                markers: {
                  if (_riderLivePosition != null)
                    Marker(
                      markerId: const MarkerId('rider'),
                      position: _riderLivePosition!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueOrange),
                      infoWindow: InfoWindow(
                          title: _riderNameController.text.trim().isNotEmpty
                              ? _riderNameController.text.trim()
                              : 'Rider'),
                    ),
                  if (_customerLat != null)
                    Marker(
                      markerId: const MarkerId('customer'),
                      position: LatLng(_customerLat!, _customerLng!),
                      icon: BitmapDescriptor.defaultMarkerWithHue(
                          BitmapDescriptor.hueBlue),
                      infoWindow: InfoWindow(
                          title: widget.order.customerName),
                    ),
                },
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
        const SizedBox(height: 20),
        _infoBox(
            Icons.location_on_rounded,
            _useRider
                ? (_riderLivePosition != null
                    ? 'Your rider is sharing their location — you and the customer both see them moving. Tap "I have arrived" once your rider confirms they\'ve reached the customer.'
                    : 'Waiting for your rider to open the tracking link and tap Start. Once they do, you\'ll see them moving here.')
                : 'Your location is being shared with the customer. Tap "I have arrived" when you reach the customer.'),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _openNavigation,
          icon: const Icon(Icons.navigation_rounded, size: 20),
          label: const Text('Navigate with Google Maps'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: AppColors.white,
            foregroundColor: AppColors.navy,
          ),
        ),
        const SizedBox(height: 12),
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
        // On a flexible-payment order MobiGas has no business telling
        // the vendor that a specific amount must be in hand before the
        // PIN — it doesn't know what they agreed. The PIN still means
        // exactly what it always meant (the customer confirming they
        // received their gas); when to ask for it is the vendor's call.
        if (widget.order.partialPayment)
          _partialPaymentNotice()
        else
          _infoBox(Icons.payments_rounded,
              'Confirm payment of $_amount is received (cash or mobile money to you) FIRST — the customer\'s PIN completes the delivery.'),
        if (_isRefill) ...[
          const SizedBox(height: 12),
          _infoBox(Icons.swap_horiz_rounded,
              'Collect the empty cylinder from customer before handing over the new gas.'),
        ],
        if (_useRider && _riderNameController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _infoBox(Icons.two_wheeler_outlined,
              'Your rider ${_riderNameController.text.trim()} gets the 4-digit PIN from the customer at the door — call them for it and enter it below.'),
        ],
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
          _row(
              Icons.payments_rounded,
              'Order value',
              widget.order.partialPayment
                  ? '$_amount — paid by your arrangement'
                  : '$_amount from customer'),
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
            '${widget.order.listing.brand.isNotEmpty ? '${widget.order.listing.brand} ' : ''}${widget.order.listing.size} delivered to ${widget.order.customerName}',
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
                    _amount,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                  ),
                  // "Collected" would be a claim MobiGas can't make on a
                  // flexible-payment order — it has no idea what actually
                  // changed hands at the door, and saying so would imply
                  // it was watching.
                  Text(
                      widget.order.partialPayment
                          ? 'Order value — settled by your own arrangement with the customer'
                          : 'Collected from the customer on delivery',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray400)),
                ],
              ),
            ),
          ]),
          if (_hasDeliveryFee) ...[
            _divider(),
            _row(Icons.sell_outlined, 'Gas price', _gasAmount),
            _divider(),
            _row(Icons.local_shipping_outlined, 'Your delivery fee',
                _deliveryAmount),
          ],
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
      // BUG FIX: typed text was styled white but the field rendered
      // with the theme's default LIGHT fill — white-on-white, so the
      // hint (gray) showed but anything typed was invisible. Fill is
      // now explicit and dark to match every other input on this
      // navy screen.
      style: const TextStyle(color: AppColors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.gray600),
        prefixIcon:
            Icon(icon, color: AppColors.gray400, size: 20),
        filled: true,
        fillColor: AppColors.white.withValues(alpha: 0.05),
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