import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/services/firebase_service.dart';

class DeliveryConfirmedScreen extends StatefulWidget {
  const DeliveryConfirmedScreen({super.key});

  @override
  State<DeliveryConfirmedScreen> createState() =>
      _DeliveryConfirmedScreenState();
}

class _DeliveryConfirmedScreenState extends State<DeliveryConfirmedScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  int _selectedRating = 0;
  bool _ratingSubmitted = false;
  bool _isSubmittingRating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = Tween<double>(begin: 0.5, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) return;
    setState(() => _isSubmittingRating = true);

    final order = context.read<OrderProvider>().activeOrder;
    if (order == null) {
      setState(() {
        _ratingSubmitted = true;
        _isSubmittingRating = false;
      });
      return;
    }

    try {
      // Save rating to order
      // Scoped rules: a query filtered on orderId alone is rejected —
      // Firestore cannot prove the result belongs to this customer.
      final orderSnap = await FirebaseService.orders
          .where('orderId', isEqualTo: order.orderId)
          .where('customerId', isEqualTo: order.customerId)
          .limit(1)
          .get();

      if (orderSnap.docs.isNotEmpty) {
        await orderSnap.docs.first.reference.update({
          'customerRating': _selectedRating,
          'ratedAt': FieldValue.serverTimestamp(),
        });
      }

      // Update vendor's average rating
      final vendorDoc = await FirebaseService.vendors
          .doc(order.vendorId)
          .get();

      if (vendorDoc.exists) {
        final data = vendorDoc.data() as Map<String, dynamic>;
        final currentRating = (data['rating'] ?? 0.0).toDouble();
        final totalReviews = (data['totalReviews'] ?? 0) as int;
        final newTotal = totalReviews + 1;
        final newRating =
            ((currentRating * totalReviews) + _selectedRating) / newTotal;

        await FirebaseService.vendors.doc(order.vendorId).update({
          'rating': double.parse(newRating.toStringAsFixed(1)),
          'totalReviews': newTotal,
        });
      }

      setState(() => _ratingSubmitted = true);
    } catch (e) {
      setState(() => _ratingSubmitted = true);
    }

    setState(() => _isSubmittingRating = false);
  }

  @override
  Widget build(BuildContext context) {
    final order = context.read<OrderProvider>().activeOrder;

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Delivery confirmed!',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(
                        color: AppColors.white,
                        fontSize: 28,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your gas has been delivered. Enjoy!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray400,
                        height: 1.5,
                      ),
                ),
                const SizedBox(height: 28),

                // ── RATING SECTION ────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppColors.white.withValues(alpha: 0.1)),
                  ),
                  child: _ratingSubmitted
                      ? Column(
                          children: [
                            const Icon(Icons.favorite_rounded,
                                color: AppColors.orange, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              'Thanks for your rating!',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: AppColors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your feedback helps other customers',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.gray400),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Text(
                              'Rate your delivery',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: AppColors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (order != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                order.vendorName,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.gray400),
                              ),
                            ],
                            const SizedBox(height: 16),
                            // Stars
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(5, (i) {
                                final star = i + 1;
                                return GestureDetector(
                                  onTap: () => setState(
                                      () => _selectedRating = star),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 150),
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      star <= _selectedRating
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: star <= _selectedRating
                                          ? AppColors.warning
                                          : AppColors.gray600,
                                      size: 40,
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _selectedRating == 0
                                  ? 'Tap to rate'
                                  : _selectedRating == 1
                                      ? 'Poor'
                                      : _selectedRating == 2
                                          ? 'Fair'
                                          : _selectedRating == 3
                                              ? 'Good'
                                              : _selectedRating == 4
                                                  ? 'Great'
                                                  : 'Excellent!',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: _selectedRating == 0
                                        ? AppColors.gray600
                                        : AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _selectedRating == 0 ||
                                      _isSubmittingRating
                                  ? null
                                  : _submitRating,
                              style: ElevatedButton.styleFrom(
                                minimumSize:
                                    const Size(double.infinity, 48),
                              ),
                              child: _isSubmittingRating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.white),
                                    )
                                  : const Text('Submit rating'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _ratingSubmitted = true),
                              child: Text('Skip',
                                  style: TextStyle(
                                      color: AppColors.gray600)),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => context.go('/home'),
                  child: const Text('Back to home'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}