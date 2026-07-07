import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/providers/vendor_provider.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/features/customer/screens/repayments_screen.dart';
import 'package:mobigas/core/widgets/double_back_to_exit.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/features/shared/refer_earn_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  bool _initializedForCustomer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Listen for active order status changes → auto-open tracking
      context.read<OrderProvider>().addListener(() {
        final order = context.read<OrderProvider>().activeOrder;
        if (order?.status == OrderStatus.outForDelivery && mounted) {
          context.push('/order-tracking');
        }
      });
      _initForCustomer();
    });
  }

  /// Loads vendors + order stream once the customer object exists.
  /// Called from initState AND build, because on cold start the
  /// customer is still hydrating from Firestore when initState runs —
  /// loading vendors before we have coordinates means no distances.
  void _initForCustomer() {
    if (_initializedForCustomer) return;
    final customer = context.read<AuthProvider>().customer;
    if (customer == null) return;
    _initializedForCustomer = true;
    context.read<VendorProvider>().loadVendors(
          lat: customer.latitude,
          lng: customer.longitude,
        );
    context.read<OrderProvider>().watchOrders(customer.id);
  }

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

    // Customer just became available (cold start) — load vendors with
    // real coordinates and start the order stream.
    if (!_initializedForCustomer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _initForCustomer());
    }

    return DoubleBackToExit(
      child: Scaffold(
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
                    const RepaymentsScreen(),
                    _buildProfileTab(customer, auth),
                  ],
                ),
              ),
              _buildBottomNav(),
            ],
          ),
        ),
      ),
    );
  }

  // ── HOME TAB ──────────────────────────────────────────────────────
  Widget _buildHomeTab(CustomerModel customer, OrderProvider orders) {
    return RefreshIndicator(
      color: AppColors.orange,
      onRefresh: () async {
        context.read<OrderProvider>().refreshOrders();
        await context.read<VendorProvider>().loadVendors(
              lat: customer.latitude,
              lng: customer.longitude,
            );
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildHomeHeader(customer),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildCreditCard(customer),
                  const SizedBox(height: 20),
                  if (!customer.isBankApproved) ...[
                    _buildApplyCreditCard(),
                    const SizedBox(height: 20),
                  ],
                  _buildVendorPreview(),
                  const SizedBox(height: 20),
                  _buildHowItWorks(),
                  const SizedBox(height: 20),
                  _buildRecentOrders(orders),
                ],
              ),
            ),
          ],
        ),
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
                  Text(greeting,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.gray400,
                          )),
                  Text(
                    customer.name.split(' ').first,
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium
                        ?.copyWith(color: AppColors.white, fontSize: 22),
                  ),
                ],
              ),
              const Spacer(),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: FirestoreService.watchNotifications(customer.id),
                builder: (context, snap) {
                  final unreadCount = (snap.data ?? [])
                      .where((n) => n['read'] != true)
                      .length;
                  return GestureDetector(
                    onTap: () =>
                        _showNotifications(context, customer.id),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.orange.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.notifications_outlined,
                              color: AppColors.orange, size: 22),
                        ),
                        if (unreadCount > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              constraints: const BoxConstraints(
                                  minWidth: 18, minHeight: 18),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                    color: AppColors.navy, width: 1.5),
                              ),
                              child: Text(
                                unreadCount > 9 ? '9+' : '$unreadCount',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (customer.isBankApproved)
            Row(
              children: [
                _headerStat('Credit limit',
                    'KES ${customer.bankApprovedLimit!.toStringAsFixed(0)}'),
                Container(
                    width: 1,
                    height: 36,
                    color: AppColors.gray600,
                    margin: const EdgeInsets.symmetric(horizontal: 20)),
                _headerStat('Available',
                    'KES ${customer.bankCreditAvailable.toStringAsFixed(0)}',
                    valueColor: AppColors.success),
                Container(
                    width: 1,
                    height: 36,
                    color: AppColors.gray600,
                    margin: const EdgeInsets.symmetric(horizontal: 20)),
                _headerStat('Used',
                    'KES ${customer.bankCreditUsed.toStringAsFixed(0)}'),
              ],
            )
          else
            Text(
              'No gas credit yet — order and pay cash on delivery, or apply for a credit limit below.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                    fontSize: 12,
                    height: 1.4,
                  ),
            ),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                  fontSize: 11,
                )),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: valueColor ?? AppColors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                )),
      ],
    );
  }

  Widget _buildCreditCard(CustomerModel customer) {
    final usedPercent =
        customer.bankApprovedLimit != null && customer.bankApprovedLimit! > 0
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
          Text('Available credit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                    fontSize: 12,
                  )),
          const SizedBox(height: 4),
          Text(
            customer.isBankApproved
                ? 'KES ${customer.bankCreditAvailable.toStringAsFixed(0)}'
                : 'Awaiting bank approval',
            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  color: AppColors.white,
                  fontSize: customer.isBankApproved ? 36 : 20,
                  fontWeight: FontWeight.w800,
                ),
          ),
          if (!customer.isBankApproved) ...[
            const SizedBox(height: 6),
            Text(
              'You can still order gas and pay cash on delivery.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray400,
                    fontSize: 11,
                  ),
            ),
          ],
          if (customer.isBankApproved) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: usedPercent,
                backgroundColor: AppColors.white.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.orange),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildApplyCreditCard() {
    return GestureDetector(
      onTap: () => context.push('/credit-application'),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.navy,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.credit_score_rounded,
                  color: AppColors.orange, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Want gas on credit?',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Apply for a credit limit — order now, repay in 30 days',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.orange, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildHowItWorks() {
    final steps = [
      _HowStep(Icons.shopping_cart_outlined, 'Order', 'Pick size & vendor',
          AppColors.orange),
      _HowStep(Icons.two_wheeler_outlined, 'Delivery', 'To your door',
          AppColors.navy),
      _HowStep(
          Icons.pin_outlined, 'PIN', 'Confirm delivery', AppColors.success),
      _HowStep(
          Icons.payment_outlined, 'Pay', 'Cash or credit', AppColors.warning),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                )),
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
                          child:
                              Icon(step.icon, color: step.color, size: 22),
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

  Widget _buildVendorPreview() {
    final vendors = context.watch<VendorProvider>().onlineVendors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Order from vendors near you',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    )),
            const Spacer(),
            GestureDetector(
              onTap: () => context.push('/order'),
              child: Text('${vendors.length} online →',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      )),
            ),
          ],
        ),
        const SizedBox(height: 12),
        vendors.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.gray200),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.store_outlined,
                        size: 36, color: AppColors.gray400),
                    const SizedBox(height: 8),
                    Text('No vendors online yet',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.gray400)),
                  ],
                ),
              )
            : Column(
                children:
                    vendors.take(3).map((v) => _vendorCard(v)).toList(),
              ),
      ],
    );
  }

  Widget _vendorCard(VendorModel vendor) {
    final available = vendor.listings.where((l) => l.available).toList();
    final refills = available
        .where((l) => l.productType == GasProductType.refill)
        .toList();
    final hasFullKit =
        available.any((l) => l.productType == GasProductType.fullKit);
    final hasGrillKit =
        available.any((l) => l.productType == GasProductType.grillKit);
    // BUG FIX: previously just the minimum price across every size —
    // if a vendor's 3kg was cheapest but their 6kg/13kg were pricier,
    // the card said "from KES 800" with no indication that price was
    // ONLY for 3kg, misleading anyone who actually wants a different
    // size. Now the label names the size that price applies to.
    GasListing? cheapestRefill;
    for (final l in refills) {
      if (cheapestRefill == null || l.price < cheapestRefill.price) {
        cheapestRefill = l;
      }
    }

    Widget chip(String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.gray200),
          ),
          child: Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.gray600,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
        );

    return GestureDetector(
      onTap: () => context.push('/order'),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gray200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.orange,
                  child: Text(vendor.businessName[0].toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(vendor.businessName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: AppColors.navy,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text('Online',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.success,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${vendor.distance} · ★ ${vendor.rating.toStringAsFixed(1)} · ${vendor.deliveryTime}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: AppColors.gray400, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: AppColors.gray400),
              ],
            ),
            if (cheapestRefill != null || hasFullKit || hasGrillKit) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (cheapestRefill != null)
                    chip(
                        '${cheapestRefill.size} refill from KES ${cheapestRefill.price.toStringAsFixed(0)}'),
                  if (hasFullKit) chip('Gas + cylinder'),
                  if (hasGrillKit) chip('Gas + cylinder + grill'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRecentOrders(OrderProvider orders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent orders',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                    )),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _currentTab = 1),
              child: Text('See all',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w600,
                      )),
            ),
          ],
        ),
        const SizedBox(height: 12),
        orders.orders.isEmpty
            ? Container(
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
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppColors.gray600)),
                    const SizedBox(height: 4),
                    Text('Your gas orders will appear here',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray400)),
                  ],
                ),
              )
            : Column(
                children: orders.orders
                    .take(3)
                    .map((o) => _orderTile(o))
                    .toList()),
      ],
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
        statusIcon = Icons.two_wheeler_rounded;
        statusLabel = 'On the way';
        break;
      case OrderStatus.cancelled:
        statusColor = AppColors.gray400;
        statusIcon = Icons.cancel_rounded;
        statusLabel = 'Cancelled';
        break;
      default:
        statusColor = AppColors.warning;
        statusIcon = Icons.hourglass_top_rounded;
        statusLabel = 'Pending';
    }
    final isCash = order.paymentMethod == PaymentMethod.cash;
    final canCancel = order.status == OrderStatus.pending;
    final canTrack = order.status == OrderStatus.pending ||
        order.status == OrderStatus.accepted ||
        order.status == OrderStatus.outForDelivery;
    final tile = Container(
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
                Text('${order.listing.size} — ${order.vendorName}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 14, color: AppColors.navy)),
                Text('${order.orderId} · ${isCash ? 'Cash' : 'Credit'}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  'KES ${order.customerTotal.toStringAsFixed(0)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      color: order.status == OrderStatus.cancelled
                          ? AppColors.gray400
                          : AppColors.navy,
                      fontWeight: FontWeight.w700)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(statusLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
              if (canCancel) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _confirmCancelOrder(order),
                  child: Text('Cancel order',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.error,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (!canTrack) return tile;

    // In-progress orders reopen the live tracking screen — otherwise
    // a customer who navigates away has no way back to the map.
    return GestureDetector(
      onTap: () {
        context.read<OrderProvider>().setActiveOrder(order);
        context.push('/order-tracking');
      },
      child: tile,
    );
  }

  void _confirmCancelOrder(OrderModel order) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this order?'),
        content: Text(
          '${order.listing.size} from ${order.vendorName} — the vendor hasn\'t accepted it yet.'
          '${order.paymentMethod == PaymentMethod.credit ? ' Your credit will be released back to you.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Keep order',
                style: TextStyle(color: AppColors.gray600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<OrderProvider>().cancelOrder(order);
            },
            child: const Text('Cancel order',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
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
          child: Row(children: [
            Text('My Orders',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                    )),
          ]),
        ),
        Expanded(
          child: orders.error != null && orders.orders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 56, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text('Could not load your orders',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppColors.navy)),
                        const SizedBox(height: 8),
                        Text(orders.error!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.gray400)),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: () =>
                              context.read<OrderProvider>().refreshOrders(),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : orders.orders.isEmpty
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
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: ElevatedButton(
                          onPressed: () => context.push('/order'),
                          child: const Text('Order gas now'),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.orange,
                  onRefresh: () =>
                      context.read<OrderProvider>().refreshOrders(),
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.orders.length,
                    itemBuilder: (_, i) => _orderTile(orders.orders[i]),
                  ),
                ),
        ),
      ],
    );
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
                GestureDetector(
                  onTap: customer.selfieUrl != null
                      ? () => _showSelfie(context, customer.selfieUrl!)
                      : null,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.orange,
                        backgroundImage: customer.selfieUrl != null
                            ? NetworkImage(customer.selfieUrl!)
                            : null,
                        child: customer.selfieUrl == null
                            ? Text(customer.name[0],
                                style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700))
                            : null,
                      ),
                      if (customer.selfieUrl != null)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              color: AppColors.success,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.verified_rounded,
                                color: AppColors.white, size: 14),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(customer.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.white)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => context.push('/edit-profile'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_rounded,
                            color: AppColors.orange, size: 14),
                        const SizedBox(width: 6),
                        Text('Edit profile',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(customer.phone,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppColors.gray400)),
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
                if ((customer.email ?? '').isNotEmpty)
                  _profileTile(Icons.email_outlined, 'Email',
                      customer.email!),
                _profileTile(Icons.badge_outlined, 'National ID',
                    customer.nationalId),
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
                _profileAction(Icons.lock_outline_rounded, 'Change password',
                    onTap: () => _showChangePassword(context)),
                _profileAction(Icons.card_giftcard_rounded, 'Refer & Earn',
                    highlight: true,
                    onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ReferEarnScreen(
                              ownerId: customer.id,
                              ownerType: 'customer',
                              ownerName: customer.name,
                            ),
                          ),
                        )),
                _profileAction(Icons.people_outline_rounded, 'My guarantors',
                    onTap: () => _showGuarantors(context, customer)),
                _profileAction(Icons.help_outline_rounded, 'Help & support',
                    onTap: () => context.push('/support')),
                _profileAction(Icons.info_outline_rounded, 'About MobiGas',
                    onTap: () => _showAbout(context)),
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
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.gray600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.navy, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _profileAction(IconData icon, String label,
      {VoidCallback? onTap, bool highlight = false}) {
    final iconColor = highlight ? AppColors.success : AppColors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        tileColor: highlight
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: highlight
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.gray200),
        ),
        leading: Icon(icon, color: iconColor, size: 20),
        title: Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
                    color: highlight ? AppColors.success : AppColors.navy,
                    fontWeight: highlight ? FontWeight.w600 : FontWeight.w400)),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14,
            color: highlight ? AppColors.success : AppColors.gray400),
        onTap: onTap ?? () {},
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────
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
                      Text(item.label,
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
                              )),
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

  // ── MODALS ────────────────────────────────────────────────────────
  void _showSelfie(BuildContext context, String selfieUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                selfieUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) =>
                    progress == null
                        ? child
                        : const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.orange)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded,
                      color: AppColors.white, size: 16),
                  const SizedBox(width: 6),
                  Text('Identity verified',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          )),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close',
                  style: TextStyle(color: AppColors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showGuarantors(BuildContext context, CustomerModel customer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('My guarantors',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.navy)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Read only',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color: AppColors.gray600, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Guarantors cannot be changed after submission.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.gray400),
            ),
            const SizedBox(height: 20),
            customer.guarantors.isEmpty
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.gray100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.people_outline_rounded,
                            color: AppColors.gray400, size: 36),
                        const SizedBox(height: 8),
                        Text('No guarantors added yet',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.gray600)),
                        const SizedBox(height: 4),
                        Text(
                            'Apply for gas credit to add guarantors',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.gray400)),
                      ],
                    ),
                  )
                : Column(
                    children: customer.guarantors
                        .asMap()
                        .entries
                        .map((e) => Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.gray100,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: AppColors.gray200),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: AppColors.orange,
                                    child: Text(
                                      e.value.name.isNotEmpty
                                          ? e.value.name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: AppColors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.value.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                color: AppColors.navy,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          e.value.phone,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: AppColors.gray600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.successLight,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Guarantor ${e.key + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.success,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showNotifications(BuildContext context, String customerId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Notifications',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: AppColors.navy)),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        FirestoreService.markAllNotificationsRead(
                            customerId),
                    child: Text('Mark all read',
                        style: TextStyle(
                            color: AppColors.orange, fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Close',
                        style: TextStyle(color: AppColors.orange)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: FirestoreService.watchNotifications(customerId),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.orange));
                    }
                    final notifications = snap.data!;
                    if (notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.notifications_none_rounded,
                                size: 64, color: AppColors.gray400),
                            const SizedBox(height: 12),
                            Text('No notifications yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: AppColors.gray600)),
                            const SizedBox(height: 8),
                            Text(
                              'Order updates and payment reminders\nwill appear here',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.gray400),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: notifications.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final n = notifications[i];
                        final isRead = n['read'] == true;
                        final createdAt = n['createdAt'] as DateTime?;
                        return Dismissible(
                          key: ValueKey(n['id']),
                          direction: DismissDirection.endToStart,
                          onDismissed: (_) => FirestoreService
                              .deleteNotification(n['id'] as String),
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: AppColors.white),
                          ),
                          child: GestureDetector(
                            onTap: () {
                              if (!isRead) {
                                FirestoreService.markNotificationRead(
                                    n['id'] as String);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isRead
                                    ? AppColors.white
                                    : AppColors.orange
                                        .withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: isRead
                                        ? AppColors.gray200
                                        : AppColors.orange
                                            .withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  if (!isRead)
                                    Container(
                                      margin:
                                          const EdgeInsets.only(top: 5),
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: AppColors.orange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  if (!isRead) const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (n['title'] as String).isNotEmpty
                                              ? n['title'] as String
                                              : 'MobiGas',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  color: AppColors.navy,
                                                  fontWeight: isRead
                                                      ? FontWeight.w500
                                                      : FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(n['body'] as String,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color:
                                                        AppColors.gray600,
                                                    height: 1.4)),
                                        if (createdAt != null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                              '${createdAt.day}/${createdAt.month}/${createdAt.year} · ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color: AppColors
                                                          .gray400,
                                                      fontSize: 10)),
                                        ],
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => FirestoreService
                                        .deleteNotification(
                                            n['id'] as String),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                          color: AppColors.gray400),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Change password',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppColors.navy)),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'New password',
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: AppColors.gray400, size: 20),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Update password'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.local_fire_department_rounded,
                  color: AppColors.white, size: 34),
            ),
            const SizedBox(height: 16),
            Text('MobiGas',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.navy, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Cook now, pay later',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.gray600)),
            const SizedBox(height: 4),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snap) => Text(
                snap.hasData
                    ? 'Version ${snap.data!.version} (${snap.data!.buildNumber})'
                    : '',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.gray400),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'MobiGas connects you with local gas vendors for fast delivery — pay cash on delivery, or partner with our banks to get cooking gas on credit and repay within 30 days via M-Pesa.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.gray600, height: 1.5),
            ),
            const SizedBox(height: 16),
          ],
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