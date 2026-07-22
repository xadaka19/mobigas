// lib/features/stock_boost/vendor_pezesha_stock_loan.dart
//
// Vendor-side Pezesha stock loan — sits in the same Earnings-tab slot
// as StockBoostCard (vendor_stock_boost.dart), same restrained visual
// pattern (no number until requested, no partner claim beyond what's
// true).
//
// Vendor is BOTH the borrower (pezesha_id) and the disbursement
// target (their own till/paybill) — see applyPezeshaLoan in
// functions/src/pezesha.ts.
//
// ── WHO OWNS THE FLOW ───────────────────────────────────────────────
// The CARD owns the sheet -> upload -> sheet cycle, not the sheet.
// The sheet can't run it: opening the upload screen means closing the
// sheet first (leaving a live modal behind a pushed route strands it
// there, stale, showing the old "no limit" answer), and once popped
// the sheet's State is gone — it can't reopen anything. So the sheet
// just pops `true` to say "the vendor wants the statement flow", and
// _openLimitSheet below drives it: reopen on a successful score, so a
// vendor who just got scored lands straight back on their new limit
// instead of hunting for "Check your limit" again.
//
// "View my loans" appears in TWO places, deliberately:
//  - On the card itself, standing, independent of the sheet — a
//    vendor with an existing loan shouldn't have to tap "Check your
//    limit" (which re-runs eligibility checking) just to see its
//    status. This is what satisfies the persistent-visibility
//    requirement flagged in pezesha_service.dart's getLoanHistory
//    comment (Google Play policy for lending-adjacent apps).
//  - In the success state of the sheet, for anyone who wants to jump
//    straight there right after applying — that sheet auto-closes 2s
//    after showing, so this is a bonus shortcut, not the only way in.

import 'package:flutter/material.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/services/pezesha_service.dart';
import 'package:mobigas/features/bnpl/pezesha_loan_status_screen.dart';
import 'package:mobigas/features/bnpl/pezesha_statement_upload_screen.dart';

const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);

class VendorPezeshaStockLoanCard extends StatefulWidget {
  final String vendorId;
  final Map<String, dynamic>? vendorData;

  const VendorPezeshaStockLoanCard({
    super.key,
    required this.vendorId,
    required this.vendorData,
  });

  @override
  State<VendorPezeshaStockLoanCard> createState() =>
      _VendorPezeshaStockLoanCardState();
}

class _VendorPezeshaStockLoanCardState
    extends State<VendorPezeshaStockLoanCard> {
  String get _country => (widget.vendorData?['country'] as String?) ?? 'KE';

  /// Contact number on file, pre-filled into the statement form so the
  /// vendor isn't retyping what MobiGas already knows. Deliberately
  /// `phone` (the contact line), NOT a payout number — an M-Pesa
  /// statement belongs to the line the statement was issued for.
  String? get _contactPhone {
    final phone = (widget.vendorData?['phone'] ?? '').toString().trim();
    return phone.isEmpty ? null : phone;
  }

  /// Opens the limit sheet and drives whatever it asks for next.
  ///
  /// The sheet pops `true` when the vendor chooses the statement flow.
  /// The upload screen in turn pops `true` only when scoring actually
  /// produced a limit — so reopening on that (and only that) puts them
  /// straight back on the new number, while a no-limit outcome leaves
  /// them on the upload screen's own "what usually helps" state rather
  /// than bouncing them into a sheet that would just repeat it.
  ///
  /// The recursion is the point: reopen -> "Improve my limit" again ->
  /// upload -> reopen, for as long as the vendor keeps going.
  Future<void> _openLimitSheet() async {
    final wantsUpload = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _StockLoanSheet(
        country: _country,
        initialPhone: _contactPhone,
      ),
    );
    if (!mounted || wantsUpload != true) return;
    await _openStatementUpload();
  }

  /// Pushes the statement flow, and drops back into the limit sheet if
  /// a limit came back. Also the card's own "Improve my limit" entry
  /// point, so that button behaves the same as the one inside the
  /// sheet.
  Future<void> _openStatementUpload() async {
    final gotLimit = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PezeshaStatementUploadScreen(
          ownerType: 'vendor',
          country: _country,
          initialPhone: _contactPhone,
        ),
      ),
    );
    if (!mounted || gotLimit != true) return;
    // Scored, and a limit came back — the sheet re-runs its own check
    // on open, so it lands on the new number.
    await _openLimitSheet();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.vendorId.isEmpty) return const SizedBox.shrink();
    final country = _country;

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
              const Text('Instant stock loan',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Check your limit and get funds sent straight to your account '
            'to restock — through our finance partner Pezesha.',
            style: TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
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
              onPressed: _openLimitSheet,
              child: const Text('Check your limit',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size(0, 36),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PezeshaLoanStatusScreen(
                      ownerType: 'vendor',
                      country: country,
                    ),
                  ),
                ),
                child: const Text('View my loans',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                  minimumSize: const Size(0, 36),
                ),
                onPressed: _openStatementUpload,
                child: const Text('Improve my limit',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _SheetState { checking, unavailable, available, applying, success, error }

/// Pops `true` to ask the CARD to open the statement flow — see the
/// "who owns the flow" note in the file header. It never pushes that
/// screen itself.
class _StockLoanSheet extends StatefulWidget {
  final String country;
  final String? initialPhone;

  const _StockLoanSheet({required this.country, this.initialPhone});

  @override
  State<_StockLoanSheet> createState() => _StockLoanSheetState();
}

class _StockLoanSheetState extends State<_StockLoanSheet> {
  _SheetState _state = _SheetState.checking;
  PezeshaLoanOffer? _offer;
  String? _message;
  final _amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLimit();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  /// Hands control back to the card, which closes this sheet, pushes
  /// the statement screen, and reopens a fresh sheet if a limit comes
  /// back.
  void _requestStatementUpload() => Navigator.of(context).pop(true);

  Future<void> _checkLimit() async {
    setState(() => _state = _SheetState.checking);
    try {
      await PezeshaService.ensureRegistered(ownerType: 'vendor');
      final offer = await PezeshaService.getLoanOffer(ownerType: 'vendor');
      if (!mounted) return;
      if (offer == null) {
        setState(() {
          _state = _SheetState.unavailable;
          // Leads with the action, not the refusal — see the matching
          // comment in customer_bnpl.dart. A vendor with no Pezesha
          // history gets "no limit" on their first check by default;
          // the statement is what changes that, so it goes first.
          _message = 'Pezesha needs your M-Pesa statement to work out '
              'your limit. It takes about a minute.';
        });
      } else {
        setState(() {
          _state = _SheetState.available;
          _offer = offer;
          _amountCtrl.text = offer.amount.toStringAsFixed(0);
        });
      }
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.error;
        _message = 'Could not check your limit. Try again.';
      });
    }
  }

  Future<void> _apply() async {
    final offer = _offer;
    if (offer == null) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0 || amount > offer.amount) {
      setState(() => _message =
          'Enter an amount up to your limit of '
          '${Currency.formatFor(widget.country, offer.amount)}.');
      return;
    }

    setState(() {
      _state = _SheetState.applying;
      _message = null;
    });
    try {
      await PezeshaService.applyLoan(
        loanType: 'vendor_stock',
        amount: amount,
      );
      if (!mounted) return;
      setState(() => _state = _SheetState.success);
      Future.delayed(const Duration(seconds: 2), () {
        // pop(false), not pop(true) — a completed application must not
        // read as "open the statement flow" to the card above.
        if (mounted) Navigator.of(context).pop(false);
      });
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.available;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _SheetState.available;
        _message = 'Could not submit your application. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grab handle so a short error/empty state reads as an
            // intentional sheet, not a stray box at the screen edge.
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text('Stock loan',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 20, color: _navy)),
            const SizedBox(height: 14),
            _buildBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _SheetState.checking:
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(color: _orange),
          ),
        );
      case _SheetState.unavailable:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_message ?? '',
                style: const TextStyle(
                    color: Colors.black54, fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            // What they'll need, before they tap — see the matching
            // comment in customer_bnpl.dart.
            const Text(
              'You\'ll need your M-Pesa statement as a PDF (6 or 12 '
              'months) and the password Safaricom sent with it — '
              'request both on *334#.',
              style:
                  TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _requestStatementUpload,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Upload my statement'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        );
      case _SheetState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_message ?? 'Something went wrong. Please try again.',
                style: const TextStyle(
                    color: Colors.black87, fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _checkLimit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _orange,
                  side: const BorderSide(color: _orange),
                ),
                child: const Text('Retry'),
              ),
            ),
          ],
        );
      case _SheetState.success:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Loan approved — funds are on their way to your '
                      'account.'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Bonus shortcut — the card itself has a standing "View my
            // loans" link that works whether or not this sheet was ever
            // opened, so this one is just convenience for anyone
            // already looking at this exact moment, before the sheet
            // auto-closes below.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  foregroundColor: _orange,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PezeshaLoanStatusScreen(
                      ownerType: 'vendor',
                      country: widget.country,
                    ),
                  ),
                ),
                child: const Text('View my loans',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        );
      case _SheetState.available:
      case _SheetState.applying:
        final offer = _offer!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You qualify for up to '
              '${Currency.formatFor(widget.country, offer.amount)}, '
              'repaid over ${offer.duration} days.',
              style: const TextStyle(color: _navy, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _amountCtrl,
              enabled: _state != _SheetState.applying,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'How much do you need?',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _state == _SheetState.applying ? null : _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _state == _SheetState.applying
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Apply now'),
              ),
            ),
            const SizedBox(height: 8),
            // A vendor who already has a limit may still want a bigger
            // one — the deck's flow (567 -> 570, 70,500 -> 78,500) is
            // exactly this case, not just the zero-limit one.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  foregroundColor: _orange,
                ),
                onPressed: _state == _SheetState.applying
                    ? null
                    : _requestStatementUpload,
                child: const Text('Improve my limit',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'You repay Pezesha directly according to the schedule they '
              'provide — MobiGas does not collect repayments.',
              style: TextStyle(color: Colors.black45, fontSize: 11, height: 1.3),
            ),
          ],
        );
    }
  }
}
