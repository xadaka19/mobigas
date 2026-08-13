import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/config/mobile_money.dart';
import 'package:mobigas/flavors/flavor_config.dart';

/// How long we wait for the payment to settle before telling the
/// vendor to check back — same generous window as the platform-fee
/// flow (vendor_fees_banner.dart), for the same reason: both
/// stkCallback and Pesapal's IPN can lag past what the vendor already
/// saw on their own screen.
const Duration _kResultTimeout = Duration(seconds: 90);

/// Full-app lock for the MobiGas Facilitation Fee (1% of a disbursed
/// Pezesha vendor_stock loan). Unlike VendorFeesBanner — a dismissible
/// bottom sheet the vendor can ignore — this is a non-dismissible,
/// always-on-top block: the app is unusable for anything else while
/// any facilitation fee is owed. Mount once, at the app root, above
/// the router (see app.dart's MaterialApp.router `builder`), so it
/// intercepts every screen regardless of navigation state.
///
/// Vendor-only and Kenya/Uganda/Tanzania — Pezesha loans disburse in
/// all three, so this supports both M-Pesa (KE) and Pesapal (UG/TZ),
/// mirroring VendorFeesBanner's dual-rail handling exactly.
class VendorLoanFeeLockGate extends StatelessWidget {
  final Widget child;

  const VendorLoanFeeLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!FlavorConfig.isVendor) return child;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return child;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vendors')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return child;
        final data = snap.data!.data() as Map<String, dynamic>;
        final loanFeeOwed = (data['loanFeeOwed'] ?? 0.0).toDouble();

        if (loanFeeOwed <= 0) return child;

        final country = (data['country'] as String?) ?? 'KE';
        final payerPhone = (() {
          final payout = (data['payoutPhone'] ?? '').toString().trim();
          if (payout.isNotEmpty) return payout;
          return (data['phone'] ?? '').toString().trim();
        })();

        return Stack(
          children: [
            child,
            // Full-screen, non-dismissible — no back button, no swipe,
            // no way to see the app underneath until paid.
            PopScope(
              canPop: false,
              child: Material(
                color: AppColors.navy,
                child: SafeArea(
                  child: _LoanFeeLockBody(
                    loanFeeOwed: loanFeeOwed,
                    country: country,
                    vendorId: uid,
                    payerPhone: payerPhone,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LoanFeeLockBody extends StatefulWidget {
  final double loanFeeOwed;
  final String country;
  final String vendorId;
  final String payerPhone;

  const _LoanFeeLockBody({
    required this.loanFeeOwed,
    required this.country,
    required this.vendorId,
    required this.payerPhone,
  });

  @override
  State<_LoanFeeLockBody> createState() => _LoanFeeLockBodyState();
}

enum _PaymentPhase { idle, sendingPrompt, waitingForPin, failed }

class _LoanFeeLockBodyState extends State<_LoanFeeLockBody> {
  late final TextEditingController _phoneController;
  _PaymentPhase _phase = _PaymentPhase.idle;
  String? _statusMessage;
  StreamSubscription<DocumentSnapshot>? _txnSub;
  Timer? _timeoutTimer;

  PlatformFeeProvider get _provider =>
      MobileMoney.feeProviderFor(widget.country);
  bool get _isPesapal => _provider == PlatformFeeProvider.pesapal;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.payerPhone);
  }

  @override
  void dispose() {
    _txnSub?.cancel();
    _timeoutTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isError => _phase == _PaymentPhase.failed;
  bool get _isBusy =>
      _phase == _PaymentPhase.sendingPrompt ||
      _phase == _PaymentPhase.waitingForPin;

  Future<void> _payWithMpesa() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      setState(() {
        _phase = _PaymentPhase.idle;
        _statusMessage = 'Enter a valid Safaricom number.';
      });
      return;
    }

    _txnSub?.cancel();
    _timeoutTimer?.cancel();

    setState(() {
      _phase = _PaymentPhase.sendingPrompt;
      _statusMessage = null;
    });

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('initiateLoanFeeStkPush');
      final result = await callable.call({'phone': phone});
      final checkoutRequestId = result.data['checkoutRequestId'] as String?;

      if (!mounted) return;

      if (checkoutRequestId == null) {
        setState(() {
          _phase = _PaymentPhase.failed;
          _statusMessage = 'Could not track this payment. Try again.';
        });
        return;
      }

      setState(() {
        _phase = _PaymentPhase.waitingForPin;
        _statusMessage = (result.data['message'] as String?) ??
            'Check your phone to complete the M-Pesa payment.';
      });

      // No need to react to 'completed' here — the moment stkCallback
      // decrements loanFeeOwed to 0, the StreamBuilder in
      // VendorLoanFeeLockGate rebuilds and this whole screen just
      // disappears on its own. Only watching for 'failed' so we can
      // tell the vendor to retry.
      _txnSub = FirebaseFirestore.instance
          .collection('stk_transactions')
          .doc(checkoutRequestId)
          .snapshots()
          .listen(_handleTransactionUpdate);

      _timeoutTimer = Timer(_kResultTimeout, _handleTimeout);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PaymentPhase.failed;
        _statusMessage =
            e.message ?? 'Could not start the M-Pesa payment. Try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _PaymentPhase.failed;
        _statusMessage = 'Something went wrong. Try again.';
      });
    }
  }

  Future<void> _payWithPesapal() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      setState(() {
        _phase = _PaymentPhase.idle;
        _statusMessage = 'Enter a valid phone number.';
      });
      return;
    }

    _txnSub?.cancel();
    _timeoutTimer?.cancel();

    setState(() {
      _phase = _PaymentPhase.sendingPrompt;
      _statusMessage = null;
    });

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('initiatePesapalPayment');
      final result = await callable.call({
        'vendorId': widget.vendorId,
        'amount': widget.loanFeeOwed,
        'country': widget.country,
        'phone': phone,
      });
      final redirectUrl = result.data['redirectUrl'] as String?;
      final orderTrackingId = result.data['orderTrackingId'] as String?;

      if (!mounted) return;

      if (redirectUrl == null || orderTrackingId == null) {
        setState(() {
          _phase = _PaymentPhase.failed;
          _statusMessage = 'Could not start the Pesapal payment. Try again.';
        });
        return;
      }

      final launched = await launchUrl(
        Uri.parse(redirectUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        if (!mounted) return;
        setState(() {
          _phase = _PaymentPhase.failed;
          _statusMessage = 'Could not open the payment page. Try again.';
        });
        return;
      }

      setState(() {
        _phase = _PaymentPhase.waitingForPin;
        _statusMessage =
            'Complete your payment in the browser, then come back here — '
            'this updates automatically once confirmed.';
      });

      _txnSub = FirebaseFirestore.instance
          .collection('pesapal_transactions')
          .doc(orderTrackingId)
          .snapshots()
          .listen(_handleTransactionUpdate);

      _timeoutTimer = Timer(_kResultTimeout, _handleTimeout);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _PaymentPhase.failed;
        _statusMessage =
            e.message ?? 'Could not start the Pesapal payment. Try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _PaymentPhase.failed;
        _statusMessage = 'Something went wrong. Try again.';
      });
    }
  }

  /// Note: unlike VendorFeesBanner, there is deliberately no
  /// 'completed' branch here — see the comment in _payWithMpesa.
  /// Only 'failed' needs handling; success dismisses this whole
  /// screen automatically via the StreamBuilder above it.
  void _handleTransactionUpdate(DocumentSnapshot doc) {
    if (!mounted || !doc.exists) return;
    final data = doc.data() as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status == 'failed') {
      _timeoutTimer?.cancel();
      final resultDesc = data['resultDesc'] as String?;
      setState(() {
        _phase = _PaymentPhase.failed;
        _statusMessage = resultDesc != null
            ? 'Payment not completed: $resultDesc'
            : 'Payment was not completed. You can try again.';
      });
    }
  }

  void _handleTimeout() {
    if (!mounted || _phase != _PaymentPhase.waitingForPin) return;
    setState(() {
      _statusMessage =
          'Still confirming your payment — this can take a moment. '
          'This screen will clear automatically once confirmed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.lock_rounded, color: AppColors.white, size: 40),
          const SizedBox(height: 16),
          Text(
            'MobiGas Facilitation Fee due',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your recent stock loan has been disbursed to your supplier. '
            'Pay the facilitation fee below to unlock the app.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppColors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount owed',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400)),
                Text(
                  Currency.formatFor(widget.country, widget.loanFeeOwed),
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(_isPesapal ? 'Pay with Pesapal' : 'Pay with M-Pesa',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 8),
          TextField(
            controller: _phoneController,
            enabled: !_isBusy,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: AppColors.white),
            decoration: InputDecoration(
              hintText: _isPesapal ? 'e.g. 0712 345 678' : '07XX XXX XXX',
              hintStyle: TextStyle(color: AppColors.gray400),
              prefixIcon: const Icon(Icons.phone_android_rounded,
                  color: AppColors.gray400),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: AppColors.white.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.orange),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed:
                _isBusy ? null : (_isPesapal ? _payWithPesapal : _payWithMpesa),
            icon: _isBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  )
                : Icon(
                    _phase == _PaymentPhase.failed
                        ? Icons.refresh_rounded
                        : _isPesapal
                            ? Icons.open_in_new_rounded
                            : Icons.phone_iphone_rounded,
                    size: 18),
            label: Text(_phase == _PaymentPhase.sendingPrompt
                ? (_isPesapal ? 'Opening Pesapal...' : 'Sending prompt...')
                : _phase == _PaymentPhase.waitingForPin
                    ? (_isPesapal
                        ? 'Waiting for payment...'
                        : 'Waiting for M-Pesa PIN...')
                    : _phase == _PaymentPhase.failed
                        ? 'Try again'
                        : 'Pay ${Currency.formatFor(widget.country, widget.loanFeeOwed)} now'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: AppColors.success,
            ),
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_isError ? AppColors.error : AppColors.orange)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_phase == _PaymentPhase.waitingForPin)
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
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: _isError
                                    ? AppColors.error
                                    : AppColors.orangeLight,
                                height: 1.4,
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
