// lib/features/stock_boost/vendor_stock_boost.dart
//
// MobiGas vendor app — "Stock boost" as a REFERRAL surface.
//
// MobiGas decides NOTHING here. No eligibility threshold, no qualifying
// amount, no gate — the finance partner sees the trading snapshot and
// makes every decision. MobiGas introduces; it does not pre-screen,
// underwrite, advise, disburse, or collect.
//
// LAYOUT NOTE: this card renders on the Earnings tab, directly under the
// big "Total earnings" figure — which derives from the SAME gasPrice sum
// as the trading record. The card therefore deliberately shows NO number
// of its own (it would duplicate the header pixel-for-pixel, and any
// one-delivery lag between the live aggregate and vendor_stats_alltime
// would read as a bug). The concrete numbers appear exactly once beyond
// the header: inside the request sheet, as a preview of the payload the
// partner receives — which is what informed consent should look like.
//
// Remote switch (no app release needed):
//   platform_settings/stock_boost { active: bool, countries: [..] }
//     active=false → reframe copy only, no button, no partner claim
//     active=true  → request CTA; sheet shows the record to be shared
//
// Reads:  vendor_stats_alltime/{vendorId}   (snapshot for the sheet)
//         platform_settings/stock_boost     (is the program open, where)
//         financingReferrals                (their latest referral status)
// Writes: none — requesting calls the requestStockBoost function, and the
//         server re-checks the active flag so a patched client gains nothing.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:mobigas/core/config/currency.dart';

// ---- brand ----
const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);

// ---------------------------------------------------------------------------
// Streams
// ---------------------------------------------------------------------------

/// Program switch. Flipped from the admin side when a finance partner is
/// signed — needs a client read rule:
///   match /platform_settings/stock_boost {
///     allow read: if request.auth != null;
///     allow write: if false;
///   }
Stream<DocumentSnapshot<Map<String, dynamic>>> stockBoostConfigStream() =>
    FirebaseFirestore.instance
        .collection('platform_settings')
        .doc('stock_boost')
        .snapshots();

/// The vendor's own aggregate. Doc id is the auth uid.
/// cashSales + creditSales = lifetime delivered sales (both sum
/// order.gasPrice; creditSales is a legacy non-cash bucket, always 0
/// since PaymentMethod.credit was removed — summed anyway so the total
/// stays correct if it's ever revived).
Stream<DocumentSnapshot<Map<String, dynamic>>> vendorStatsStream(String vendorId) =>
    FirebaseFirestore.instance
        .collection('vendor_stats_alltime')
        .doc(vendorId)
        .snapshots();

/// Queried by ownerUid, NOT vendorId — the firestore.rules read condition
/// tests ownerUid, and a list query is rejected wholesale unless its
/// constraints prove every returned doc satisfies the rule.
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
    // 10s auth backstop can clear the spinner with an empty uid — .doc('')
    // throws on an empty document path.
    if (vendorId.isEmpty) return const SizedBox.shrink();

    final country = (vendorData?['country'] as String?) ?? 'KE';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stockBoostConfigStream(),
      builder: (context, cfgSnap) {
        if (cfgSnap.hasError) {
          debugPrint('StockBoost: config read failed — ${cfgSnap.error}');
          return const SizedBox.shrink();
        }
        final cfg = cfgSnap.data?.data();
        final programActive = cfg?['active'] == true;
        final programCountries =
            List<String>.from(cfg?['countries'] ?? const ['KE']);

        // Vendors outside the program's countries see nothing at all,
        // rather than copy framed around an unavailable thing.
        if (!programCountries.contains(country)) {
          return const SizedBox.shrink();
        }

        if (!programActive) {
          // No partner signed yet. Reframe the earnings figure above as a
          // trading record — WITHOUT repeating it, and without claiming a
          // partner exists. Every sentence stays true with zero banks signed.
          return _recordCard(context);
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: vendorStatsStream(vendorId),
          builder: (context, statsSnap) {
            if (statsSnap.hasError) {
              debugPrint('StockBoost: stats read failed — ${statsSnap.error}');
              return const SizedBox.shrink();
            }
            final stats = statsSnap.data?.data();

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: latestReferralStream(vendorId),
              builder: (context, refSnap) {
                if (refSnap.hasError) {
                  debugPrint(
                      'StockBoost: referral read failed — ${refSnap.error}');
                }
                final latest = (refSnap.data?.docs.isNotEmpty ?? false)
                    ? refSnap.data!.docs.first.data()
                    : null;
                final isOpen = latest != null &&
                    _openStatuses.contains(latest['status']);
                return _activeCard(context, country, stats, isOpen);
              },
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Program not active — no partner claim, no button, and NO figure: the
  // earnings header directly above already shows the same number.
  // -------------------------------------------------------------------------
  Widget _recordCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(18),
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
              const Text('Your trading record',
                  style: TextStyle(
                      color: _navy, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Every shilling above is more than earnings — each delivery '
            'through MobiGas builds a verified sales record, the kind of '
            'trading history finance providers look at when offering stock '
            'financing to gas vendors.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Program active — request CTA, or "partner will contact you" once open.
  // Still no figure here; the sheet shows the exact record being shared.
  // -------------------------------------------------------------------------
  Widget _activeCard(BuildContext context, String country,
      Map<String, dynamic>? stats, bool isOpen) {
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
                    'to take it from there.'
                : 'Your sales record above can work for you. Request an '
                    'introduction to our finance partner for stock financing — '
                    'they review your record and contact you directly. They '
                    'make all decisions and set all terms.',
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
                  builder: (_) => RequestStockBoostSheet(
                    vendorId: vendorId,
                    country: country,
                    stats: stats,
                  ),
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
// Request sheet — shows the vendor the EXACT record that will be shared
// (this is the one place the concrete numbers appear beyond the earnings
// header), an optional "how much stock" hint, then a single tap that acts
// as consent. No credit language, no checkbox.
// ---------------------------------------------------------------------------
class RequestStockBoostSheet extends StatefulWidget {
  final String vendorId;
  final String country;
  final Map<String, dynamic>? stats;

  const RequestStockBoostSheet({
    super.key,
    required this.vendorId,
    required this.country,
    required this.stats,
  });

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

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String? get _sellingSince {
    final first = widget.stats?['firstDeliveredAt'];
    if (first is! Timestamp) return null;
    final d = first.toDate();
    return '${_months[d.month - 1]} ${d.year}';
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
            // Recent-activity floor or program-inactive — the server's
            // message says which.
            'failed-precondition' =>
              e.message ?? 'This request can\'t be sent right now.',
            'permission-denied' => 'This account can\'t make this request.',
            'not-found' => 'This isn\'t available yet. Please try again later.',
            'unauthenticated' => 'Please sign in again.',
            _ => 'Something went wrong. Try again.',
          });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _shareRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Text(value,
              style: const TextStyle(
                  color: _navy, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final lifetime = _lifetimeSales(widget.stats);
    final deliveries = (widget.stats?['fulfilled'] ?? 0) as num;
    final since = _sellingSince;

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
            'Our finance partner reviews your MobiGas sales record and '
            'contacts you directly. They make all decisions and set all '
            'terms — everything is arranged with them, off the app.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),

          // The exact payload preview — the consent line below points here.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What we\'ll share with them',
                    style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.4),
                        fontSize: 12)),
                const SizedBox(height: 6),
                _shareRow('Sales through MobiGas',
                    Currency.formatFor(widget.country, lifetime)),
                _shareRow('Deliveries completed', '$deliveries'),
                if (since != null) _shareRow('Selling since', since),
              ],
            ),
          ),
          const SizedBox(height: 14),

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
              'By requesting, you agree to share the record above with our '
              'finance partner.',
              style:
                  TextStyle(color: Colors.black45, fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }
}