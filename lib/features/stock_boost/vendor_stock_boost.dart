// lib/features/stock_boost/vendor_stock_boost.dart
//
// MobiGas vendor app — "Stock boost" as a REFERRAL surface.
// The app only introduces the vendor to a finance partner. It carries NO loan
// mechanics, NO agreement, NO ledger, NO credit language. Tapping "Request"
// is the vendor's consent to be referred; everything else happens off-app
// between the vendor and the bank.
//
// Two states:
//   QUALIFIED  — stockBoostEligibility/{vendorId}.eligible == true → request CTA
//   BUILDING   — not yet qualified → progress card, so the vendor knows the
//                surface exists and that on-platform selling is the path to
//                it. Deliberately makes NO promise that hitting the numbers
//                produces an introduction — MobiGas introduces, the partner
//                decides. "Unlock" is avoided for exactly that reason.
//
// Reads:  vendor_stats_alltime/{vendorId}  (progress — the LIVE stats schema,
//                                           written by onOrderStatusChange)
//         stockBoostEligibility/{vendorId} (qualified to be referred?)
//         financingReferrals               (their latest referral status)
// Writes: none directly — requesting calls the requestStockBoost function.
//
// !! THRESHOLDS MIRROR functions/src/stockBoost.ts. If TENURE_DAYS /
// !! MIN_LIFETIME_KES / ELIGIBLE_COUNTRIES change there, change them here, or
// !! the progress card will disagree with the server and the vendor will sit
// !! at "100%" while staying locked.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:mobigas/core/config/currency.dart';

// ---- brand ----
const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);
const _green = Color(0xFF16A34A);

// ---- server-mirrored tunables (functions/src/stockBoost.ts) ----
const _kEligibleCountries = {'KE'};
const _kTenureDays = 90;
const _kMinLifetimeKes = 150000.0;

// ---------------------------------------------------------------------------
// Streams
// ---------------------------------------------------------------------------

/// The vendor's own aggregate stats. Doc id is the auth uid.
/// Fields (written by onOrderStatusChange / backfillVendorStats):
///   cashSales   — sum of gasPrice on delivered CASH orders
///   creditSales — sum of gasPrice on delivered NON-cash orders (mobile money;
///                 "credit" here means "not cash" — nothing to do with lending)
///   fulfilled   — delivered count
///   firstDeliveredAt / lastSaleAt — added for the tenure + recency gates
Stream<DocumentSnapshot<Map<String, dynamic>>> vendorStatsStream(String vendorId) =>
    FirebaseFirestore.instance
        .collection('vendor_stats_alltime')
        .doc(vendorId)
        .snapshots();

Stream<DocumentSnapshot<Map<String, dynamic>>> eligibilityStream(String vendorId) =>
    FirebaseFirestore.instance
        .collection('stockBoostEligibility')
        .doc(vendorId)
        .snapshots();

/// Queried by ownerUid, NOT vendorId — the firestore.rules read condition
/// tests ownerUid, and a list query is rejected wholesale unless its
/// constraints prove every returned doc satisfies the rule. Same value in
/// practice (vendor docs are keyed by uid); different field, and the query
/// must match the rule.
Stream<QuerySnapshot<Map<String, dynamic>>> latestReferralStream(String vendorId) =>
    FirebaseFirestore.instance
        .collection('financingReferrals')
        .where('ownerUid', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();

const _openStatuses = {'referred', 'contacted', 'onboarded'};

double _lifetimeSales(Map<String, dynamic>? stats) =>
    ((stats?['cashSales'] ?? 0).toDouble()) +
    ((stats?['creditSales'] ?? 0).toDouble());

// ---------------------------------------------------------------------------
// Card
//
// vendorData is the map VendorHomeScreen already holds — used only for the
// country gate, so this widget adds no vendors/ read of its own.
// ---------------------------------------------------------------------------
class StockBoostCard extends StatelessWidget {
  final String vendorId;
  final Map<String, dynamic>? vendorData;

  const StockBoostCard({
    super.key,
    required this.vendorId,
    required this.vendorData,
  });

  @override
  Widget build(BuildContext context) {
    // VendorHomeScreen builds all four tabs eagerly (IndexedStack), and its
    // 10s auth backstop can clear the spinner with an empty uid. .doc('')
    // throws — an empty document path is invalid.
    if (vendorId.isEmpty) return const SizedBox.shrink();

    // Mirrors ELIGIBLE_COUNTRIES server-side. UG/TZ vendors see nothing at
    // all, rather than progress toward something not offered to them.
    final country = (vendorData?['country'] as String?) ?? 'KE';
    if (!_kEligibleCountries.contains(country)) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: eligibilityStream(vendorId),
      builder: (context, eligSnap) {
        // A permission-denied here (missing rule) would otherwise render as
        // nothing at all, forever, with no error anywhere. Fail loud in debug.
        if (eligSnap.hasError) {
          debugPrint('StockBoost: eligibility read failed — ${eligSnap.error}');
          return const SizedBox.shrink();
        }

        final elig = eligSnap.data?.data();
        final isQualified = elig != null && elig['eligible'] == true;

        if (!isQualified) {
          // No eligibility doc yet (the nightly sweep hasn't picked them up),
          // or the sweep ran and said no. Either way: show progress.
          return _buildingCard(context, country);
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: latestReferralStream(vendorId),
          builder: (context, refSnap) {
            if (refSnap.hasError) {
              debugPrint('StockBoost: referral read failed — ${refSnap.error}');
            }
            final latest = (refSnap.data?.docs.isNotEmpty ?? false)
                ? refSnap.data!.docs.first.data()
                : null;
            final isOpen =
                latest != null && _openStatuses.contains(latest['status']);
            return _qualifiedCard(context, isOpen);
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // BUILDING — the vendor doesn't qualify yet.
  //
  // Copy discipline: tells the vendor the surface EXISTS and that steady
  // on-platform selling is the path to it. Must not imply that reaching the
  // numbers entitles them to an introduction, or that an introduction produces
  // stock. True on day 1 with zero partner banks signed; still true on day 90
  // with two.
  // -------------------------------------------------------------------------
  Widget _buildingCard(BuildContext context, String country) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: vendorStatsStream(vendorId),
      builder: (context, statsSnap) {
        if (statsSnap.hasError) {
          debugPrint('StockBoost: stats read failed — ${statsSnap.error}');
          return const SizedBox.shrink();
        }

        final stats = statsSnap.data?.data();
        final lifetime = _lifetimeSales(stats);

        final firstDelivered = stats?['firstDeliveredAt'];
        final firstDate =
            firstDelivered is Timestamp ? firstDelivered.toDate() : null;

        final tenureDays =
            firstDate == null ? 0 : DateTime.now().difference(firstDate).inDays;
        final tenureMet = tenureDays >= _kTenureDays;
        final volumeMet = lifetime >= _kMinLifetimeKes;

        // No delivered sales yet — no meaningful progress to show, and they
        // have more pressing things to do than think about stock financing.
        final noSalesYet = firstDate == null && lifetime <= 0;

        final volumeFraction =
            (lifetime / _kMinLifetimeKes).clamp(0.0, 1.0).toDouble();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _navy.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      color: _navy.withValues(alpha: 0.55), size: 20),
                  const SizedBox(width: 8),
                  const Text('Grow your stock',
                      style: TextStyle(
                          color: _navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                noSalesYet
                    ? 'Vendors who sell steadily on MobiGas can be introduced to '
                        'our finance partner to help them carry more stock. It '
                        'starts with your first deliveries.'
                    : 'Vendors who sell steadily on MobiGas can be introduced to '
                        'our finance partner to help them carry more stock. '
                        'Here\'s where you are.',
                style: const TextStyle(
                    color: Colors.black54, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),

              // Volume — the bar, because this is the part selling moves.
              _progressRow(
                label: 'Sales through MobiGas',
                valueText: '${Currency.formatFor(country, lifetime)} '
                    'of ${Currency.formatFor(country, _kMinLifetimeKes)}',
                fraction: volumeFraction,
                met: volumeMet,
              ),
              const SizedBox(height: 14),

              // Tenure — a checkmark, not a bar. Waiting isn't an action, and
              // a progress bar would imply it is.
              _checkRow(
                met: tenureMet,
                text: tenureMet
                    ? 'Selling for over $_kTenureDays days'
                    : noSalesYet
                        ? 'Selling for $_kTenureDays days'
                        : '$tenureDays of $_kTenureDays days selling',
              ),

              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Updated once a day. Meeting these doesn\'t guarantee an '
                  'introduction — our finance partner decides who they take on, '
                  'and sets their own terms.',
                  style: TextStyle(
                      color: Colors.black.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.35),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _progressRow({
    required String label,
    required String valueText,
    required double fraction,
    required bool met,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: _navy, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (met) const Icon(Icons.check_circle, color: _green, size: 16),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: _navy.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(met ? _green : _orange),
          ),
        ),
        const SizedBox(height: 5),
        Text(valueText,
            style: const TextStyle(color: Colors.black54, fontSize: 11)),
      ],
    );
  }

  Widget _checkRow({required bool met, required String text}) {
    return Row(
      children: [
        Icon(
          met ? Icons.check_circle : Icons.schedule_rounded,
          size: 16,
          color: met ? _green : Colors.black26,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: met ? _navy : Colors.black54,
                  fontSize: 12,
                  fontWeight: met ? FontWeight.w600 : FontWeight.w400)),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // QUALIFIED — request CTA, or "partner will contact you" once open.
  // -------------------------------------------------------------------------
  Widget _qualifiedCard(BuildContext context, bool isOpen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, Color(0xFF16255A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: _orange, size: 20),
              const SizedBox(width: 8),
              const Text('Grow your stock',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isOpen
                ? 'Request sent. Our finance partner will contact you directly '
                    'to set you up.'
                : 'Because you sell steadily on MobiGas, we can connect you with '
                    'our finance partner to boost your stock. They\'ll reach out '
                    'to you directly.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4),
          ),
          const SizedBox(height: 16),
          if (isOpen)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Requested — partner will be in touch',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13)),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => RequestStockBoostSheet(vendorId: vendorId),
                ),
                child: const Text('Request stock boost',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Request sheet — optional "how much stock" hint, then a single tap that acts
// as consent to be referred. No credit language, no checkbox.
// ---------------------------------------------------------------------------
class RequestStockBoostSheet extends StatefulWidget {
  final String vendorId;
  const RequestStockBoostSheet({super.key, required this.vendorId});

  @override
  State<RequestStockBoostSheet> createState() => _RequestStockBoostSheetState();
}

class _RequestStockBoostSheetState extends State<RequestStockBoostSheet> {
  final _ctrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final hint = double.tryParse(_ctrl.text.trim());
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('requestStockBoost');
      await fn.call({
        'vendorId': widget.vendorId,
        if (hint != null && hint > 0) 'desiredAmountKes': hint,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Request sent. Our finance partner will contact you directly.'),
          backgroundColor: _navy,
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = switch (e.code) {
            'failed-precondition' =>
              e.message ?? 'You\'re not eligible right now.',
            'permission-denied' => 'This account can\'t make this request.',
            // Callable not deployed / renamed. Without this arm the vendor
            // sees a generic "something went wrong" and retries forever.
            'not-found' => 'This isn\'t available yet. Please try again later.',
            'unauthenticated' => 'Please sign in again.',
            _ => 'Something went wrong. Try again.',
          });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Request stock boost',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 20, color: _navy)),
          const SizedBox(height: 6),
          const Text(
            'We\'ll share your MobiGas trading history with our finance partner '
            'so they can set you up. They\'ll contact you directly — everything '
            'is arranged with them.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: 'KES ',
              labelText: 'How much stock do you want? (optional)',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _orange, width: 2)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Send request',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
              'By requesting, you agree to share your trading history with our '
              'finance partner.',
              style:
                  TextStyle(color: Colors.black45, fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }
}