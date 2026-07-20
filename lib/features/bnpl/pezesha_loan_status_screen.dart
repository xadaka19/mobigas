// lib/features/bnpl/pezesha_loan_status_screen.dart
//
// Shared "My Loans" screen for BOTH apps — customer BNPL and vendor
// stock loans use the same underlying Pezesha loan record shape, and
// the codebase already serves both flavors from one lib/ (see
// FlavorConfig), so this is parameterized by ownerType/country rather
// than built twice.
//
// This is what satisfies the persistent-visibility requirement
// flagged in pezesha_service.dart's getLoanHistory comment: a Google
// Play policy requirement for lending-adjacent apps that loan
// terms/status stay visible after the fact, not just in a one-time
// "approved!" toast at application time (which is all
// BnplCheckoutOption / _StockLoanSheet show today).
//
// VERIFY: the exact field names Pezesha returns from
// /mfi/v1/borrowers/latest and /mfi/v1/borrowers/statement aren't
// confirmed (see pezesha.ts header comment items 1-6). Every value
// this screen reads is looked up defensively across a few likely
// spellings (see _pick) rather than assumed present, and anything it
// doesn't recognize is still shown — collapsed, under "More details"
// — so nothing Pezesha actually returns silently disappears while the
// schema is unconfirmed. Once confirmed on the Discovery Call,
// hardcode the real field names in _LoanCard and this fallback can
// shrink or go away.

import 'package:flutter/material.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/services/pezesha_service.dart';

const _navy = Color(0xFF0D1B40);
const _orange = Color(0xFFF97316);

class PezeshaLoanStatusScreen extends StatefulWidget {
  final String ownerType; // 'customer' | 'vendor'
  final String country;

  const PezeshaLoanStatusScreen({
    super.key,
    required this.ownerType,
    required this.country,
  });

  @override
  State<PezeshaLoanStatusScreen> createState() =>
      _PezeshaLoanStatusScreenState();
}

enum _LoadState { loading, loaded, error }

class _PezeshaLoanStatusScreenState extends State<PezeshaLoanStatusScreen> {
  _LoadState _state = _LoadState.loading;
  Map<String, dynamic>? _latest;
  List<Map<String, dynamic>> _history = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _state = _LoadState.loading;
      _error = null;
    });
    try {
      final latest = await PezeshaService.getLoanStatus(
        ownerType: widget.ownerType,
      );
      final history = await PezeshaService.getLoanHistory(
        ownerType: widget.ownerType,
        page: 1,
      );
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _history = history;
        _page = 1;
        _hasMore = history.isNotEmpty;
        _state = _LoadState.loaded;
      });
    } on PezeshaException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _error = 'Could not load your loans. Try again.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final more = await PezeshaService.getLoanHistory(
        ownerType: widget.ownerType,
        page: nextPage,
      );
      if (!mounted) return;
      setState(() {
        _history = [..._history, ...more];
        _page = nextPage;
        _hasMore = more.isNotEmpty;
      });
    } catch (_) {
      // Silent — pagination failure just means "Load more" can be
      // tapped again; not worth an error banner over what's already
      // showing correctly.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Loans'),
        backgroundColor: _navy,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator(color: _orange));
      case _LoadState.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error ?? 'Something went wrong.',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        );
      case _LoadState.loaded:
        return RefreshIndicator(
          onRefresh: _load,
          color: _orange,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Current loan',
                  style: TextStyle(
                      color: _navy.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 8),
              _latest == null
                  ? _emptyCard('No active loan right now.')
                  : _LoanCard(
                      data: _latest!, country: widget.country, highlight: true),
              const SizedBox(height: 24),
              Text('Loan history',
                  style: TextStyle(
                      color: _navy.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 8),
              if (_history.isEmpty) _emptyCard('No past loans yet.'),
              for (final loan in _history) ...[
                _LoanCard(data: loan, country: widget.country),
                const SizedBox(height: 10),
              ],
              if (_hasMore)
                Center(
                  child: TextButton(
                    onPressed: _loadingMore ? null : _loadMore,
                    child: _loadingMore
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Load more'),
                  ),
                ),
            ],
          ),
        );
    }
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _navy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message,
          style: const TextStyle(color: Colors.black54, fontSize: 13)),
    );
  }
}

/// Reads a value trying several possible field-name spellings, since
/// the real Pezesha response shape isn't confirmed yet (see file
/// header). Returns null if none of the candidates are present.
dynamic _pick(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key) && data[key] != null) return data[key];
  }
  return null;
}

/// Parses a value that might arrive as a num or a numeric String —
/// Pezesha's JSON has been inconsistent about this elsewhere in the
/// integration (see PezeshaLoanOffer.fromMap's own rate parsing).
double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

class _LoanCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String country;
  final bool highlight;

  const _LoanCard({
    required this.data,
    required this.country,
    this.highlight = false,
  });

  static const _recognizedKeys = {
    'amount', 'loan_amount', 'principal',
    'status', 'loan_status',
    'due_date', 'dueDate', 'repayment_date',
    'balance', 'amount_due', 'outstanding_balance',
    'rate', 'interest_rate', 'interest', 'fee',
    'duration', 'tenure',
    'loan_id', 'loanId', 'id',
  };

  @override
  Widget build(BuildContext context) {
    final amount = _toDouble(_pick(data, ['amount', 'loan_amount', 'principal']));
    final status = _pick(data, ['status', 'loan_status']);
    final dueDate = _pick(data, ['due_date', 'dueDate', 'repayment_date']);
    final balance =
        _toDouble(_pick(data, ['balance', 'amount_due', 'outstanding_balance']));
    final rate = _pick(data, ['rate', 'interest_rate']);
    final interest = _pick(data, ['interest']);
    final fee = _pick(data, ['fee']);
    final duration = _pick(data, ['duration', 'tenure']);
    final loanId = _pick(data, ['loan_id', 'loanId', 'id']);

    // Anything Pezesha returned that this card doesn't have a labeled
    // slot for — shown collapsed rather than silently dropped, since
    // the real schema isn't confirmed yet (see file header).
    final unrecognized = Map.fromEntries(
      data.entries.where((e) => !_recognizedKeys.contains(e.key)),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? _navy : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            highlight ? null : Border.all(color: _navy.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: amount != null
                    ? Text(
                        Currency.formatFor(country, amount),
                        style: TextStyle(
                          color: highlight ? Colors.white : _navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      )
                    : Text(loanId != null ? 'Loan #$loanId' : 'Loan',
                        style: TextStyle(
                            color: highlight ? Colors.white : _navy,
                            fontWeight: FontWeight.w700)),
              ),
              if (status != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (highlight ? Colors.white : _orange)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$status',
                    style: TextStyle(
                      color: highlight ? Colors.white : _orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          if (balance != null || dueDate != null) ...[
            const SizedBox(height: 10),
            if (balance != null)
              _row('Amount due', Currency.formatFor(country, balance), highlight),
            if (dueDate != null) _row('Due', '$dueDate', highlight),
          ],
          if (duration != null || rate != null || interest != null || fee != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (duration != null) _pill('$duration days', highlight),
                if (rate != null) _pill('Rate: $rate', highlight),
                if (interest != null) _pill('Interest: $interest', highlight),
                if (fee != null) _pill('Fee: $fee', highlight),
              ],
            ),
          ],
          if (unrecognized.isNotEmpty) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text('More details',
                    style: TextStyle(
                        fontSize: 11,
                        color: highlight ? Colors.white70 : Colors.black45)),
                children: [
                  for (final entry in unrecognized.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('${entry.key}: ${entry.value}',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  highlight ? Colors.white70 : Colors.black45)),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, bool highlight) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: highlight ? Colors.white70 : Colors.black54)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlight ? Colors.white : _navy)),
        ],
      ),
    );
  }

  Widget _pill(String text, bool highlight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (highlight ? Colors.white : _navy).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 10, color: highlight ? Colors.white : _navy)),
    );
  }
}
