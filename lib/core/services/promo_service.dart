import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/promo_model.dart';

class PromoService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// audience: 'customer' or 'vendor'
  /// country: 'KE', 'TZ', 'UG'
  Future<PromoModel?> getPromoToShow({
    required String audience,
    required String country,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('promo_popups')
          .where('isActive', isEqualTo: true)
          .orderBy('priority')
          .get();

      final candidates = snapshot.docs
          .map((doc) => PromoModel.fromFirestore(doc))
          .where((promo) =>
              (promo.targetAudience == audience || promo.targetAudience == 'all') &&
              (promo.targetCountry == country || promo.targetCountry == 'all') &&
              promo.isWithinDateRange)
          .toList();

      for (final promo in candidates) {
        if (await _shouldShow(promo)) {
          return promo;
        }
      }
      return null;
    } catch (e) {
      // A promo failing to load (missing index, offline, rules, etc.)
      // should never crash or block the home screen — just show no popup.
      // ignore: avoid_print
      print('Failed to load promo: $e');
      return null;
    }
  }

  Future<bool> _shouldShow(PromoModel promo) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'promo_shown_${promo.id}';

    if (promo.frequency == 'every_launch') return true;

    if (promo.frequency == 'once_ever') {
      return !(prefs.getBool(key) ?? false);
    }

    // once_per_day
    final lastShownStr = prefs.getString(key);
    if (lastShownStr == null) return true;
    final lastShown = DateTime.tryParse(lastShownStr);
    if (lastShown == null) return true;
    return DateTime.now().difference(lastShown).inHours >= 24;
  }

  Future<void> markPromoShown(PromoModel promo) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'promo_shown_${promo.id}';
    if (promo.frequency == 'once_ever') {
      await prefs.setBool(key, true);
    } else {
      await prefs.setString(key, DateTime.now().toIso8601String());
    }
  }

  Future<void> logImpression({
    required String promoId,
    required String audience,
    required String country,
    String? userId,
  }) async {
    final promoRef = _firestore.collection('promo_popups').doc(promoId);
    final eventRef = _firestore.collection('promo_analytics').doc();

    final batch = _firestore.batch();
    batch.set(
      promoRef,
      {'impressionCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );
    batch.set(eventRef, {
      'promoId': promoId,
      'type': 'impression',
      'audience': audience,
      'country': country,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      // ignore: avoid_print
      print('Failed to log promo impression: $e');
    }
  }

  Future<void> logClick({
    required String promoId,
    required String audience,
    required String country,
    String? userId,
  }) async {
    final promoRef = _firestore.collection('promo_popups').doc(promoId);
    final eventRef = _firestore.collection('promo_analytics').doc();

    final batch = _firestore.batch();
    batch.set(
      promoRef,
      {'clickCount': FieldValue.increment(1)},
      SetOptions(merge: true),
    );
    batch.set(eventRef, {
      'promoId': promoId,
      'type': 'click',
      'audience': audience,
      'country': country,
      'userId': userId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    try {
      await batch.commit();
    } catch (e) {
      // ignore: avoid_print
      print('Failed to log promo click: $e');
    }
  }
}