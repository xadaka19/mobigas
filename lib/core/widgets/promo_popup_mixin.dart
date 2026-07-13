import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/promo_service.dart';
import 'promo_popup.dart';

/// Mixin for any screen State that should check for and show a promo
/// popup. Add `with PromoPopupMixin` to the State class, then call
/// `checkForPromo(...)` once you have a confirmed audience/country.
mixin PromoPopupMixin<T extends StatefulWidget> on State<T> {
  final PromoService _promoService = PromoService();

  void checkForPromo({
    required String audience, // 'customer' or 'vendor'
    required String country, // 'KE' | 'TZ' | 'UG'
    String? userId,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final promo = await _promoService.getPromoToShow(
        audience: audience,
        country: country,
      );
      if (promo == null || !mounted) return;

      // Log the impression when the dialog is actually about to show,
      // not just when it's fetched.
      unawaited(_promoService.logImpression(
        promoId: promo.id,
        audience: audience,
        country: country,
        userId: userId,
      ));

      await showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => PromoPopup(
          promo: promo,
          onCtaTap: () {
            unawaited(_promoService.logClick(
              promoId: promo.id,
              audience: audience,
              country: country,
              userId: userId,
            ));
            Navigator.pop(context);
            if (promo.actionType == 'route' && promo.actionTarget.isNotEmpty) {
              context.push(promo.actionTarget);
            }
            // actionType == 'url' handling: add url_launcher if/when
            // you need external links from a promo.
          },
          onClose: () => Navigator.pop(context),
        ),
      );

      await _promoService.markPromoShown(promo);
    });
  }
}
