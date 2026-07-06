import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/models/app_models.dart';

/// ⚠️ FILL THESE IN before shipping — the paybill MobiGas collects
/// platform fees on. Vendors pay to this paybill with their vendor ID
/// (their auth UID / phone) as the account number so admin can match
/// payments during settlement.
const String kFeePaybillNumber = '4160599'; 
const String kFeeAccountHint = 'your phone number';

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
        final isSuspended = data['isSuspended'] ?? false;
        final locked = isSuspended ||
            feesOwed >= MobiGasFees.vendorFeeLockThreshold;

        if (feesOwed <= 0 && !isSuspended) return const SizedBox.shrink();

        final bg = locked ? AppColors.errorLight : AppColors.warningLight;
        final accent = locked ? AppColors.error : AppColors.warning;
        final textColor =
            locked ? AppColors.error : const Color(0xFF92400E);

        return GestureDetector(
          onTap: () => _showFeeSheet(
              context, feesOwed, locked, (data['phone'] ?? '').toString()),
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
                            : 'Platform fees: KES ${feesOwed.toStringAsFixed(0)} owed',
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
                            ? 'Pay KES ${feesOwed.toStringAsFixed(0)} now to resume receiving orders. Tap for payment details.'
                            : 'Customer-finder fee (1%) on your cash orders. Orders pause automatically at KES ${MobiGasFees.vendorFeeLockThreshold.toStringAsFixed(0)} — tap to pay now.',
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

  void _showFeeSheet(
      BuildContext context, double feesOwed, bool locked, String vendorPhone) {
    final phoneController = TextEditingController(text: vendorPhone);
    // Must live outside the StatefulBuilder's builder callback — that
    // callback re-runs on every setSheetState call, so variables
    // declared inside it would reset to their initial value on every
    // rebuild instead of persisting (e.g. isProcessing would always
    // snap back to false right after being set to true).
    bool isProcessing = false;
    String? statusMessage;
    bool statusIsError = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> payNow() async {
            final phone = phoneController.text.trim();
            if (phone.length < 9) {
              setSheetState(() {
                statusMessage = 'Enter a valid Safaricom number.';
                statusIsError = true;
              });
              return;
            }
            setSheetState(() {
              isProcessing = true;
              statusMessage = null;
            });
            try {
              final callable = FirebaseFunctions.instance
                  .httpsCallable('initiateStkPush');
              final result = await callable.call({'phone': phone});
              setSheetState(() {
                isProcessing = false;
                statusIsError = false;
                statusMessage = (result.data['message'] as String?) ??
                    'Check your phone to complete the payment.';
              });
              // No need to poll — the banner above is a live Firestore
              // stream on feesOwed, so it updates and disappears on
              // its own the moment stkCallback settles the payment.
            } on FirebaseFunctionsException catch (e) {
              setSheetState(() {
                isProcessing = false;
                statusIsError = true;
                statusMessage = e.message ??
                    'Could not start the M-Pesa payment. Try again.';
              });
            } catch (_) {
              setSheetState(() {
                isProcessing = false;
                statusIsError = true;
                statusMessage = 'Something went wrong. Try again.';
              });
            }
          }

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
                          locked
                              ? Icons.lock_rounded
                              : Icons.account_balance_wallet_outlined,
                          color:
                              locked ? AppColors.error : AppColors.orange,
                          size: 22),
                      const SizedBox(width: 10),
                      Text('Platform fees',
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
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount owed',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.gray400)),
                        Text('KES ${feesOwed.toStringAsFixed(0)}',
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
                  Text('Pay with M-Pesa',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 14,
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: phoneController,
                    enabled: !isProcessing,
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
                    onPressed: isProcessing ? null : payNow,
                    icon: isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.white),
                          )
                        : const Icon(Icons.phone_iphone_rounded, size: 18),
                    label: Text(isProcessing
                        ? 'Sending prompt...'
                        : 'Pay KES ${feesOwed.toStringAsFixed(0)} now'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: AppColors.success,
                    ),
                  ),
                  if (statusMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (statusIsError
                                ? AppColors.error
                                : AppColors.success)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        statusMessage!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: statusIsError
                                  ? AppColors.error
                                  : AppColors.success,
                              height: 1.4,
                            ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'MobiGas charges a 1% customer-finder fee on cash orders we bring you. '
                    'Credit orders are not charged this fee. '
                    'If unpaid fees reach KES ${MobiGasFees.vendorFeeLockThreshold.toStringAsFixed(0)}, '
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
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
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
                            _payLine(context,
                                '2. Business number: $kFeePaybillNumber'),
                            _payLine(
                                context, '3. Account: $kFeeAccountHint'),
                            _payLine(context,
                                '4. Amount: KES ${feesOwed.toStringAsFixed(0)}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              const ClipboardData(text: kFeePaybillNumber));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Paybill number copied')),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy paybill number'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close',
                          style: TextStyle(color: AppColors.gray600)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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