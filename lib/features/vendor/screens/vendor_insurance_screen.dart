import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/config/insurance_config.dart';
import 'package:mobigas/core/models/insurance_models.dart';
import 'package:mobigas/core/services/insurance_service.dart';
import 'package:mobigas/core/config/mobile_money.dart';
import 'package:url_launcher/url_launcher.dart';

/// How long we wait for the STK payment to settle before telling the
/// vendor to check back — same generous window as the platform-fee
/// flow (kStkResultTimeout in vendor_fees_banner.dart), since
/// Safaricom's callback can lag well past what the vendor sees on
/// their own screen.
const Duration _kStkResultTimeout = Duration(seconds: 90);

enum _Phase {
  loadingHistory,
  choosingCover,
  sendingPrompt,
  waitingForPin,
  issuing, // payment confirmed, waiting for the policy doc to appear
  success,
  failed,
}

class VendorInsuranceScreen extends StatefulWidget {
  final String vendorId;
  final Map<String, dynamic>? vendorData;
  final InsurancePolicyModel? existingPolicy;

  const VendorInsuranceScreen({
    super.key,
    required this.vendorId,
    required this.vendorData,
    this.existingPolicy,
  });

  @override
  State<VendorInsuranceScreen> createState() => _VendorInsuranceScreenState();
}

class _VendorInsuranceScreenState extends State<VendorInsuranceScreen> {
  _Phase _phase = _Phase.loadingHistory;
  String? _statusMessage;
  SalesHistoryResult? _history;
  CoverageMultiplier _multiplier = CoverageMultiplier.x1;
  late final TextEditingController _phoneController;
  StreamSubscription<DocumentSnapshot>? _stkSub;
  StreamSubscription<InsurancePolicyModel?>? _policySub;
  Timer? _timeoutTimer;
  final DateTime _screenOpenedAt = DateTime.now();

  String get _country => (widget.vendorData?['country'] as String?) ?? 'KE';

  @override
  void initState() {
    super.initState();
    // Same payout-vs-contact resolution used in vendor_fees_banner.dart
    // (_feePayerPhoneFrom) — prefill the wallet the vendor actually
    // pays from, not necessarily their customer-facing contact line.
    final payout = (widget.vendorData?['payoutPhone'] ?? '').toString();
    final contact = (widget.vendorData?['phone'] ?? '').toString();
    _phoneController =
        TextEditingController(text: payout.isNotEmpty ? payout : contact);
    _loadHistory();
  }

  @override
  void dispose() {
    _stkSub?.cancel();
    _policySub?.cancel();
    _timeoutTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    // Already covered — nothing to quote.
    if (widget.existingPolicy?.isActive == true) {
      setState(() => _phase = _Phase.success);
      return;
    }
    try {
      final result =
          await InsuranceService.computeAvgMonthlySales(widget.vendorId);
      if (!mounted) return;
      setState(() {
        _history = result;
        _phase = _Phase.choosingCover;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _statusMessage = 'Could not load your sales history. Try again.';
      });
    }
  }

  (double sumInsured, SumInsuredBasis basis) get _quote {
    if (_history == null) return (0, SumInsuredBasis.starter);
    return InsuranceService.sumInsuredFor(
      history: _history!,
      multiplier: _multiplier,
    );
  }

  double get _premium => InsuranceConfig.premiumFor(_quote.$1);

  bool get _isBusy =>
      _phase == _Phase.sendingPrompt ||
      _phase == _Phase.waitingForPin ||
      _phase == _Phase.issuing;

  Future<void> _buyNow() async {
    final phone = _phoneController.text.trim();
    final provider = MobileMoney.feeProviderFor(_country);
    final isPesapal = provider == PlatformFeeProvider.pesapal;

    if (phone.length < 9) {
      setState(() => _statusMessage = isPesapal
          ? 'Enter a valid phone number.'
          : 'Enter a valid M-Pesa number.');
      return;
    }

    _stkSub?.cancel();
    _timeoutTimer?.cancel();
    setState(() {
      _phase = _Phase.sendingPrompt;
      _statusMessage = null;
    });

    final (sumInsured, basis) = _quote;

    try {
      if (isPesapal) {
        final res = await InsuranceService.initiatePremiumPesapal(
          vendorId: widget.vendorId,
          phone: phone,
          sumInsured: sumInsured,
          premium: _premium,
          basis: basis,
          multiplier: basis == SumInsuredBasis.computed ? _multiplier : null,
          avgMonthlySales: _history?.avgMonthlySales,
        );
        if (!mounted) return;
        if (res.redirectUrl == null || res.orderTrackingId == null) {
          setState(() {
            _phase = _Phase.failed;
            _statusMessage = 'Could not start the payment. Try again.';
          });
          return;
        }

        final launched = await launchUrl(
          Uri.parse(res.redirectUrl!),
          mode: LaunchMode.externalApplication,
        );
        if (!launched) {
          if (!mounted) return;
          setState(() {
            _phase = _Phase.failed;
            _statusMessage = 'Could not open the payment page. Try again.';
          });
          return;
        }

        setState(() {
          _phase = _Phase.waitingForPin;
          _statusMessage =
              'Complete your payment in the browser, then come back — '
              'this updates automatically once confirmed.';
        });

        _stkSub = FirebaseFirestore.instance
            .collection('insurance_pesapal_transactions')
            .doc(res.orderTrackingId)
            .snapshots()
            .listen(_handleStkUpdate);
        _timeoutTimer = Timer(_kStkResultTimeout, _handleTimeout);
      } else {
        final checkoutRequestId = await InsuranceService.initiatePremiumStk(
          vendorId: widget.vendorId,
          phone: phone,
          sumInsured: sumInsured,
          premium: _premium,
          basis: basis,
          multiplier: basis == SumInsuredBasis.computed ? _multiplier : null,
          avgMonthlySales: _history?.avgMonthlySales,
        );
        if (!mounted) return;
        if (checkoutRequestId == null) {
          setState(() {
            _phase = _Phase.failed;
            _statusMessage = 'Could not start the payment. Try again.';
          });
          return;
        }

        setState(() {
          _phase = _Phase.waitingForPin;
          _statusMessage = 'Check your phone to complete the M-Pesa payment.';
        });

        _stkSub = FirebaseFirestore.instance
            .collection('insurance_stk_transactions')
            .doc(checkoutRequestId)
            .snapshots()
            .listen(_handleStkUpdate);
        _timeoutTimer = Timer(_kStkResultTimeout, _handleTimeout);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _statusMessage = 'Something went wrong. Try again.';
      });
    }
  }

  void _handleStkUpdate(DocumentSnapshot doc) {
    if (!mounted || !doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status == 'completed') {
      // Payment landed — the server-side issueInsurancePolicy function
      // (triggered off this same stk_transactions write) now calls
      // the underwriter's API and writes the insurance_policies doc.
      // We wait for THAT doc rather than declaring success on payment
      // alone: a vendor should see "policy active", not just "we
      // took your money" — the underwriter call could still fail
      // after payment clears.
      _timeoutTimer?.cancel();
      setState(() {
        _phase = _Phase.issuing;
        _statusMessage = 'Payment received — issuing your policy...';
      });
      _watchForIssuedPolicy();
    } else if (status == 'failed') {
      _timeoutTimer?.cancel();
      final resultDesc = data['resultDesc'] as String?;
      setState(() {
        _phase = _Phase.failed;
        _statusMessage = resultDesc != null
            ? 'Payment not completed: $resultDesc'
            : 'Payment was not completed. You can try again.';
      });
    }
  }

  void _watchForIssuedPolicy() {
    _policySub?.cancel();
    _policySub =
        InsuranceService.watchActivePolicy(widget.vendorId).listen((policy) {
      if (!mounted || policy == null) return;
      // Only treat this as THIS purchase completing if it was issued
      // after this screen opened — otherwise a pre-existing active
      // policy would falsely trigger success the instant the
      // listener attaches.
      if (policy.purchasedAt.isAfter(_screenOpenedAt)) {
        setState(() {
          _phase = _Phase.success;
          _statusMessage = null;
        });
      }
    });
    Timer(_kStkResultTimeout, () {
      if (mounted && _phase == _Phase.issuing) {
        setState(() {
          _statusMessage =
              'Payment received — your policy is still being issued. '
              'This can take a moment; check back shortly.';
        });
      }
    });
  }

  void _handleTimeout() {
    if (!mounted || _phase != _Phase.waitingForPin) return;
    setState(() {
      _statusMessage =
          'Still confirming your payment — this can take a moment. '
          'You can check back; it will update automatically.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        elevation: 0,
        title: const Text('Stock insurance'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.loadingHistory:
        return const Padding(
          padding: EdgeInsets.only(top: 80),
          child:
              Center(child: CircularProgressIndicator(color: AppColors.orange)),
        );
      case _Phase.success:
        return _buildSuccess();
      default:
        return _buildQuoteAndPay();
    }
  }

  Widget _buildQuoteAndPay() {
    final (sumInsured, basis) = _quote;
    final isPesapal =
        MobileMoney.feeProviderFor(_country) == PlatformFeeProvider.pesapal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoCard(
          Icons.shield_outlined,
          'Fire & theft cover for your gas stock — underwritten by our insurance partner. MobiGas only facilitates the purchase and earns a commission.',
        ),
        const SizedBox(height: 20),
        if (basis == SumInsuredBasis.starter) ...[
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Starter cover',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'You don\'t have a full month of delivery history yet, so '
                  'we\'re offering a flat starter amount. Once you\'ve '
                  'completed orders in at least one month, your cover can '
                  'scale with your actual sales.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400, height: 1.5),
                ),
              ],
            ),
          ),
        ] else ...[
          Text('Choose your cover',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.white, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Based on your average monthly sales of '
            '${Currency.formatFor(_country, _history?.avgMonthlySales ?? 0)} '
            '(last ${_history?.activeMonthsCount ?? 0} active '
            '${_history?.activeMonthsCount == 1 ? 'month' : 'months'})',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray400, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: CoverageMultiplier.values.map((m) {
              final selected = _multiplier == m;
              return Expanded(
                child: GestureDetector(
                  onTap:
                      _isBusy ? null : () => setState(() => _multiplier = m),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.orange
                          : AppColors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.orange
                            : AppColors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Text(
                      m.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? AppColors.white : AppColors.gray400,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 20),
        _card(
          child: Column(
            children: [
              _quoteRow('Sum insured', Currency.formatFor(_country, sumInsured)),
              const Divider(height: 20, color: Colors.white12),
              _quoteRow('Annual premium', Currency.formatFor(_country, _premium),
                  isBold: true, valueColor: AppColors.orange),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(isPesapal ? 'Pay with Pesapal' : 'Pay with M-Pesa',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          enabled: !_isBusy,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText:
                isPesapal ? 'e.g. 0712 345 678' : '07XX XXX XXX',
            hintStyle: const TextStyle(color: AppColors.gray600),
            prefixIcon:
                const Icon(Icons.phone_android_rounded, color: AppColors.gray400),
            filled: true,
            fillColor: AppColors.white.withValues(alpha: 0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppColors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.orange),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _isBusy ? null : _buyNow,
          icon: _isBusy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.white))
              : const Icon(Icons.phone_iphone_rounded, size: 18),
          label: Text(
            _phase == _Phase.sendingPrompt
                ? 'Sending prompt...'
                : _phase == _Phase.waitingForPin
                    ? (isPesapal
                        ? 'Waiting for payment...'
                        : 'Waiting for M-Pesa PIN...')
                    : _phase == _Phase.issuing
                        ? 'Issuing your policy...'
                        : _phase == _Phase.failed
                            ? 'Try again'
                            : 'Pay ${Currency.formatFor(_country, _premium)} now',
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 52),
            backgroundColor: AppColors.success,
          ),
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (_phase == _Phase.failed
                      ? AppColors.error
                      : AppColors.orange)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isBusy)
                  const Padding(
                    padding: EdgeInsets.only(right: 10, top: 2),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.orange),
                    ),
                  ),
                Expanded(
                  child: Text(
                    _statusMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _phase == _Phase.failed
                            ? AppColors.error
                            : AppColors.orangeDeep,
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'MobiGas facilitates this policy and earns a commission from our '
          'insurance partner — your cover is underwritten by them, not by '
          'MobiGas. Claims are handled directly with the underwriter.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.gray600, fontSize: 11, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      children: [
        const SizedBox(height: 40),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified_user_rounded,
              color: AppColors.success, size: 56),
        ),
        const SizedBox(height: 24),
        Text('You\'re covered!',
            style: Theme.of(context)
                .textTheme
                .displayMedium
                ?.copyWith(color: AppColors.white, fontSize: 26)),
        const SizedBox(height: 8),
        Text('Fire & theft cover is now active on your stock.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.gray400, height: 1.5)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.white.withValues(alpha: 0.1)),
      ),
      child: child,
    );
  }

  Widget _quoteRow(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.gray400)),
        const Spacer(),
        Text(value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: valueColor ?? AppColors.white,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                fontSize: isBold ? 18 : 14)),
      ],
    );
  }

  Widget _infoCard(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.orange, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
