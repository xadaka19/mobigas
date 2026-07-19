// lib/features/stock_boost/vendor_pezesha_stock_loan.dart
//
// Vendor-side Pezesha stock loan — sits in the same Earnings-tab slot
// as StockBoostCard (vendor_stock_boost.dart), same restrained visual
// pattern (no number until requested, no partner claim beyond what's
// true). This is the Pezesha-specific path; StockBoostCard's referral
// flow stays in place as the fallback for any country/vendor Pezesha
// doesn't cover.
//
// SWITCHING BETWEEN THEM: read platform_settings/financing once (same
// pattern as platform_settings/stock_boost) and render THIS widget
// when provider == 'pezesha' and the vendor's country is covered,
// otherwise render the existing StockBoostCard. Wiring that switch is
// a one-line change wherever StockBoostCard is currently placed in
// vendor_home_screen.dart's Earnings tab — not included here since it
// depends on how you want to name/structure that config doc.
//
// Vendor is BOTH the borrower (pezesha_id) and the disbursement
// target (their own till/paybill) — see applyPezeshaLoan in
// functions/src/pezesha.ts.

import 'package:flutter/material.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/services/pezesha_service.dart';

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
  @override
  Widget build(BuildContext context) {
    if (widget.vendorId.isEmpty) return const SizedBox.shrink();
    final country = (widget.vendorData?['country'] as String?) ?? 'KE';

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
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20))),
                builder: (_) => _StockLoanSheet(country: country),
              ),
              child: const Text('Check your limit',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SheetState { checking, unavailable, available, applying, success, error }

class _StockLoanSheet extends StatefulWidget {
  final String country;
  const _StockLoanSheet({required this.country});

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

  Future<void> _checkLimit() async {
    setState(() => _state = _SheetState.checking);
    try {
      await PezeshaService.ensureRegistered(ownerType: 'vendor');
      final offer = await PezeshaService.getLoanOffer(ownerType: 'vendor');
      if (!mounted) return;
      if (offer == null) {
        setState(() {
          _state = _SheetState.unavailable;
          _message =
              'No stock loan available yet — keep fulfilling orders '
              'through MobiGas to build your record.';
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
        if (mounted) Navigator.of(context).pop();
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Stock loan',
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 20, color: _navy)),
          const SizedBox(height: 14),
          _buildBody(),
        ],
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
        return Text(_message ?? '',
            style: const TextStyle(
                color: Colors.black54, fontSize: 13, height: 1.4));
      case _SheetState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_message ?? 'Something went wrong.',
                style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(onPressed: _checkLimit, child: const Text('Retry')),
          ],
        );
      case _SheetState.success:
        return const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text('Loan approved — funds are on their way to your '
                  'account.'),
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
