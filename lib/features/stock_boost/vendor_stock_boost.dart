// lib/features/stock_boost/vendor_stock_boost.dart
//
// MobiGas vendor app — "Stock boost" as a REFERRAL surface.
// The app only introduces the vendor to a finance partner. It carries NO loan
// mechanics, NO agreement, NO ledger, NO credit language. Tapping "Request"
// is the vendor's consent to be referred; everything else happens off-app
// between the vendor and the bank.
//
// Reads:  stockBoostEligibility/{vendorId}   (are they qualified to be referred)
//         financingReferrals (their latest referral status)
// Writes: none directly — requesting calls the requestStockBoost function.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

// ---- brand ----
const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);

String _kes(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return 'KES ${b.toString()}';
}

// ---------------------------------------------------------------------------
// Streams
// ---------------------------------------------------------------------------
Stream<DocumentSnapshot<Map<String, dynamic>>> eligibilityStream(String vendorId) =>
    FirebaseFirestore.instance.collection('stockBoostEligibility').doc(vendorId).snapshots();

Stream<QuerySnapshot<Map<String, dynamic>>> latestReferralStream(String vendorId) =>
    FirebaseFirestore.instance
        .collection('financingReferrals')
        .where('vendorId', isEqualTo: vendorId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();

const _openStatuses = {'referred', 'contacted', 'onboarded'};

// ---------------------------------------------------------------------------
// Card — renders only for eligible (actively-selling) vendors. Shows either a
// "request" CTA, or a "partner will contact you" status once referred.
// ---------------------------------------------------------------------------
class StockBoostCard extends StatelessWidget {
  final String vendorId;
  const StockBoostCard({super.key, required this.vendorId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: eligibilityStream(vendorId),
      builder: (context, eligSnap) {
        final elig = eligSnap.data?.data();
        if (elig == null || elig['eligible'] != true) {
          // Non-KE and not-yet-qualified vendors have no eligibility doc → hidden.
          return const SizedBox.shrink();
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: latestReferralStream(vendorId),
          builder: (context, refSnap) {
            final latest = (refSnap.data?.docs.isNotEmpty ?? false)
                ? refSnap.data!.docs.first.data()
                : null;
            final isOpen = latest != null && _openStatuses.contains(latest['status']);

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
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isOpen
                        ? 'Request sent. Our finance partner will contact you directly to set you up.'
                        : 'Because you sell steadily on MobiGas, we can connect you with our '
                          'finance partner to boost your stock. They\'ll reach out to you directly.',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  if (isOpen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text('Requested — partner will be in touch',
                              style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          builder: (_) => RequestStockBoostSheet(vendorId: vendorId),
                        ),
                        child: const Text('Request stock boost',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
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

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
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
          content: Text('Request sent. Our finance partner will contact you directly.'),
          backgroundColor: _navy,
        ));
      }
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = switch (e.code) {
            'failed-precondition' => e.message ?? 'You\'re not eligible right now.',
            'permission-denied' => 'This account can\'t make this request.',
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
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _navy)),
          const SizedBox(height: 6),
          const Text(
            'We\'ll share your MobiGas trading history with our finance partner so they '
            'can set you up. They\'ll contact you directly — everything is arranged with them.',
            style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: 'KES ',
              labelText: 'How much stock do you want? (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _orange, width: 2)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send request', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Text('By requesting, you agree to share your trading history with our finance partner.',
              style: TextStyle(color: Colors.black45, fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }
}
