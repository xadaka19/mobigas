// lib/features/bnpl/customer_bnpl.dart
//
// Customer-side Pezesha BNPL — three pieces, same restrained pattern
// as vendor_stock_boost.dart's StockBoostCard: no number shown until
// the customer actually asks, no partner claim until there's
// something to claim.
//
//  1. BnplLimitCard — sits on the customer home screen. Shows nothing
//     until tapped; tapping registers (lazily, if needed) and checks
//     the limit. This is the "awareness" surface. Always forces a
//     fresh check (PezeshaService.getLoanOffer(forceRefresh: true))
//     since a tap here is an explicit, deliberate request to know
//     the current number — never serve a stale cached one here.
//
//  2. BnplCheckoutSection — sits in the checkout flow next to "Pay on
//     delivery". Resolves an offer itself (session cache first, a
//     fresh call if nothing's cached yet this session) and renders
//     nothing while resolving or if no offer is available — checkout
//     is the "decision" surface, not where someone should be
//     discovering BNPL exists for the first time, so it deliberately
//     does NOT call ensureRegistered: if the customer never opened
//     BnplLimitCard, getLoanOffer's failed-precondition ("not
//     registered") is swallowed the same as "not available" would
//     be, and checkout just shows "Pay on delivery" only.
//
//  3. BnplCheckoutOption — the actual selectable payment option once
//     an offer is known. Kept as its own widget (rather than folded
//     into the section) since a caller that already has a
//     freshly-fetched offer in hand can still render it directly.
//
// All three call PezeshaService (core/services/pezesha_service.dart).
// MobiGas never shows a repayment flow anywhere — Pezesha collects
// directly from the customer, off-app.

import 'package:flutter/material.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/services/pezesha_service.dart';
import 'package:mobigas/features/bnpl/pezesha_loan_status_screen.dart';

const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);

// ─────────────────────────────────────────────────────────────────
// 1. Home screen card
// ─────────────────────────────────────────────────────────────────
class BnplLimitCard extends StatefulWidget {
  final String country;

  const BnplLimitCard({super.key, required this.country});

  @override
  State<BnplLimitCard> createState() => _BnplLimitCardState();
}

enum _CardState { initial, checking, available, unavailable, error }

class _BnplLimitCardState extends State<BnplLimitCard> {
  _CardState _state = _CardState.initial;
  PezeshaLoanOffer? _offer;
  String? _message;

  Future<void> _checkLimit() async {
    setState(() {
      _state = _CardState.checking;
      _message = null;
    });
    try {
      await PezeshaService.ensureRegistered(ownerType: 'customer');
      // forceRefresh: true — an explicit tap on "Check my limit" is
      // exactly the moment to bypass the session cache and hit
      // Pezesha directly, not serve back whatever was cached earlier.
      final offer = await PezeshaService.getLoanOffer(
        ownerType: 'customer',
        forceRefresh: true,
      );
      if (!mounted) return;
      if (offer == null) {
        setState(() {
          _state = _CardState.unavailable;
          _message =
              'No BNPL limit available yet — keep ordering through MobiGas '
              'to build your record.';
        });
      } else {
        setState(() {
          _state = _CardState.available;
          _offer = offer;
        });
      }
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _CardState.error;
        _message = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _CardState.error;
        _message = 'Could not check your limit. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Icon(Icons.credit_card_outlined,
                  color: _navy.withValues(alpha: 0.55), size: 20),
              const SizedBox(width: 8),
              const Text('Pay later with BNPL',
                  style: TextStyle(
                      color: _navy, fontWeight: FontWeight.w700, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 8),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _CardState.initial:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Order gas now, pay in installments through our finance '
              'partner Pezesha. Check if you qualify.',
              style: TextStyle(color: Colors.black54, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _checkLimit,
              style: OutlinedButton.styleFrom(
                foregroundColor: _orange,
                side: const BorderSide(color: _orange),
              ),
              child: const Text('Check my limit'),
            ),
          ],
        );
      case _CardState.checking:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _orange),
          ),
        );
      case _CardState.available:
        final offer = _offer!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'re approved for up to '
              '${Currency.formatFor(widget.country, offer.amount)}.',
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Select "Pay with BNPL" at checkout on your next order.',
              style: TextStyle(color: Colors.black54, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 8),
            // Persistent visibility entry point — see
            // pezesha_loan_status_screen.dart's header comment for why
            // this exists (Google Play requirement for lending-adjacent
            // apps), not just a nice-to-have link.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: _orange,
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PezeshaLoanStatusScreen(
                      ownerType: 'customer',
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
      case _CardState.unavailable:
        return Text(_message ?? '',
            style: const TextStyle(
                color: Colors.black54, fontSize: 13, height: 1.4));
      case _CardState.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_message ?? 'Something went wrong.',
                style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(onPressed: _checkLimit, child: const Text('Retry')),
          ],
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// 2. Checkout wrapper — resolves an offer before rendering
//    BnplCheckoutOption, so the checkout screen never has to have
//    already called getLoanOffer itself or hold state passed down
//    from the home card.
// ─────────────────────────────────────────────────────────────────
// Reuses whatever PezeshaService's session cache already holds (e.g.
// from BnplLimitCard being checked on the home screen earlier this
// session); only hits the network if nothing's cached yet, and never
// calls ensureRegistered (see file header — checkout isn't where BNPL
// should be discovered for the first time). Renders nothing while
// resolving and nothing if BNPL isn't available for this customer —
// checkout should never show a loading flicker for a financing option
// most orders won't use.

class BnplCheckoutSection extends StatefulWidget {
  final VendorModel vendor;
  final GasListing listing;
  final String country;
  final String orderId;

  /// Called after a successful loan application, so the caller can
  /// proceed to create the order with paymentMethod = bnpl and this
  /// loanId attached (OrderModel.loanId) BEFORE calling createOrder.
  final void Function(String loanId) onApproved;

  const BnplCheckoutSection({
    super.key,
    required this.vendor,
    required this.listing,
    required this.country,
    required this.orderId,
    required this.onApproved,
  });

  @override
  State<BnplCheckoutSection> createState() => _BnplCheckoutSectionState();
}

class _BnplCheckoutSectionState extends State<BnplCheckoutSection> {
  PezeshaLoanOffer? _offer;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _resolveOffer();
  }

  Future<void> _resolveOffer() async {
    try {
      // forceRefresh: false (default) — deliberately serves the
      // cached offer from BnplLimitCard if one exists, rather than a
      // second network round trip mid-checkout.
      final offer = await PezeshaService.getLoanOffer(ownerType: 'customer');
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _resolving = false;
      });
    } catch (_) {
      // Silent — checkout just won't show the BNPL option. A customer
      // mid-checkout shouldn't hit an error banner for a financing
      // option they didn't explicitly ask for; "Pay on delivery"
      // still works regardless.
      if (!mounted) return;
      setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving || _offer == null) return const SizedBox.shrink();
    return BnplCheckoutOption(
      vendor: widget.vendor,
      listing: widget.listing,
      country: widget.country,
      offer: _offer!,
      orderId: widget.orderId,
      onApproved: widget.onApproved,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// 3. Checkout payment option
// ─────────────────────────────────────────────────────────────────
// Renders next to "Pay on delivery" once an offer is known — normally
// reached through BnplCheckoutSection above, which resolves that
// offer for you. Selecting it and confirming applies the loan
// immediately, disbursed to THIS order's vendor.

class BnplCheckoutOption extends StatefulWidget {
  final VendorModel vendor;
  final GasListing listing;
  final String country;
  final PezeshaLoanOffer offer;
  final String orderId;

  /// Called after a successful loan application, so the caller can
  /// proceed to create the order with paymentMethod = bnpl and this
  /// loanId attached.
  final void Function(String loanId) onApproved;

  const BnplCheckoutOption({
    super.key,
    required this.vendor,
    required this.listing,
    required this.country,
    required this.offer,
    required this.orderId,
    required this.onApproved,
  });

  @override
  State<BnplCheckoutOption> createState() => _BnplCheckoutOptionState();
}

class _BnplCheckoutOptionState extends State<BnplCheckoutOption> {
  bool _submitting = false;
  String? _error;

  bool get _withinLimit => widget.listing.price <= widget.offer.amount;

  Future<void> _confirm() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final loanId = await PezeshaService.applyLoan(
        loanType: 'customer_bnpl',
        amount: widget.listing.price,
        targetVendorId: widget.vendor.id,
        orderId: widget.orderId,
      );
      if (!mounted) return;
      widget.onApproved(loanId);
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not process this. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_withinLimit) {
      // Order exceeds the known limit — don't offer BNPL for it at
      // all rather than let the customer pick it and get rejected.
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card_outlined, color: _navy, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Pay with BNPL (via Pezesha)',
                    style: TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${Currency.formatFor(widget.country, widget.listing.price)} '
            'over ${widget.offer.duration} days. Loan provided by Pezesha — '
            'you repay Pezesha directly, not MobiGas.',
            style: const TextStyle(
                color: Colors.black54, fontSize: 12, height: 1.4),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
              ),
              child: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Confirm BNPL order'),
            ),
          ),
        ],
      ),
    );
  }
}