import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/models/app_models.dart';

class RepaymentsScreen extends StatelessWidget {
  const RepaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>();
    final customer = context.watch<AuthProvider>().customer;

    // BUG FIX: these lists used to filter by STATUS ONLY, so cash
    // orders (paid in full at the door) showed up here as bank loans
    // — with 8% interest added and a fabricated due date. Only
    // credit-financed orders belong on this screen at all.
    final pendingOrders = orders.orders
        .where((o) =>
            o.paymentMethod == PaymentMethod.credit &&
            (o.status == OrderStatus.delivered ||
                o.status == OrderStatus.repaying))
        .toList();

    final completedOrders = orders.orders
        .where((o) =>
            o.paymentMethod == PaymentMethod.credit &&
            o.status == OrderStatus.completed)
        .toList();

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          decoration: const BoxDecoration(
            color: AppColors.navy,
            borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Repayments',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                    ),
              ),
              if (customer?.partnerBankName.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  'Loan provider: ${customer!.partnerBankName}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: pendingOrders.isEmpty && completedOrders.isEmpty
              ? _buildEmpty(context)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (pendingOrders.isNotEmpty) ...[
                      _sectionLabel(context, 'Outstanding'),
                      const SizedBox(height: 8),
                      ...pendingOrders.map(
                          (o) => _repaymentCard(context, o, pending: true)),
                      const SizedBox(height: 20),
                    ],
                    if (completedOrders.isNotEmpty) ...[
                      _sectionLabel(context, 'Paid'),
                      const SizedBox(height: 8),
                      ...completedOrders.map(
                          (o) => _repaymentCard(context, o, pending: false)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.navy,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  Widget _repaymentCard(BuildContext context, OrderModel order,
      {required bool pending}) {
    final dueDate = order.bankRepaymentDueDate ??
        order.createdAt.add(const Duration(days: 30));
    final dueDateStr = '${dueDate.day}/${dueDate.month}/${dueDate.year}';
    final isOverdue =
        pending && DateTime.now().isAfter(dueDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOverdue
              ? AppColors.error
              : pending
                  ? AppColors.orange.withValues(alpha: 0.4)
                  : AppColors.gray200,
          width: pending ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Order header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isOverdue
                  ? AppColors.errorLight
                  : pending
                      ? AppColors.orangeLight
                      : AppColors.gray100,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(
                  isOverdue
                      ? Icons.warning_rounded
                      : pending
                          ? Icons.pending_rounded
                          : Icons.check_circle_rounded,
                  color: isOverdue
                      ? AppColors.error
                      : pending
                          ? AppColors.orange
                          : AppColors.success,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  isOverdue
                      ? 'OVERDUE'
                      : pending
                          ? 'Payment due $dueDateStr'
                          : 'Paid',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isOverdue
                            ? AppColors.error
                            : pending
                                ? AppColors.orangeDeep
                                : AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Text(
                  order.orderId,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                        fontSize: 10,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${order.listing.size} gas',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          order.vendorName,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.gray400,
                                  ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'KES ${order.listing.customerRepayment.toStringAsFixed(0)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: pending
                                    ? AppColors.orange
                                    : AppColors.success,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (order.partnerBankName.isNotEmpty)
                          Text(
                            'to ${order.partnerBankName}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.gray400,
                                  fontSize: 11,
                                ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (pending) ...[
                  const SizedBox(height: 16),
                  const Divider(color: AppColors.gray200),
                  const SizedBox(height: 12),
                  // Payment instructions
                  _paymentInstructions(context, order),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentInstructions(BuildContext context, OrderModel order) {
    // Bank paybill — will be set per partner bank
    // For pilot: hardcoded, later from Firestore bank config
    const String paybill = '400200'; // placeholder — bank provides this
    final String accountNumber = order.orderId;
    final String amount =
        order.listing.customerRepayment.toStringAsFixed(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay via M-Pesa',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 13,
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 10),
        _mpesaStep(context, '1', 'Go to M-Pesa → Lipa na M-Pesa → Pay Bill'),
        _mpesaStep(context, '2',
            'Business no: $paybill (${order.partnerBankName})',
            copyValue: paybill),
        _mpesaStep(context, '3', 'Account no: $accountNumber',
            copyValue: accountNumber),
        _mpesaStep(context, '4', 'Amount: KES $amount',
            copyValue: amount),
        _mpesaStep(context, '5', 'Enter M-Pesa PIN and confirm'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.success, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Use your Order ID ($accountNumber) as the account number so your payment is matched correctly.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF166534),
                        height: 1.4,
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mpesaStep(BuildContext context, String step, String text,
      {String? copyValue}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: AppColors.orange,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: AppColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.navy,
                    height: 1.4,
                    fontSize: 12,
                    fontWeight: copyValue != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
            ),
          ),
          if (copyValue != null)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: copyValue));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('$copyValue copied'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                );
              },
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_rounded,
                    size: 14, color: AppColors.orange),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 64, color: AppColors.gray400),
          const SizedBox(height: 16),
          Text(
            'No repayments due',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.gray600,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Repayments appear here after you buy gas on credit',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
        ],
      ),
    );
  }
}