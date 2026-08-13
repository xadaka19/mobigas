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
// ── FEE LOCK ────────────────────────────────────────────────────────
// A fee-locked vendor (VendorLock.isLocked) can't take NEW financing —
// the server refuses applyPezeshaLoan's vendor_stock branch. So when
// locked, "Check your limit" and "Improve my limit" are replaced by a
// notice pointing at the fees banner. "View my loans" stays available
// even when locked: the Play lending-visibility requirement is about
// EXISTING loans, and a fee lock must not hide a loan a vendor already
// has.
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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/access/vendor_lock.dart';
import 'package:mobigas/core/services/pezesha_service.dart';
import 'package:mobigas/core/services/supplier_service.dart';
import 'package:mobigas/features/bnpl/pezesha_loan_status_screen.dart';
import 'package:mobigas/features/bnpl/pezesha_statement_upload_screen.dart';

const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);

// At/above this amount (per country) attaching the supplier's invoice
// to a stock-loan order is REQUIRED; below it, optional. Mirrored
// server-side in stockInvoiceThresholdFor() in functions/src/pezesha.ts
// — keep the two maps in sync. UG/TZ are placeholders to confirm.
const Map<String, num> _stockInvoiceThresholds = {
  'KE': 50000,
  'UG': 1500000,
  'TZ': 1000000,
};

num _stockInvoiceThresholdFor(String country) =>
    _stockInvoiceThresholds[country.toUpperCase()] ?? 50000;

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

  bool get _locked =>
      VendorLock.isLocked(widget.vendorData ?? const <String, dynamic>{});

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
    final locked = _locked;

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
          Text(
            locked
                ? 'Restocking finance through our partner Pezesha. Clear '
                    'your platform fees to unlock it.'
                : 'Check your limit and restock through our finance '
                    'partner Pezesha — funds go straight to your chosen '
                    'supplier.',
            style: const TextStyle(
                color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (locked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      color: Colors.white70, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Clear your platform fees to unlock stock financing.',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, height: 1.3),
                    ),
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
                onPressed: _openLimitSheet,
                child: const Text('Check your limit',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Always available — even when fee-locked — so a vendor can
              // always see an existing loan's status (Play visibility).
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
              // "Improve my limit" is a NEW-borrowing action — hidden
              // while locked, same as the main CTA above.
              if (!locked) ...[
                const SizedBox(width: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: _openStatementUpload,
                  child: const Text('Improve my limit',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum _SheetState { checking, unavailable, available, success, error }

// The `available` state is a short wizard: pick the amount, then the
// supplier + how they're paid, then confirm and apply.
enum _Step { amount, supplier, confirm }

/// Pops `true` to ask the CARD to open the statement flow — see the
/// "who owns the flow" note in the file header. It never pushes that
/// screen itself. Pops `false` once an application has completed.
class _StockLoanSheet extends StatefulWidget {
  final String country;
  final String? initialPhone;

  const _StockLoanSheet({required this.country, this.initialPhone});

  @override
  State<_StockLoanSheet> createState() => _StockLoanSheetState();
}

class _StockLoanSheetState extends State<_StockLoanSheet> {
  _SheetState _state = _SheetState.checking;
  _Step _step = _Step.amount;

  PezeshaLoanOffer? _offer;
  String? _message; // inline validation / error text
  final _amountCtrl = TextEditingController();

  // Supplier selection.
  bool _loadingSuppliers = false;
  String? _supplierError;
  List<Supplier> _suppliers = const [];
  Supplier? _supplier;
  SupplierPaymentMethod? _method;

  bool _applying = false;

  // Invoice (productive-use evidence): required at/above the
  // per-country threshold, optional below.
  String? _invoicePath;
  bool _invoiceUploading = false;

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
          _message = 'Pezesha needs your M-Pesa statement to work out '
              'your limit. It takes about a minute.';
        });
      } else {
        setState(() {
          _state = _SheetState.available;
          _step = _Step.amount;
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

  double? get _amount {
    final v = double.tryParse(_amountCtrl.text.trim());
    if (v == null || v <= 0) return null;
    return v;
  }

  // amount -> supplier: validate the amount, then load the directory.
  Future<void> _goToSupplier() async {
    final offer = _offer;
    if (offer == null) return;
    final amount = _amount;
    if (amount == null || amount > offer.amount) {
      setState(() => _message =
          'Enter an amount up to your limit of '
          '${Currency.formatFor(widget.country, offer.amount)}.');
      return;
    }
    setState(() {
      _message = null;
      _step = _Step.supplier;
    });
    if (_suppliers.isEmpty) await _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _loadingSuppliers = true;
      _supplierError = null;
    });
    try {
      final list = await SupplierService.forCountry(widget.country);
      if (!mounted) return;
      setState(() {
        _suppliers = list;
        _loadingSuppliers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSuppliers = false;
        _supplierError =
            'Could not load suppliers. Check your connection and try again.';
      });
    }
  }

  void _selectSupplier(Supplier s) {
    final payable = s.paymentMethods.where((m) => m.isPayable).toList();
    setState(() {
      _supplier = s;
      // Auto-select when there's exactly one payable method.
      _method = payable.length == 1 ? payable.first : null;
      _message = null;
    });
  }

  void _goToConfirm() {
    if (_supplier == null || _method == null) {
      setState(() => _message = 'Choose a supplier and how they\'re paid.');
      return;
    }
    setState(() {
      _message = null;
      _step = _Step.confirm;
    });
  }

  bool get _invoiceRequired =>
      (_amount ?? 0) >= _stockInvoiceThresholdFor(widget.country);

  Future<void> _pickInvoice() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 2000,
      );
      if (picked == null) return;
      setState(() {
        _invoiceUploading = true;
        _message = null;
      });
      final path =
          await PezeshaService.uploadInvoiceFile(file: File(picked.path));
      if (!mounted) return;
      setState(() {
        _invoicePath = path;
        _invoiceUploading = false;
      });
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _invoiceUploading = false;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _invoiceUploading = false;
        _message = 'Could not attach the invoice. Try again.';
      });
    }
  }

  Future<void> _apply() async {
    final offer = _offer;
    final supplier = _supplier;
    final method = _method;
    final amount = _amount;
    if (offer == null ||
        supplier == null ||
        method == null ||
        amount == null ||
        amount > offer.amount) {
      return;
    }
    if (_invoiceRequired && _invoicePath == null) {
      setState(() => _message =
          'Attach the supplier invoice to place an order this size.');
      return;
    }
    setState(() {
      _applying = true;
      _message = null;
    });
    try {
      await PezeshaService.applyLoan(
        loanType: 'vendor_stock',
        amount: amount,
        supplierId: supplier.id,
        paymentMethodId: method.id,
        invoicePath: _invoicePath,
      );
      if (!mounted) return;
      setState(() {
        _applying = false;
        _state = _SheetState.success;
      });
      Future.delayed(const Duration(seconds: 2), () {
        // pop(false), not pop(true) — a completed application must not
        // read as "open the statement flow" to the card above.
        if (mounted) Navigator.of(context).pop(false);
      });
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _applying = false;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _applying = false;
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
        return _buildUnavailable();
      case _SheetState.error:
        return _buildError();
      case _SheetState.success:
        return _buildSuccess();
      case _SheetState.available:
        switch (_step) {
          case _Step.amount:
            return _buildAmountStep();
          case _Step.supplier:
            return _buildSupplierStep();
          case _Step.confirm:
            return _buildConfirmStep();
        }
    }
  }

  Widget _radioDot(bool selected) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: selected ? _orange : Colors.black38, width: 2),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration:
                    const BoxDecoration(shape: BoxShape.circle, color: _orange),
              ),
            )
          : null,
    );
  }

  Widget _buildUnavailable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_message ?? '',
            style: const TextStyle(
                color: Colors.black54, fontSize: 13, height: 1.4)),
        const SizedBox(height: 8),
        const Text(
          'You\'ll need your M-Pesa statement as a PDF (6 or 12 '
          'months) and the password Safaricom sent with it — '
          'request both on *334#.',
          style: TextStyle(color: Colors.black45, fontSize: 12, height: 1.4),
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
  }

  Widget _buildError() {
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
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green),
            SizedBox(width: 8),
            Expanded(
              child: Text('Order placed — Pezesha is paying your supplier '
                  'directly.'),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  // A small "< Back   Step x of 3" row atop the supplier/confirm steps so
  // the wizard reads as a sequence, not three loose screens.
  Widget _stepBar(int index, VoidCallback onBack) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          InkWell(
            onTap: _applying ? null : onBack,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Row(
                children: [
                  Icon(Icons.chevron_left_rounded, size: 18, color: _navy),
                  Text('Back',
                      style: TextStyle(
                          color: _navy,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text('Step $index of 3',
              style: const TextStyle(color: Colors.black38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildAmountStep() {
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
            onPressed: _goToSupplier,
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Next: choose supplier'),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              foregroundColor: _orange,
            ),
            onPressed: _requestStatementUpload,
            child: const Text('Improve my limit',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _buildSupplierStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBar(2, () => setState(() => _step = _Step.amount)),
        if (_loadingSuppliers)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: _orange),
            ),
          )
        else if (_supplierError != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_supplierError!,
                  style: const TextStyle(color: Colors.black87, fontSize: 13)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loadSuppliers,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _orange,
                  side: const BorderSide(color: _orange),
                ),
                child: const Text('Retry'),
              ),
            ],
          )
        else if (_suppliers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No approved suppliers for your area yet. Please check back '
              'soon.',
              style: TextStyle(color: Colors.black54, fontSize: 13),
            ),
          )
        else ...[
          const Text('Where are you restocking from?',
              style: TextStyle(
                  color: _navy, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suppliers.map(_buildSupplierTile).toList(),
              ),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _goToConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Next: review'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSupplierTile(Supplier s) {
    final selected = _supplier?.id == s.id;
    final payable = s.paymentMethods.where((m) => m.isPayable).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
            color: selected ? _orange : Colors.black12,
            width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _selectSupplier(s),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _radioDot(selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _navy)),
                        if (s.brands.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(s.brands.join(', '),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Payment method: shown only once the supplier is selected.
          // A single method is auto-picked and shown as a plain line; two
          // or more are offered as a choice.
          if (selected && payable.length == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Paid via ${payable.first.label}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            ),
          if (selected && payable.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: payable.map((m) {
                  final msel = _method?.id == m.id;
                  return InkWell(
                    onTap: () => setState(() => _method = m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          _radioDot(msel),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(m.label,
                                style: const TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConfirmStep() {
    final offer = _offer!;
    final supplier = _supplier!;
    final method = _method!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepBar(3, () => setState(() => _step = _Step.supplier)),
        _confirmRow('Amount', Currency.formatFor(widget.country, _amount!)),
        _confirmRow('Supplier', supplier.name),
        _confirmRow('Paid via', method.label),
        const SizedBox(height: 12),
        _buildInvoiceSection(),
        const SizedBox(height: 8),
        Text(
          'Pezesha pays ${supplier.name} directly for your stock. You repay '
          'Pezesha over ${offer.duration} days on the schedule they '
          'provide — MobiGas does not collect repayments.',
          style: const TextStyle(
              color: Colors.black45, fontSize: 11, height: 1.35),
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
            onPressed: (_applying || _invoiceUploading) ? null : _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: _orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _applying
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Place order'),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceSection() {
    final required = _invoiceRequired;
    final attached = _invoicePath != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 18, color: _navy),
              const SizedBox(width: 8),
              const Text('Supplier invoice',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _navy)),
              const SizedBox(width: 6),
              Text(required ? '(required)' : '(optional)',
                  style: TextStyle(
                      fontSize: 12,
                      color: required ? Colors.red : Colors.black45)),
            ],
          ),
          const SizedBox(height: 8),
          if (attached)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: Colors.green),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Invoice attached',
                      style:
                          TextStyle(fontSize: 13, color: Colors.black87)),
                ),
                TextButton(
                  onPressed: _invoiceUploading ? null : _pickInvoice,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    foregroundColor: _orange,
                  ),
                  child: const Text('Replace',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _invoiceUploading ? null : _pickInvoice,
              icon: _invoiceUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _orange),
                    )
                  : const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(
                  _invoiceUploading ? 'Uploading…' : 'Attach a photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: const BorderSide(color: _orange),
              ),
            ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: _navy, fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
