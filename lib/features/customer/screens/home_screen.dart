import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/providers/order_provider.dart';
import 'package:mobigas/core/providers/vendor_provider.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/widgets/double_back_to_exit.dart';
import 'package:mobigas/core/widgets/profile_completion_banner.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/features/shared/refer_earn_screen.dart';
import 'package:mobigas/core/widgets/promo_popup_mixin.dart';
import 'package:mobigas/core/config/pezesha_config.dart';
import 'package:mobigas/features/bnpl/customer_bnpl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with PromoPopupMixin {
  int _currentTab = 0;

  bool _ordersWatched = false;
  bool _promoChecked = false;
  double? _loadedLat;
  double? _loadedLng;

  late final OrderProvider _orderProvider;
  late final VoidCallback _orderListener;
  OrderStatus? _lastOrderStatus;

  @override
  void initState() {
    super.initState();
    _orderProvider = context.read<OrderProvider>();

    // Auto-open tracking when an order *transitions* into
    // out-for-delivery. Firing on every notify would stack tracking
    // screens on any refresh that happens mid-delivery.
    _orderListener = () {
      final status = _orderProvider.activeOrder?.status;
      if (status == OrderStatus.outForDelivery &&
          _lastOrderStatus != OrderStatus.outForDelivery &&
          mounted) {
        context.push('/order-tracking');
      }
      _lastOrderStatus = status;
    };
    _orderProvider.addListener(_orderListener);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initForCustomer());
  }

  @override
  void dispose() {
    _orderProvider.removeListener(_orderListener);
    super.dispose();
  }

  bool get _needsVendorReload {
    final c = context.read<AuthProvider>().customer;
    if (c == null || c.latitude == 0 || c.longitude == 0) return false;
    return _loadedLat != c.latitude || _loadedLng != c.longitude;
  }

  /// Starts the order stream as soon as we have a customer, and
  /// (re)loads vendors whenever real coordinates land — on cold start,
  /// or the moment the customer pins their location from the profile
  /// banner. Vendor matching is a Haversine search around the pin, so
  /// loading against 0,0 searches the middle of the Atlantic and
  /// returns nothing. We simply don't call it until we have a pin.
  void _initForCustomer() {
    final customer = context.read<AuthProvider>().customer;
    if (customer == null) return;

    if (!_promoChecked) {
      _promoChecked = true;
      checkForPromo(
        audience: 'customer',
        country: customer.country,
        userId: customer.id,
      );
    }

    if (!_ordersWatched) {
      _ordersWatched = true;
      context.read<OrderProvider>().watchOrders(customer.id);
    }

    if (customer.latitude == 0 || customer.longitude == 0) return;
    if (_loadedLat == customer.latitude && _loadedLng == customer.longitude) {
      return;
    }

    _loadedLat = customer.latitude;
    _loadedLng = customer.longitude;
    context.read<VendorProvider>().loadVendors(
          lat: customer.latitude,
          lng: customer.longitude,
        );
  }

  /// Ordering needs a phone number and a delivery pin. Rather than
  /// failing at vendor-matching or at checkout, send the customer
  /// straight to the step they're missing.
  void _goToOrder() {
    final auth = context.read<AuthProvider>();
    if (!auth.isProfileComplete) {
      ProfileCompletionSheet.show(
        context,
        initialStep: auth.firstIncompleteStep,
      );
      return;
    }
    context.push('/order');
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

    // Cold start (customer just hydrated) or the customer just saved a
    // location from the banner — both need a vendor load.
    if (!_ordersWatched || _needsVendorReload) {
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
        if (customer.latitude != 0 && customer.longitude != 0) {
          await context.read<VendorProvider>().loadVendors(
                lat: customer.latitude,
                lng: customer.longitude,
              );
        }
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
                  const ProfileCompletionBanner(),
                  _buildOrderNowCard(),
                  if (PezeshaConfig.isAvailableFor(customer.country)) ...[
                    const SizedBox(height: 8),
                    BnplLimitCard(country: customer.country),
                  ],
                  const SizedBox(height: 20),
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

    final firstName =
        customer.name.trim().isEmpty ? 'there' : customer.name.split(' ').first;

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
                    firstName,
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
                  final unreadCount =
                      (snap.data ?? []).where((n) => n['read'] != true).length;
                  return GestureDetector(
                    onTap: () => _showNotifications(context, customer.id),
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
          const SizedBox(height: 16),
          Text(
            'Gas delivered to your door — compare prices from trusted vendors near you.',
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

  Widget _buildOrderNowCard() {
    return GestureDetector(
      onTap: _goToOrder,
      child: Container(
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
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.local_fire_department_rounded,
                  color: AppColors.orange, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order gas now',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          )),
                  const SizedBox(height: 2),
                  Text(
                    'Refills, full kits & accessories — pay cash or mobile money on delivery',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 11,
                          height: 1.4,
                        ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppColors.orange, size: 16),
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
          Icons.payment_outlined, 'Pay', 'Cash or mobile money', AppColors.warning),
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
                          child: Icon(step.icon, color: step.color, size: 22),
                        ),
                        const SizedBox(height: 6),
                        Text(step.title,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                            textAlign: TextAlign.center),
                        Text(step.subtitle,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
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
    final auth = context.watch<AuthProvider>();
    final vendors = context.watch<VendorProvider>().onlineVendors;

    // Without a pin there is nothing to match against — say so, and
    // give the customer the one action that fixes it.
    if (!auth.hasLocation) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gray200),
        ),
        child: Column(
          children: [
            const Icon(Icons.location_off_outlined,
                size: 36, color: AppColors.gray400),
            const SizedBox(height: 10),
            Text('Pin your location to see vendors',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.navy, fontSize: 14)),
            const SizedBox(height: 4),
            Text('We match you with vendors within 8 km of your pin.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.gray400)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () =>
                  ProfileCompletionSheet.show(context, initialStep: 1),
              child: const Text('Pin my location'),
            ),
          ],
        ),
      );
    }

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
              onTap: _goToOrder,
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
                children: vendors.take(3).map((v) => _vendorCard(v)).toList(),
              ),
      ],
    );
  }

  Widget _vendorCard(VendorModel vendor) {
    final available = vendor.listings.where((l) => l.available).toList();
    final refills =
        available.where((l) => l.productType == GasProductType.refill).toList();
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

    // Delivery: THREE states, not two. deliveryPreferenceSet is false
    // for any vendor who hasn't saved their pricing step since the
    // delivery feature shipped — we genuinely don't know what they
    // charge, so the card shows nothing at all rather than promising
    // free delivery on their behalf. See VendorModel's tri-state
    // comment; do not simplify this to `!vendor.chargesDeliveryFee`.
    final showsDelivery = vendor.deliveryPreferenceSet;
    final freeDelivery = vendor.hasFreeDelivery;

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

    /// Coloured chip for the things a customer actively compares on —
    /// free delivery and flexible payment — so they don't disappear
    /// into the grey run of product chips.
    Widget accentChip(IconData icon, String label, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      )),
            ],
          ),
        );

    final initial = vendor.businessName.trim().isEmpty
        ? '?'
        : vendor.businessName[0].toUpperCase();

    return GestureDetector(
      onTap: _goToOrder,
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
                  child: Text(initial,
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
                              color: AppColors.success.withValues(alpha: 0.12),
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
                            ?.copyWith(color: AppColors.gray400, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: AppColors.gray400),
              ],
            ),
            if (cheapestRefill != null ||
                hasFullKit ||
                hasGrillKit ||
                showsDelivery ||
                vendor.acceptsPartialPayment) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (cheapestRefill != null)
                    chip(
                        '${cheapestRefill.size} refill from ${Currency.formatFor(vendor.country, cheapestRefill.price)}'),
                  if (hasFullKit) chip('Gas + cylinder'),
                  if (hasGrillKit) chip('Gas + cylinder + grill'),
                  // Free delivery gets the accent treatment — it's one
                  // of the first things a customer compares between two
                  // vendors at similar prices. A vendor who charges
                  // gets the plain grey chip naming the fee, so the
                  // customer knows the real cost before they tap in.
                  if (showsDelivery)
                    freeDelivery
                        ? accentChip(Icons.local_shipping_outlined,
                            'Free delivery', AppColors.success)
                        : chip(
                            '+ ${Currency.formatFor(vendor.country, vendor.deliveryFee)} delivery'),
                  // Signals the vendor is open to arranging flexible
                  // payment — the details are shown on the order screen,
                  // where a specific vendor is selected. MobiGas only
                  // surfaces that the option exists; it's not a party to
                  // any arrangement.
                  if (vendor.acceptsPartialPayment)
                    accentChip(Icons.handshake_outlined, 'Flexible payment',
                        AppColors.orange),
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
                children:
                    orders.orders.take(3).map((o) => _orderTile(o)).toList()),
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
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 14, color: AppColors.navy)),
                Text('${order.orderId} · Pay on delivery',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400)),
                // Only when there was one. Says why the total above is
                // more than the gas price the customer chose, without
                // adding a row to every free-delivery order.
                if (order.deliveryFee > 0)
                  Text(
                      'Incl. ${Currency.formatFor(order.country, order.deliveryFee)} delivery',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray400,
                            fontSize: 10,
                          )),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // customerTotal = gas + delivery. Already correct here
              // before this feature (delivery was simply always 0), so
              // this line needed no change — it picks the fee up the
              // moment OrderModel carries one.
              Text(Currency.formatFor(order.country, order.customerTotal),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14,
                      color: order.status == OrderStatus.cancelled
                          ? AppColors.gray400
                          : AppColors.navy,
                      fontWeight: FontWeight.w700)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel this order?'),
        content: Text(
          '${order.listing.size} from ${order.vendorName} — the vendor hasn\'t accepted it yet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text('Keep order', style: TextStyle(color: AppColors.gray600)),
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
                            padding:
                                const EdgeInsets.symmetric(horizontal: 48),
                            child: ElevatedButton(
                              onPressed: _goToOrder,
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
    // A Google account has no password to change.
    final isGoogleAccount = FirebaseAuth.instance.currentUser?.providerData
            .any((p) => p.providerId == 'google.com') ??
        false;

    // The green tick means "we checked an ID", not "this person has an
    // avatar". A Google customer's selfieUrl is just their Google photo.
    final isIdVerified = customer.nationalId.trim().isNotEmpty;

    final landmark = _dedupeJoin(customer.estate, customer.county);
    final hasPin = customer.latitude != 0 && customer.longitude != 0;
    final location = landmark.isNotEmpty
        ? landmark
        : hasPin
            ? 'Pinned on map'
            : 'Not set';
    final initial =
        customer.name.trim().isEmpty ? '?' : customer.name[0].toUpperCase();

    return SingleChildScrollView(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: customer.selfieUrl != null
                      ? () => _showSelfie(context, customer.selfieUrl!,
                          verified: isIdVerified)
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
                            ? Text(initial,
                                style: const TextStyle(
                                    color: AppColors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700))
                            : null,
                      ),
                      if (isIdVerified)
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.orange,
                                      fontWeight: FontWeight.w600,
                                    )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                customer.phone.trim().isEmpty
                    ? GestureDetector(
                        onTap: () =>
                            ProfileCompletionSheet.show(context, initialStep: 0),
                        child: Text('Add your phone number',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                )),
                      )
                    : Text(customer.phone,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.gray400)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                if ((customer.email ?? '').isNotEmpty)
                  _profileTile(Icons.email_outlined, 'Email', customer.email!),
                if (customer.nationalId.trim().isNotEmpty)
                  _profileTile(Icons.badge_outlined, 'National ID',
                      customer.nationalId),
                _profileTile(
                    Icons.location_on_outlined, 'Location', location),
                const SizedBox(height: 8),
                if (!isGoogleAccount)
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
                _profileAction(Icons.help_outline_rounded, 'Help & support',
                    onTap: () => context.push('/support')),
                _profileAction(Icons.info_outline_rounded, 'About MobiGas',
                    onTap: () => _showAbout(context)),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final router = GoRouter.of(context);
                    await auth.logout();
                    router.go('/');
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

  /// Joins two location parts without duplication — if either
  /// contains the other (e.g. estate already ends with the county),
  /// just use the longer one.
  static String _dedupeJoin(String a, String b) {
    final x = a.trim();
    final y = b.trim();
    if (x.isEmpty) return y;
    if (y.isEmpty) return x;
    if (x.toLowerCase().contains(y.toLowerCase())) return x;
    if (y.toLowerCase().contains(x.toLowerCase())) return y;
    return '$x, $y';
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: highlight ? AppColors.success : AppColors.navy,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400)),
        trailing: Icon(Icons.arrow_forward_ios_rounded,
            size: 14, color: highlight ? AppColors.success : AppColors.gray400),
        onTap: onTap ?? () {},
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
      _NavItem(
          Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
      _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
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
                        color: isActive ? AppColors.orange : AppColors.gray400,
                        size: 24,
                      ),
                      const SizedBox(height: 4),
                      Text(item.label,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
  void _showSelfie(BuildContext context, String selfieUrl,
      {required bool verified}) {
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
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.orange)),
              ),
            ),
            if (verified) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                            )),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('Close', style: TextStyle(color: AppColors.white)),
            ),
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
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        // Keeps the last tile clear of the system navigation bar.
        child: SafeArea(
          top: false,
          child: Padding(
          padding: const EdgeInsets.all(24),
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
                      FirestoreService.markAllNotificationsRead(customerId),
                  child: Text('Mark all read',
                      style: TextStyle(color: AppColors.orange, fontSize: 13)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child:
                      Text('Close', style: TextStyle(color: AppColors.orange)),
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
                        child:
                            CircularProgressIndicator(color: AppColors.orange));
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
                            'Order and delivery updates\nwill appear here',
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
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = notifications[i];
                      final isRead = n['read'] == true;
                      final createdAt = n['createdAt'] as DateTime?;
                      return Dismissible(
                        key: ValueKey(n['id']),
                        direction: DismissDirection.endToStart,
                        onDismissed: (_) => FirestoreService.deleteNotification(
                            n['id'] as String),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
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
                                  : AppColors.orange.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: isRead
                                      ? AppColors.gray200
                                      : AppColors.orange
                                          .withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isRead)
                                  Container(
                                    margin: const EdgeInsets.only(top: 5),
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
                                                  color: AppColors.gray600,
                                                  height: 1.4)),
                                      if (createdAt != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                            '${createdAt.day}/${createdAt.month}/${createdAt.year} · ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: AppColors.gray400,
                                                    fontSize: 10)),
                                      ],
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      FirestoreService.deleteNotification(
                                          n['id'] as String),
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(Icons.close_rounded,
                                        size: 16, color: AppColors.gray400),
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
      ),
    );
  }

  void _showChangePassword(BuildContext context) {
    final controller = TextEditingController();
    final currentController = TextEditingController();
    var saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
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
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: AppColors.navy)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: currentController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    hintText: 'Current password',
                    prefixIcon: Icon(Icons.lock_clock_outlined,
                        color: AppColors.gray400, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: controller,
                  obscureText: true,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    hintText: 'New password — letters and numbers',
                    prefixIcon: Icon(Icons.lock_outline_rounded,
                        color: AppColors.gray400, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(sheetContext);
                          final next = controller.text;
                          final current = currentController.text;

                          if (next.length < 6 ||
                              !RegExp(r'[A-Za-z]').hasMatch(next) ||
                              !RegExp(r'[0-9]').hasMatch(next)) {
                            messenger.showSnackBar(const SnackBar(
                              content: Text(
                                  'Password needs 6+ characters, a letter and a number'),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ));
                            return;
                          }

                          setSheetState(() => saving = true);
                          try {
                            final user = FirebaseAuth.instance.currentUser!;
                            // Firebase requires a recent login before a
                            // password change — reauthenticate first.
                            await user.reauthenticateWithCredential(
                              EmailAuthProvider.credential(
                                email: user.email!,
                                password: current,
                              ),
                            );
                            await user.updatePassword(next);
                            navigator.pop();
                            messenger.showSnackBar(const SnackBar(
                              content: Text('Password updated'),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                            ));
                          } on FirebaseAuthException catch (e) {
                            setSheetState(() => saving = false);
                            messenger.showSnackBar(SnackBar(
                              content: Text(e.code == 'wrong-password' ||
                                      e.code == 'invalid-credential'
                                  ? 'Current password is incorrect'
                                  : 'Could not update password. Try again.'),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ));
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: AppColors.white),
                        )
                      : const Text('Update password'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// About sheet.
  ///
  /// Without `isScrollControlled` the sheet is capped at 9/16 of the
  /// screen height, and without SafeArea it draws *under* the system
  /// navigation bar — which is why the last line of the description
  /// sat behind the gesture pill. The SingleChildScrollView keeps it
  /// usable on short screens rather than overflowing.
  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.gray200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
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
                Text('Gas delivered in minutes',
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
                  'MobiGas connects you with trusted local gas vendors for fast delivery — compare prices, order in seconds, and pay cash or mobile money when your gas arrives.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppColors.gray600, height: 1.5),
                ),
                const SizedBox(height: 20),
                // Play wants Terms and Privacy reachable in-app, and
                // About is where a reviewer goes looking for them.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () {
                        // Pop the sheet first, then push on the
                        // screen's context — not the sheet's.
                        Navigator.pop(sheetContext);
                        context.push('/terms');
                      },
                      child: Text('Terms of Service',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.orange,
                                    decoration: TextDecoration.underline,
                                  )),
                    ),
                    Text('  ·  ',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray400)),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(sheetContext);
                        context.push('/privacy');
                      },
                      child: Text('Privacy Policy',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.orange,
                                    decoration: TextDecoration.underline,
                                  )),
                    ),
                  ],
                ),
              ],
            ),
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