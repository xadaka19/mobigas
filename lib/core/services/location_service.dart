import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class LocationService {
  static StreamSubscription<Position>? _locationSubscription;
  static String? _activeOrderId;

  // Start tracking vendor location for an order
  static Future<void> startTracking(String orderId) async {
    _activeOrderId = orderId;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    _locationSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // update every 10 meters
      ),
    ).listen((Position position) {
      _updateOrderLocation(orderId, position);
    });
  }

  static Future<void> _updateOrderLocation(
      String orderId, Position position) async {
    try {
      final snap = await FirebaseService.orders
          .where('orderId', isEqualTo: orderId)
          .get();

      if (snap.docs.isNotEmpty) {
        await snap.docs.first.reference.update({
          'riderLocation': {
            'lat': position.latitude,
            'lng': position.longitude,
            'timestamp': FieldValue.serverTimestamp(),
          },
        });
      }
    } catch (e) {
      // Location update failed silently
    }
  }

  static void stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;

    // Clear rider location from order
    if (_activeOrderId != null) {
      FirebaseService.orders
          .where('orderId', isEqualTo: _activeOrderId)
          .get()
          .then((snap) {
        if (snap.docs.isNotEmpty) {
          snap.docs.first.reference.update({
            'riderLocation': FieldValue.delete(),
          });
        }
      });
    }
    _activeOrderId = null;
  }

  static Future<Position> getCurrentPosition() async {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
}
