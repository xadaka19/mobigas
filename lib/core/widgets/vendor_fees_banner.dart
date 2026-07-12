import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/config/currency.dart';

/// ⚠️ FILL THESE IN before shipping — the paybill MobiGas collects
/// platform fees on. Vendors pay to this paybill with their vendor ID
/// (their auth UID / phone) as the account number so admin can match
/// payments during settlement.
const String kFeePaybillNumber = '4160599';
const String kFeeAccountHint = 'your phone number';

/// How long we wait for stkCallback to settle the transaction before
/// giving up and telling the vendor to check manually. Generous
/// because Safaricom's own callback can occasionally lag well past
/// the point the vendor already saw a success/failure screen on
/// their own phone.
const Duration kStkResultTimeout = Duration(seconds: 90);

/// Shows the vendor their accrued platform fees (1% customer-finder
/// fee on cash orders). Three states:
///  - feesOwed == 0            -> hidden
///  - 0 < feesOwed < threshold -> orange warning with pay instructions
///  - feesOwed >= threshold    -> red LOCKED banner (customers can no
///                                longer see this vendor until admin
///                                records payment)
///
/// Drop into the vendor home screen near the top of the body:
///   const VendorFeesBanner(),
class VendorFeesBanner extends StatelessWidget {
  const VendorFeesBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('vendors')
          .doc(uid)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox.shrink();
        }
        final data = snap.data!.data() as Map<String, dynamic>;
        final feesOwed = (data['feesOwed'] ?? 0.0).toDouble();
        final country = (data['country'] as String?) ?? 'KE';
        final isSuspended = data['isSuspended'] ?? false;
        final locked = isSuspended ||
            feesOwed >= MobiGasFees.vendorFeeLockThreshold;

        if (feesOwed <= 0 && !isSuspended) return const SizedBox.shrink();

        final bg = locked ? AppColors.errorLight : AppColors.warningLight;
        final accent = locked ? AppColors.error : AppColors.warning;
        final textColor =
            locked ? AppColors.error : const Color(0xFF92400E);

        return GestureDetector(
          onTap: () => showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            isScrollControlled: true,
            builder: (_) => _FeeSheet(
              feesOwed: feesOwed,
              locked: locked,
              country: country,
              vendorPhone: (data['phone'] ?? '').toString(),
            ),
          ),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                    locked
                        ? Icons.lock_rounded
                        : Icons.account_balance_wallet_outlined,
                    color: accent,
                    size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        locked
                            ? 'Orders paused — platform fees due'
                            : 'Platform fees: ${Currency.formatFor(country, feesOwed)} owed',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 14,
                              color: textColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        locked
                            ? 'Pay ${Currency.formatFor(country, feesOwed)} now to resume receiving orders. Tap for payment details.'
                            : 'Customer-finder fee (1%) on your cash orders. Orders pause automatically at ${Currency.formatFor(country, MobiGasFees.vendorFeeLockThreshold)} — tap to pay now.',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: textColor,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: accent),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The payment bottom sheet, extracted into its own StatefulWidget
/// (rather than a StatefulBuilder closure) specifically so it can own
/// a StreamSubscription and clean it up in dispose() — a
/// StatefulBuilder has no dispose hook, so any listener started
/// inside one would leak for the lifetime of the app, still firing
/// setState after the sheet was long closed.
class _FeeSheet extends StatefulWidget {
  final double feesOwed;
  final bool locked;
  final String country;
  final String vendorPhone;

  const _FeeSheet({
    required this.feesOwed,
    required this.locked,
    required this.country,
    required this.vendorPhone,
  });

  @override
  State<_FeeSheet> createState() => _FeeSheetState();
}

enum _PaymentPhase { idle, sendingPrompt, waitingForPin, success, failed }

class _FeeSheetState extends State<_FeeSheet> {
  late final TextEditingController _phoneController;
  _PaymentPhase _phase = _PaymentPhase.idle;
  String? _statusMessage;
  StreamSubscription<DocumentSnapshot>? _txnSub;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.vendorPhone);
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

  Future<void> _payNow() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 9) {
      setState(() {
        _phase = _PaymentPhase.idle;
        _statusMessage = 'Enter a valid Safaricom number.';
      });
      return;
    }

    // Starting a fresh attempt — drop any listener/timer from a
    // previous try so we never react to a stale transaction.
    _txnSub?.cancel();
    _timeoutTimer?.cancel();

    setState(() {
      _phase = _PaymentPhase.sendingPrompt;
      _statusMessage = null;
    });

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('initiateStkPush');
      final result = await callable.call({'phone': phone});
      final checkoutRequestId = result.data['checkoutRequestId'] as String?;

      if (!mounted) return;

      if (checkoutRequestId == null) {
        // Shouldn't happen if the function succeeded, but don't leave
        // the vendor stuck with a spinner if it does.
        setState(() {
          _phase = _PaymentPhase.failed;
          _statusMessage = 'Could not track this payment. Try again.';
        });
        return;
      }

      setState(() {
        _phase = _PaymentPhase.waitingForPin;
        _statusMessage =
            (result.data['message'] as String?) ??
                'Check your phone to complete the M-Pesa payment.';
      });

      // Listen for stkCallback to settle this exact transaction.
      _txnSub = FirebaseFirestore.instance
          .collection('stk_transactions')
          .doc(checkoutRequestId)
          .snapshots()
          .listen((doc) {
        if (!mounted || !doc.exists) return;
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String?;

        if (status == 'completed') {
          _timeoutTimer?.cancel();
          setState(() {
            _phase = _PaymentPhase.success;
            _statusMessage = 'Payment received — thank you!';
          });
          // Give the vendor a moment to actually see the success
          // message before the sheet closes itself.
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) Navigator.of(context).pop();
          });
        } else if (status == 'failed') {
          _timeoutTimer?.cancel();
          final resultDesc = data['resultDesc'] as String?;
          setState(() {
            _phase = _PaymentPhase.failed;
            _statusMessage = resultDesc != null
                ? 'Payment not completed: $resultDesc'
                : 'Payment was not completed. You can try again.';
          });
        }
        // status == 'pending' -> keep waiting, no UI change needed.
      });

      // Don't wait forever — Safaricom's callback occasionally lags.
      _timeoutTimer = Timer(kStkResultTimeout, () {
        if (!mounted || _phase != _PaymentPhase.waitingForPin) return;
        setState(() {
          _statusMessage =
              'Still confirming your payment — this can take a moment. '
              'You can close this and check back; it will update '
              'automatically once confirmed.';
        });
      });
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

  @override
  Widget build(BuildContext context) {
    final feesOwed = widget.feesOwed;
    final locked = widget.locked;
    final isSuccess = _phase == _PaymentPhase.success;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                    isSuccess
                        ? Icons.check_circle_rounded
                        : locked
                            ? Icons.lock_rounded
                            : Icons.account_balance_wallet_outlined,
                    color: isSuccess
                        ? AppColors.success
                        : locked
                            ? AppColors.error
                            : AppColors.orange,
                    size: 22),
                const SizedBox(width: 10),
                Text(isSuccess ? 'Payment complete' : 'Platform fees',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.navy)),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSuccess ? AppColors.success : AppColors.navy,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isSuccess ? 'Amount paid' : 'Amount owed',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray400)),
                  Text(Currency.formatFor(widget.country, feesOwed),
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(
                            color: AppColors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                          )),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!isSuccess) ...[
              Text('Pay with M-Pesa',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        color: AppColors.navy,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                enabled: !_isBusy,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '07XX XXX XXX',
                  prefixIcon: const Icon(Icons.phone_android_rounded,
                      color: AppColors.gray400),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.orange),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isBusy ? null : _payNow,
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
                            : Icons.phone_iphone_rounded,
                        size: 18),
                label: Text(_phase == _PaymentPhase.sendingPrompt
                    ? 'Sending prompt...'
                    : _phase == _PaymentPhase.waitingForPin
                        ? 'Waiting for M-Pesa PIN...'
                        : _phase == _PaymentPhase.failed
                            ? 'Try again'
                            : 'Pay ${Currency.formatFor(widget.country, feesOwed)} now'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  backgroundColor: AppColors.success,
                ),
              ),
            ],
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isError
                          ? AppColors.error
                          : isSuccess
                              ? AppColors.success
                              : AppColors.orange)
                      .withValues(alpha: 0.1),
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
                                      : isSuccess
                                          ? AppColors.success
                                          : AppColors.orangeDeep,
                                  height: 1.4,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!isSuccess) ...[
              const SizedBox(height: 20),
              Text(
                'MobiGas charges a 1% customer-finder fee on cash orders we bring you. '
                'Credit orders are not charged this fee. '
                'If unpaid fees reach ${Currency.formatFor(widget.country, MobiGasFees.vendorFeeLockThreshold)}, '
                'your shop is hidden from customers until you pay. '
                'It reappears automatically once your payment is recorded.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray600,
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('Or pay manually via paybill',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray600,
                        fontWeight: FontWeight.w600)),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.orangeLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _payLine(context, '1. Lipa na M-Pesa → Pay Bill'),
                        _payLine(
                            context, '2. Business number: $kFeePaybillNumber'),
                        _payLine(context, '3. Account: $kFeeAccountHint'),
                        _payLine(context,
                            '4. Amount: ${Currency.formatFor(widget.country, feesOwed)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                          const ClipboardData(text: kFeePaybillNumber));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Paybill number copied')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy paybill number'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(isSuccess ? 'Done' : 'Close',
                    style: const TextStyle(color: AppColors.gray600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _payLine(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.orangeDeep,
                fontSize: 12,
                height: 1.4,
              )),
    );
  }
}