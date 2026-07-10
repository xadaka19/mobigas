import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/services/firebase_service.dart';

/// Why tracking didn't start, so the vendor screen can say something
/// useful instead of showing a map that never moves.
enum TrackingResult {
  started,
  locationServicesOff,
  permissionDenied,
  permissionDeniedForever,
  notSignedIn,
  orderNotFound,
}

class LocationService {
  static StreamSubscription<Position>? _locationSubscription;
  static String? _activeOrderId;

  /// Resolved once per delivery. The old code ran a full
  /// `where('orderId', isEqualTo: ...)` collection query on EVERY
  /// position update — one query plus one write per 10 metres of
  /// road. A 5 km delivery was ~500 needless queries.
  static DocumentReference? _orderRef;

  static bool get isTracking => _locationSubscription != null;

  /// Streams the vendor's own position onto the order document for the
  /// duration of a delivery they are making themselves. (When a rider
  /// delivers, vendor_order_screen never calls this — the rider's web
  /// page writes riderLocation instead, tagged 'rider_link'.)
  ///
  /// Returns why it couldn't start, so the caller can tell the vendor
  /// rather than leaving them with a delivery that silently isn't
  /// being tracked.
  static Future<TrackingResult> startTracking(String orderId) async {
    // Starting a second delivery, or a screen rebuild calling this
    // twice, used to leave the first stream running — two streams
    // from one phone writing to two different orders.
    await stopTracking();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return TrackingResult.notSignedIn;

    if (!await Geolocator.isLocationServiceEnabled()) {
      return TrackingResult.locationServicesOff;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // The old code discarded this return value, so a vendor who
      // tapped "Deny" got a stream that threw into the void.
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return TrackingResult.permissionDeniedForever;
    }
    if (permission == LocationPermission.denied) {
      return TrackingResult.permissionDenied;
    }

    // The vendorId filter is not decoration. Once the orders rules are
    // scoped to the parties on an order, a query that filters only by
    // orderId cannot be proven safe by Firestore and is rejected
    // outright — even for the vendor who owns the order.
    final snap = await FirebaseService.orders
        .where('orderId', isEqualTo: orderId)
        .where('vendorId', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return TrackingResult.orderNotFound;

    _activeOrderId = orderId;
    _orderRef = snap.docs.first.reference;

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // update every 10 meters
        // Keeps location updates flowing once the vendor backgrounds
        // the app or the screen sleeps. This foreground service — not
        // ACCESS_BACKGROUND_LOCATION — is what makes background
        // tracking work, and keeps the release out of Play's
        // background-location review.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'MobiGas delivery in progress',
          notificationText: 'Sharing your location with the customer',
          enableWakeLock: true,
        ),
      ),
    ).listen(
      (position) {
        // A position can arrive after stopTracking() cancelled the
        // stream but before the cancel resolves. Don't resurrect a
        // finished delivery's riderLocation.
        if (_activeOrderId != orderId) return;
        _updateOrderLocation(orderId, position);
      },
      onError: (e) => debugPrint('LocationService: position stream error: $e'),
    );

    return TrackingResult.started;
  }

  static Future<void> _updateOrderLocation(
      String orderId, Position position) async {
    final ref = _orderRef;
    if (ref == null) return;
    try {
      await ref.update({
        'riderLocation': {
          'lat': position.latitude,
          'lng': position.longitude,
          'timestamp': FieldValue.serverTimestamp(),
        },
        // Stamped explicitly so vendor_order_screen can tell this
        // phone's GPS apart from a rider-link position. Without it, a
        // stale 'rider_link' value from an earlier attempt would make
        // the vendor's own map draw a rider marker on top of their
        // own myLocationEnabled dot.
        'riderLocationSource': 'vendor_phone',
      });
    } catch (e) {
      // NOT silent. If the orders rules restrict updates to an
      // allowlist of fields, this is permission-denied on every single
      // position — the vendor's delivery looks fine while the
      // customer's map never moves, and nothing anywhere says why.
      debugPrint('LocationService: riderLocation write failed for '
          '$orderId — $e');
    }
  }

  /// Awaitable, so callers can be sure the stream is down and the
  /// stale pin is cleared before they navigate away.
  ///
  /// When a rider is delivering, startTracking was never called, so
  /// _orderRef is null and this correctly leaves the rider's own
  /// position on the document.
  static Future<void> stopTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;

    final ref = _orderRef;
    _orderRef = null;
    _activeOrderId = null;

    if (ref == null) return;
    try {
      await ref.update({
        'riderLocation': FieldValue.delete(),
        'riderLocationSource': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('LocationService: could not clear riderLocation — $e');
    }
  }

  /// One-shot position, for the location pickers. Does not use the
  /// foreground service.
  static Future<Position> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationServiceDisabledException();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      // Previously this went straight to getCurrentPosition() and
      // threw a raw PermissionDeniedException from deep inside the
      // plugin, which the callers' `catch (_) {}` swallowed.
      throw PermissionDeniedException('Location permission denied');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}