import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/models/app_models.dart';

class StockLoanScreen extends StatefulWidget {
  final int monthsOnPlatform;
  final int totalDeliveries;
  final double averageMonthlyRevenue;
  final Map<String, dynamic> vendorData;

  const StockLoanScreen({
    super.key,
    required this.monthsOnPlatform,
    required this.totalDeliveries,
    required this.averageMonthlyRevenue,
    required this.vendorData,
  });

  @override
  State<StockLoanScreen> createState() => _StockLoanScreenState();
}

class _StockLoanScreenState extends State<StockLoanScreen> {
  final _amountController = TextEditingController();
  String _purpose = 'Buy gas stock in bulk';
  bool _isSubmitting = false;
  bool _submitted = false;
  StockLoanStatus? _existingStatus;

  String get _vendorId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  // Max loan = 3x average monthly revenue
  double get _maxLoan => widget.averageMonthlyRevenue * 3;

  @override
  void initState() {
    super.initState();
    _checkExistingApplication();
  }

  Future<void> _checkExistingApplication() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('stock_loan_applications')
          .where('vendorId', isEqualTo: _vendorId)
          .orderBy('appliedAt', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        setState(() {
          _existingStatus = StockLoanStatus.values.firstWhere(
            (e) => e.name == data['status'],
            orElse: () => StockLoanStatus.pending,
          );
        });
      }
    } catch (_) {}
  }

  bool _idConfirmed = false;
  bool _termsAccepted = false;

  Future<void> _submitApplication() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a valid amount'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (amount > _maxLoan) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Maximum loan is KES ${_maxLoan.toStringAsFixed(0)}'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance
          .collection('stock_loan_applications')
          .add({
        'vendorId': _vendorId,
        'vendorName': widget.vendorData['businessName'] ?? '',
        'ownerName': widget.vendorData['ownerName'] ?? '',
        'phone': widget.vendorData['phone'] ?? '',
        'businessType': widget.vendorData['businessType'] ?? '',
        'requestedAmount': amount,
        'approvedAmount': 0,
        'purpose': _purpose,
        'status': StockLoanStatus.pending.name,
        'monthsOnPlatform': widget.monthsOnPlatform,
        'totalDeliveries': widget.totalDeliveries,
        'averageMonthlyRevenue': widget.averageMonthlyRevenue,
        'maxEligibleAmount': _maxLoan,
        'certificateUrl': widget.vendorData['certificateUrl'] ?? '',
        'appliedAt': FieldValue.serverTimestamp(),
        'partnerBankName': '',
      });

      setState(() {
        _submitted = true;
        _isSubmitting = false;
      });
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: AppColors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Text('Stock Boost Loan',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: AppColors.white)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _submitted || _existingStatus != null
                    ? _buildStatusView()
                    : _buildApplicationForm(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusView() {
    final status = _existingStatus ?? StockLoanStatus.pending;
    final isPending = status == StockLoanStatus.pending;
    final isApproved = status == StockLoanStatus.bankApproved ||
        status == StockLoanStatus.disbursed;
    final isRejected = status == StockLoanStatus.bankRejected;

    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: (isApproved
                    ? AppColors.success
                    : isRejected
                        ? AppColors.error
                        : AppColors.orange)
                .withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isApproved
                ? Icons.check_circle_rounded
                : isRejected
                    ? Icons.cancel_rounded
                    : Icons.hourglass_top_rounded,
            color: isApproved
                ? AppColors.success
                : isRejected
                    ? AppColors.error
                    : AppColors.orange,
            size: 56,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          _submitted || isPending
              ? 'Application submitted!'
              : isApproved
                  ? 'Loan approved!'
                  : 'Application not approved',
          style: Theme.of(context)
              .textTheme
              .displayMedium
              ?.copyWith(color: AppColors.white, fontSize: 24),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          _submitted || isPending
              ? 'Your application is being sent to our partner bank for instant review. The bank will assess your delivery track record and notify you within minutes.'
              : isApproved
                  ? 'Your loan has been approved. Funds will be disbursed to your M-Pesa shortly.'
                  : 'Unfortunately your application was not approved at this time. You can reapply after 30 days.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppColors.gray400, height: 1.6),
        ),
        const SizedBox(height: 32),
        _infoCard(),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.white,
            side: BorderSide(
                color: AppColors.white.withValues(alpha: 0.3)),
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Back to dashboard'),
        ),
      ],
    );
  }

  Widget _buildApplicationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eligibility summary
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(children: [
                const Icon(Icons.verified_rounded,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Text('You are eligible!',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: AppColors.success)),
              ]),
              const SizedBox(height: 12),
              _eligRow('Months on platform',
                  '${widget.monthsOnPlatform} months ✓'),
              _eligRow('Total deliveries',
                  '${widget.totalDeliveries} ✓'),
              _eligRow('Avg monthly revenue',
                  'KES ${widget.averageMonthlyRevenue.toStringAsFixed(0)}'),
              _eligRow('Max loan amount',
                  'KES ${_maxLoan.toStringAsFixed(0)}'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Loan amount',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                )),
        const SizedBox(height: 6),
        TextFormField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly
          ],
          style: const TextStyle(
              color: AppColors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            prefixText: 'KES ',
            prefixStyle: const TextStyle(
              color: AppColors.orange,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            hintText: '0',
            hintStyle: const TextStyle(color: AppColors.gray600),
            helperText:
                'Maximum: KES ${_maxLoan.toStringAsFixed(0)}',
            helperStyle: const TextStyle(
                color: AppColors.gray400, fontSize: 11),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.orange),
            ),
            filled: true,
            fillColor: AppColors.white.withValues(alpha: 0.05),
          ),
        ),
        const SizedBox(height: 20),
        Text('Purpose',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                )),
        const SizedBox(height: 8),
        ...[
          'Buy gas stock in bulk',
          'Purchase new cylinders',
          'Buy delivery motorcycle',
          'Expand to new area',
        ].map((p) => GestureDetector(
              onTap: () => setState(() => _purpose = p),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _purpose == p
                      ? AppColors.orange.withValues(alpha: 0.15)
                      : AppColors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _purpose == p
                        ? AppColors.orange
                        : AppColors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    _purpose == p
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: _purpose == p
                        ? AppColors.orange
                        : AppColors.gray400,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(p,
                      style: TextStyle(
                        color: _purpose == p
                            ? AppColors.white
                            : AppColors.gray400,
                        fontWeight: _purpose == p
                            ? FontWeight.w600
                            : FontWeight.w400,
                      )),
                ]),
              ),
            )),
        const SizedBox(height: 20),
        _infoCard(),
        const SizedBox(height: 20),
        // What we share with bank
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Information shared with partner bank',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      )),
              const SizedBox(height: 10),
              _shareRow('Business name',
                  widget.vendorData['businessName'] ?? ''),
              _shareRow('Owner name',
                  widget.vendorData['ownerName'] ?? ''),
              _shareRow(
                  widget.vendorData['businessType'] == 'sole'
                      ? 'National ID'
                      : 'Business Reg No.',
                  widget.vendorData['nationalId'] ??
                      widget.vendorData['businessRegNumber'] ??
                      ''),
              _shareRow('M-Pesa number',
                  widget.vendorData['phone'] ?? ''),
              _shareRow('Months on platform',
                  '${widget.monthsOnPlatform} months'),
              _shareRow('Total deliveries',
                  '${widget.totalDeliveries}'),
              _shareRow('Avg monthly revenue',
                  'KES ${widget.averageMonthlyRevenue.toStringAsFixed(0)}'),
              _shareRow('Business certificate',
                  widget.vendorData['certificateUrl'] != null
                      ? 'Uploaded ✓'
                      : 'Not uploaded'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Consent checkboxes
        GestureDetector(
          onTap: () => setState(() => _idConfirmed = !_idConfirmed),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _idConfirmed
                      ? AppColors.orange
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _idConfirmed
                        ? AppColors.orange
                        : AppColors.gray400,
                  ),
                ),
                child: _idConfirmed
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'I confirm my business details and ID information are accurate and I consent to sharing them with MobiGas partner banks for credit assessment.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _termsAccepted = !_termsAccepted),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: _termsAccepted
                      ? AppColors.orange
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: _termsAccepted
                        ? AppColors.orange
                        : AppColors.gray400,
                  ),
                ),
                child: _termsAccepted
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'I understand this is a loan that must be repaid. MobiGas is only a connector — the loan is provided by a partner bank.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        height: 1.4,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _isSubmitting || !_idConfirmed || !_termsAccepted
              ? null
              : _submitApplication,
          style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 52)),
          child: _isSubmitting
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.white))
              : const Text('Submit application'),
        ),
      ],
    );
  }

  Widget _shareRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400, fontSize: 12)),
          const Spacer(),
          Text(value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          _infoRow(Icons.account_balance_outlined,
              'MobiGas shares your delivery data with partner bank — bank makes all credit decisions'),
          _infoRow(Icons.payments_outlined,
              'Repay from your delivery earnings over 30-90 days'),
          _infoRow(Icons.percent_rounded,
              'Competitive interest rate from partner bank'),
          _infoRow(Icons.shield_outlined,
              'MobiGas never lends money — we only connect you to the bank'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      height: 1.4,
                    )),
          ),
        ],
      ),
    );
  }

  Widget _eligRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                  )),
          const Spacer(),
          Text(value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  )),
        ],
      ),
    );
  }
}
