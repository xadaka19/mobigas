import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/features/customer/screens/repayments_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final orders = context.watch<OrderProvider>();
    final customer = auth.customer;

    if (customer == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: IndexedStack(
                index: _currentTab,
                children: [
                  _buildHomeTab(customer, orders),
                  _buildOrdersTab(orders),
                  _buildRepaymentsTab(),
                  _buildProfileTab(customer, auth),
                ],
              ),
            ),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab(CustomerModel customer, OrderProvider orders) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHomeHeader(customer),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildCreditCard(customer),
                const SizedBox(height: 20),
                _buildOrderButton(customer),
                const SizedBox(height: 20),
                _buildHowItWorks(),
                const SizedBox(height: 20),
                _buildRecentOrdersSection(orders),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeHeader(CustomerModel customer) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning 👋'
        : hour < 17
            ? 'Good afternoon 👋'
            : 'Good evening 👋';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray400,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customer.name.split(' ').first,
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium
                        ?.copyWith(
                          color: AppColors.white,
                          fontSize: 22,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              Stack(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications_outlined,
                      color: AppColors.orange,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _headerStat(
                label: 'Credit limit',
                value: customer.bankApprovedLimit != null
                    ? 'KES ${customer.bankApprovedLimit!.toStringAsFixed(0)}'
                    : 'Pending',
              ),
              Container(
                width: 1,
                height: 36,
                color: AppColors.gray600,
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              _headerStat(
                label: 'Available',
                value: customer.isBankApproved
                    ? 'KES ${customer.bankCreditAvailable.toStringAsFixed(0)}'
                    : 'Pending',
                valueColor: AppColors.success,
              ),
              Container(
                width: 1,
                height: 36,
                color: AppColors.gray600,
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              _headerStat(
                label: 'Used',
                value:
                    'KES ${customer.bankCreditUsed.toStringAsFixed(0)}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerStat({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray400,
                fontSize: 11,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: valueColor ?? AppColors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }

  Widget _buildCreditCard(CustomerModel customer) {
    final usedPercent = customer.bankApprovedLimit != null &&
            customer.bankApprovedLimit! > 0
        ? customer.bankCreditUsed / customer.bankApprovedLimit!
        : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.navy, Color(0xFF1E3A6E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: customer.isBankApproved
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: customer.isBankApproved
                            ? AppColors.success
                            : AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      customer.isBankApproved
                          ? 'Credit active'
                          : 'Pending approval',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: customer.isBankApproved
                                ? AppColors.success
                                : AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Icon(Icons.local_fire_department_rounded,
                  color: AppColors.orange, size: 28),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'Available credit',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  fontSize: 12,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            customer.isBankApproved
                ? 'KES ${customer.bankCreditAvailable.toStringAsFixed(0)}'
                : 'Awaiting bank approval',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: AppColors.white,
                  fontSize: customer.isBankApproved ? 36 : 22,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usedPercent,
              backgroundColor: AppColors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.orange),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'KES ${customer.bankCreditUsed.toStringAsFixed(0)} used',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      fontSize: 11,
                    ),
              ),
              const Spacer(),
              if (customer.partnerBankName.isNotEmpty)
                Text(
                  'via ${customer.partnerBankName}',
                  style:
                      Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderButton(CustomerModel customer) {
    final canOrder = customer.isBankApproved;
    return GestureDetector(
      onTap: canOrder ? () => context.go('/order') : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: canOrder ? AppColors.orange : AppColors.gray400,
          borderRadius: BorderRadius.circular(20),
          boxShadow: canOrder
              ? [
                  BoxShadow(
                    color: AppColors.orange.withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    canOrder ? 'Order gas now' : 'Awaiting bank approval',
                    style:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.white,
                              fontSize: 18,
                            ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    canOrder
                        ? 'Delivered to your door · Bank pays vendor'
                        : 'You will be notified once approved',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            ),
            if (canOrder)
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: AppColors.white, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    final steps = [
      _HowStep(Icons.shopping_cart_outlined, 'Order', 'Pick size & vendor',
          AppColors.orange),
      _HowStep(Icons.local_shipping_outlined, 'Delivery',
          'Bank pays vendor', AppColors.navy),
      _HowStep(Icons.pin_outlined, 'PIN', 'Confirm delivery',
          AppColors.success),
      _HowStep(Icons.payment_outlined, 'Repay', 'Via M-Pesa',
          AppColors.warning),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How it works',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: steps.asMap().entries.map((e) {
            final i = e.key;
            final step = e.value;
            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: step.color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(step.icon,
                              color: step.color, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(step.title,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                            textAlign: TextAlign.center),
                        Text(step.subtitle,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.gray400,
                                  fontSize: 10,
                                ),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                  if (i < steps.length - 1)
                    const Icon(Icons.arrow_forward_ios_rounded,
                        size: 10, color: AppColors.gray400),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRecentOrdersSection(OrderProvider orders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent orders',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _currentTab = 1),
              child: Text(
                'See all',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        orders.orders.isEmpty
            ? _buildEmptyOrders()
            : Column(
                children: orders.orders
                    .take(3)
                    .map((o) => _orderTile(o))
                    .toList(),
              ),
      ],
    );
  }

  Widget _buildEmptyOrders() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 48, color: AppColors.gray400),
          const SizedBox(height: 12),
          Text('No orders yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.gray600,
                  )),
          const SizedBox(height: 4),
          Text('Your first gas order will appear here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                  )),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => context.go('/order'),
            child: const Text('Place first order'),
          ),
        ],
      ),
    );
  }

  Widget _orderTile(OrderModel order) {
    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (order.status) {
      case OrderStatus.delivered:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle_rounded;
        statusLabel = 'Delivered';
        break;
      case OrderStatus.outForDelivery:
        statusColor = AppColors.orange;
        statusIcon = Icons.local_shipping_rounded;
        statusLabel = 'On the way';
        break;
      case OrderStatus.pending:
        statusColor = AppColors.warning;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'Pending';
        break;
      default:
        statusColor = AppColors.gray400;
        statusIcon = Icons.receipt_outlined;
        statusLabel = 'Processing';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${order.listing.size} — ${order.vendorName}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14,
                        color: AppColors.navy,
                      ),
                ),
                Text(
                  order.orderId,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'KES ${order.listing.customerRepayment.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── ORDERS TAB ────────────────────────────────────────────────────
  Widget _buildOrdersTab(OrderProvider orders) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          color: AppColors.navy,
          child: Row(
            children: [
              Text('My Orders',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.white,
                      )),
            ],
          ),
        ),
        Expanded(
          child: orders.orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 64, color: AppColors.gray400),
                      const SizedBox(height: 16),
                      Text('No orders yet',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.gray600)),
                      const SizedBox(height: 24),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 48),
                        child: ElevatedButton(
                          onPressed: () => context.go('/order'),
                          child: const Text('Order gas now'),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.orders.length,
                  itemBuilder: (context, i) =>
                      _orderTile(orders.orders[i]),
                ),
        ),
      ],
    );
  }

  // ── REPAYMENTS TAB ────────────────────────────────────────────────
  Widget _buildRepaymentsTab() {
    return const RepaymentsScreen();
  }

  // ── PROFILE TAB ───────────────────────────────────────────────────
  Widget _buildProfileTab(CustomerModel customer, AuthProvider auth) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.orange,
                  child: Text(
                    customer.name[0],
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(customer.name,
                    style:
                        Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.white,
                            )),
                const SizedBox(height: 4),
                Text(customer.phone,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray400,
                        )),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: customer.isBankApproved
                        ? AppColors.success.withValues(alpha: 0.2)
                        : AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    customer.isBankApproved
                        ? 'Bank Approved ✓'
                        : 'Pending bank approval',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: customer.isBankApproved
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _profileTile(
                    Icons.badge_outlined, 'National ID', customer.nationalId),
                _profileTile(Icons.location_on_outlined, 'Location',
                    '${customer.estate}, ${customer.county}'),
                _profileTile(Icons.people_outline_rounded, 'Guarantors',
                    '${customer.guarantors.length} added'),
                if (customer.partnerBankName.isNotEmpty)
                  _profileTile(Icons.account_balance_outlined,
                      'Partner bank', customer.partnerBankName),
                if (customer.bankApprovedLimit != null)
                  _profileTile(
                      Icons.credit_score_rounded,
                      'Credit limit',
                      'KES ${customer.bankApprovedLimit!.toStringAsFixed(0)}'),
                const SizedBox(height: 8),
                _profileAction(
                    Icons.lock_outline_rounded, 'Change password'),
                _profileAction(
                    Icons.help_outline_rounded, 'Help & support'),
                _profileAction(
                    Icons.info_outline_rounded, 'About MobiGas'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    auth.logout();
                    context.go('/');
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Sign out'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.orange, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.gray600,
                  )),
          const Spacer(),
          Text(value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w600,
                  )),
        ],
      ),
    );
  }

  Widget _profileAction(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        tileColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.gray200),
        ),
        leading: Icon(icon, color: AppColors.navy, size: 20),
        title: Text(label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.navy,
                )),
        trailing: const Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: AppColors.gray400),
        onTap: () {},
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
      _NavItem(Icons.receipt_long_outlined, Icons.receipt_long_rounded,
          'Orders'),
      _NavItem(Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet_rounded, 'Repayments'),
      _NavItem(
          Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: items.asMap().entries.map((e) {
              final i = e.key;
              final item = e.value;
              final isActive = _currentTab == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _currentTab = i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? item.activeIcon : item.icon,
                        color: isActive
                            ? AppColors.orange
                            : AppColors.gray400,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: isActive
                                  ? AppColors.orange
                                  : AppColors.gray400,
                              fontSize: 10,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _HowStep {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _HowStep(this.icon, this.title, this.subtitle, this.color);
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
