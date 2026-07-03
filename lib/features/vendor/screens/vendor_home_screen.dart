import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/features/vendor/screens/vendor_edit_profile_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_setup_screen.dart';
import 'package:mobigas/features/vendor/screens/stock_loan_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_order_screen.dart';
import 'package:mobigas/core/widgets/double_back_to_exit.dart';

class VendorHomeScreen extends StatefulWidget {
  const VendorHomeScreen({super.key});

  @override
  State<VendorHomeScreen> createState() => _VendorHomeScreenState();
}

class _VendorHomeScreenState extends State<VendorHomeScreen> {
  int _currentTab = 0;
  bool _isOnline = false;
  Map<String, dynamic>? _vendorData;
  bool _isLoadingVendor = true;

  String get _vendorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadVendorData();
  }

  Future<void> _loadVendorData() async {
    if (_vendorId.isEmpty) {
      setState(() => _isLoadingVendor = false);
      return;
    }
    try {
      final doc = await FirebaseService.vendors.doc(_vendorId).get();
      if (!mounted) return;
      if (doc.exists) {
        setState(() {
          _vendorData = doc.data() as Map<String, dynamic>;
          _isOnline = _vendorData?['isOnline'] ?? false;
          _isLoadingVendor = false;
        });
      } else {
        // New vendor — no profile yet, show setup banner
        setState(() {
          _vendorData = null;
          _isLoadingVendor = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingVendor = false);
    }
  }

  Future<void> _toggleOnline() async {
    if (_vendorData?['isVerified'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Your account is pending approval. You cannot go online yet.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    final newStatus = !_isOnline;
    setState(() => _isOnline = newStatus);
    await FirebaseService.vendors.doc(_vendorId).update({
      'isOnline': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<OrderModel>> get _pendingOrdersStream {
    return FirebaseService.orders
        .where('vendorId', isEqualTo: _vendorId)
        .where('status', whereIn: [
          OrderStatus.pending.name,
          OrderStatus.accepted.name,
          OrderStatus.outForDelivery.name,
        ])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _orderFromMap(doc.id, data);
            }).toList());
  }

  Stream<List<OrderModel>> get _completedOrdersStream {
    return FirebaseService.orders
        .where('vendorId', isEqualTo: _vendorId)
        .where('status', isEqualTo: OrderStatus.delivered.name)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return _orderFromMap(doc.id, data);
            }).toList());
  }

  OrderModel _orderFromMap(String docId, Map<String, dynamic> data) {
    return OrderModel(
      orderId: data['orderId'] ?? docId,
      customerId: data['customerId'] ?? '',
      vendorId: data['vendorId'] ?? '',
      vendorName: data['vendorName'] ?? '',
      vendorPhone: data['vendorPhone'] ?? '',
      customerName: data['customerName'] ?? '',
      customerArea: data['customerArea'] ?? '',
      listing: GasListing(
        size: data['gasSize'] ?? '',
        kg: data['gasKg'] ?? 0,
        price: (data['gasPrice'] ?? 0).toDouble(),
        available: true,
      ),
      bankDisbursementAmount:
          (data['bankDisbursementAmount'] ?? 0).toDouble(),
      originationFeeToMobigas:
          (data['originationFeeToMobigas'] ?? 0).toDouble(),
      pin: data['pin'] ?? '',
      status: OrderStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => OrderStatus.pending,
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      partnerBankName: data['partnerBankName'] ?? '',
      riderName: data['riderName'],
      riderPhone: data['riderPhone'],
    );
  }

  Future<void> _acceptOrder(OrderModel order) async {
    await FirebaseService.orders
        .where('orderId', isEqualTo: order.orderId)
        .get()
        .then((snap) {
      if (snap.docs.isNotEmpty) {
        snap.docs.first.reference.update({
          'status': OrderStatus.accepted.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> _declineOrder(OrderModel order) async {
    await FirebaseService.orders
        .where('orderId', isEqualTo: order.orderId)
        .get()
        .then((snap) {
      if (snap.docs.isNotEmpty) {
        snap.docs.first.reference.update({
          'status': OrderStatus.defaulted.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingVendor) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.orange)),
      );
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
                  _buildHomeTab(),
                  _buildOrdersTab(),
                  _buildEarningsTab(),
                  _buildProfileTab(),
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
  Widget _buildHomeTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildVendorHeader(),
          // Setup incomplete banner
          if (_vendorData == null || (_vendorData?['businessName'] ?? '').isEmpty)
            GestureDetector(
              onTap: () async {
                final done = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VendorSetupScreen(
                        existingData: _vendorData),
                  ),
                );
                if (done == true) _loadVendorData();
              },
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppColors.orange.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.store_outlined,
                        color: AppColors.orange, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Complete your business setup',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Add your business details and gas prices to start receiving orders',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: AppColors.orange,
                                  height: 1.4,
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
            )
          else if (_vendorData?['isVerified'] != true)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded,
                      color: AppColors.warning, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pending verification',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'MobiGas is reviewing your details before activating your account.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.warning,
                                height: 1.4,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final done = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VendorSetupScreen(
                              existingData: _vendorData),
                        ),
                      );
                      if (done == true) _loadVendorData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            AppColors.warning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('Edit',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              )),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildOnlineToggle(),
                const SizedBox(height: 20),
                _buildStatsRow(),
                const SizedBox(height: 20),
                _buildIncomingOrders(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorHeader() {
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
                    'Welcome back 👋',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.gray400,
                        ),
                  ),
                  Text(
                    _vendorData?['businessName'] ?? 'Vendor',
                    style: Theme.of(context)
                        .textTheme
                        .displayMedium
                        ?.copyWith(
                          color: AppColors.white,
                          fontSize: 20,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? AppColors.success.withValues(alpha: 0.2)
                      : AppColors.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? AppColors.success
                            : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: _isOnline
                                ? AppColors.success
                                : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_vendorData?['address'] ?? _vendorData?['estate'] ?? ''}, ${_vendorData?['county'] ?? ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnlineToggle() {
    return GestureDetector(
      onTap: _toggleOnline,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _isOnline ? AppColors.success : AppColors.gray400,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _isOnline
              ? [
                  BoxShadow(
                    color: AppColors.success.withValues(alpha: 0.4),
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
              child: Icon(
                _isOnline
                    ? Icons.wifi_rounded
                    : Icons.wifi_off_rounded,
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
                    _isOnline
                        ? 'You are online'
                        : 'You are offline',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          color: AppColors.white,
                          fontSize: 18,
                        ),
                  ),
                  Text(
                    _isOnline
                        ? 'Receiving new orders · Tap to go offline'
                        : 'Not receiving orders · Tap to go online',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return StreamBuilder<List<OrderModel>>(
      stream: _completedOrdersStream,
      builder: (context, snap) {
        final orders = snap.data ?? [];
        final todayOrders = orders.where((o) {
          final now = DateTime.now();
          return o.createdAt.day == now.day &&
              o.createdAt.month == now.month &&
              o.createdAt.year == now.year;
        }).toList();
        final todayEarnings =
            todayOrders.fold(0.0, (acc, o) => acc + o.bankDisbursementAmount);
        final totalEarnings = orders.fold(
            0.0, (acc, o) => acc + o.bankDisbursementAmount);

        return Row(
          children: [
            _statCard('Today',
                'KES ${todayEarnings.toStringAsFixed(0)}',
                Icons.today_rounded, AppColors.orange),
            const SizedBox(width: 12),
            _statCard('Total earnings',
                'KES ${totalEarnings.toStringAsFixed(0)}',
                Icons.account_balance_wallet_rounded, AppColors.success),
            const SizedBox(width: 12),
            _statCard('Deliveries',
                '${orders.length}',
                Icons.local_shipping_rounded, AppColors.navy),
          ],
        );
      },
    );
  }



  Widget _statCard(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gray200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    )),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      fontSize: 10,
                    )),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingOrders() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Incoming orders',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 12),
        StreamBuilder<List<OrderModel>>(
          stream: _pendingOrdersStream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                  child:
                      CircularProgressIndicator(color: AppColors.orange));
            }
            final orders = snap.data ?? [];
            if (orders.isEmpty) {
              return _buildNoOrders();
            }
            return Column(
              children: orders.map((o) => _orderCard(o)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNoOrders() {
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
          const Icon(Icons.inbox_outlined,
              size: 48, color: AppColors.gray400),
          const SizedBox(height: 12),
          Text(
            _isOnline ? 'No orders yet' : 'You are offline',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.gray600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _isOnline
                ? 'New orders will appear here in real-time'
                : 'Go online to start receiving orders',
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

  Widget _orderCard(OrderModel order) {
    final isPending = order.status == OrderStatus.pending;
    final isAccepted = order.status == OrderStatus.accepted;
    final isOutForDelivery =
        order.status == OrderStatus.outForDelivery;

    Color statusColor = isPending
        ? AppColors.warning
        : isAccepted
            ? AppColors.orange
            : AppColors.success;
    String statusLabel = isPending
        ? 'New order'
        : isAccepted
            ? 'Accepted'
            : 'Out for delivery';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Status bar
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(statusLabel,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        )),
                const Spacer(),
                Text(order.orderId,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray400,
                          fontSize: 10,
                        )),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.customerName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: AppColors.navy,
                                    fontWeight: FontWeight.w700,
                                  )),
                          Text(order.customerArea,
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
                          'KES ${order.bankDisbursementAmount.toStringAsFixed(0)}',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                color: AppColors.navy,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                        ),
                        Text(order.listing.size,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.orange)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Action buttons
                if (isPending) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _declineOrder(order),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(
                                color: AppColors.error),
                          ),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => _acceptOrder(order),
                          child: const Text('Accept order'),
                        ),
                      ),
                    ],
                  ),
                ] else if (isAccepted || isOutForDelivery) ...[
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VendorOrderScreen(order: order),
                      ),
                    ),
                    child: Text(isAccepted
                        ? 'Start delivery'
                        : 'Continue delivery'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ORDERS TAB ────────────────────────────────────────────────────
  Widget _buildOrdersTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          color: AppColors.navy,
          child: Row(children: [
            Text('All orders',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                    )),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: _completedOrdersStream,
            builder: (context, snap) {
              final orders = snap.data ?? [];
              if (orders.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.receipt_long_outlined,
                          size: 64, color: AppColors.gray400),
                      const SizedBox(height: 16),
                      Text('No completed orders yet',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.gray600)),
                    ],
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: orders.length,
                itemBuilder: (_, i) => _completedOrderTile(orders[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _completedOrderTile(OrderModel order) {
    final dateStr =
        '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}';
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
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(order.customerName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 14, color: AppColors.navy)),
                Text('${order.listing.size} · $dateStr',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.gray400)),
              ],
            ),
          ),
          Text(
              'KES ${order.bankDisbursementAmount.toStringAsFixed(0)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 14,
                    color: AppColors.success,
                    fontWeight: FontWeight.w700,
                  )),
        ],
      ),
    );
  }

  // ── EARNINGS TAB ──────────────────────────────────────────────────
  Widget _buildEarningsTab() {
    return StreamBuilder<List<OrderModel>>(
      stream: _completedOrdersStream,
      builder: (context, snap) {
        final orders = snap.data ?? [];
        final total =
            orders.fold(0.0, (acc, o) => acc + o.bankDisbursementAmount);
        final today = orders.where((o) {
          final now = DateTime.now();
          return o.createdAt.day == now.day;
        }).fold(0.0, (acc, o) => acc + o.bankDisbursementAmount);

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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total earnings',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.gray400)),
                    Text(
                      'KES ${total.toStringAsFixed(0)}',
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(
                            color: AppColors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text('Today: KES ${today.toStringAsFixed(0)}',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.orange)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stock Boost Loan
                    if (FeatureFlags.stockBoostLoan)
                      _buildStockBoostCard(orders.length, orders),
                    if (FeatureFlags.stockBoostLoan)
                      const SizedBox(height: 20),
                    Text('${orders.length} deliveries completed',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppColors.navy)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.gray200),
                      ),
                      child: Column(
                        children: [
                          _earningsRow('Bank pays vendor directly',
                              'On PIN confirmation'),
                          _earningsRow('Your M-Pesa',
                              _vendorData?['phone'] ?? ''),
                          _earningsRow('Payment method',
                              'Instant M-Pesa transfer'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockBoostCard(int totalDeliveries, List<OrderModel> orders) {
    final createdAt = _vendorData?['createdAt'];
    int monthsOnPlatform = 0;
    if (createdAt != null) {
      try {
        final joined = (createdAt as dynamic).toDate() as DateTime;
        monthsOnPlatform = DateTime.now().difference(joined).inDays ~/ 30;
      } catch (_) {}
    }
    final isEligible = monthsOnPlatform >= 3 && totalDeliveries >= 30;
    final monthlyRevenue = orders.isEmpty || monthsOnPlatform == 0
        ? 0.0
        : orders.fold(0.0, (acc, o) => acc + o.bankDisbursementAmount) /
            monthsOnPlatform;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isEligible ? null : AppColors.navy,
        gradient: isEligible ? LinearGradient(
          colors: [AppColors.orange, AppColors.orangeDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ) : null,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEligible ? AppColors.orange : AppColors.orange.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.rocket_launch_rounded,
                color: AppColors.white, size: 22),
            const SizedBox(width: 10),
            Text('Stock Boost Loan',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(isEligible ? 'Eligible!' : 'Not yet eligible',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            isEligible
                ? 'You qualify! Get funding to buy more gas stock and grow your business.'
                : 'Deliver consistently for 3 months to unlock a stock loan. '
                  'Use the app actively — every delivery brings you closer!',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.white,
                  height: 1.5,
                  fontSize: 13)),
          if (!isEligible) ...[
            const SizedBox(height: 12),
            if (monthsOnPlatform < 3)
              _eligibilityBar('Months on platform',
                  monthsOnPlatform, 3, '\$monthsOnPlatform/3 months'),
            const SizedBox(height: 6),
            if (totalDeliveries < 30)
              _eligibilityBar('Total deliveries',
                  totalDeliveries, 30, '\$totalDeliveries/30 deliveries'),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: isEligible
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StockLoanScreen(
                          monthsOnPlatform: monthsOnPlatform,
                          totalDeliveries: totalDeliveries,
                          averageMonthlyRevenue: monthlyRevenue,
                          vendorData: _vendorData ?? {},
                        ),
                      ),
                    )
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isEligible
                  ? AppColors.white
                  : AppColors.white.withValues(alpha: 0.15),
              foregroundColor:
                  isEligible ? AppColors.orange : AppColors.gray400,
              minimumSize: const Size(double.infinity, 44),
              elevation: 0,
            ),
            child: Text(
              isEligible
                  ? 'Apply for stock loan'
                  : monthsOnPlatform == 0
                      ? 'Start delivering to unlock'
                      : 'Keep delivering — ${3 - monthsOnPlatform} month${(3 - monthsOnPlatform) == 1 ? '' : 's'} to go',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eligibilityBar(String label, int current, int max, String text) {
    final progress = (current / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white.withValues(alpha: 0.7),
                    fontSize: 11)),
          const Spacer(),
          Text(text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: AppColors.white.withValues(alpha: 0.15),
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.orange),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _earningsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
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

  // ── PROFILE TAB ───────────────────────────────────────────────────
  Widget _buildProfileTab() {
    final user = FirebaseAuth.instance.currentUser;
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
                  backgroundImage: (_vendorData?['photoUrl'] ?? user?.photoURL) != null
                      ? NetworkImage(_vendorData?['photoUrl'] ?? user!.photoURL!)
                      : null,
                  child: (_vendorData?['photoUrl'] ?? user?.photoURL) == null
                      ? Text(
                          (_vendorData?['businessName'] ?? 'V')[0],
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _vendorData?['businessName'] ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppColors.white),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final updated = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VendorEditProfileScreen(
                            vendorData: _vendorData ?? {}),
                      ),
                    );
                    if (updated == true) _loadVendorData();
                  },
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
                Text(
                  user?.email ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.gray400),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: (_vendorData?['isVerified'] == true
                            ? AppColors.success
                            : AppColors.warning)
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _vendorData?['isVerified'] == true
                        ? 'Verified vendor ✓'
                        : 'Pending verification ⏳',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: _vendorData?['isVerified'] == true
                              ? AppColors.success
                              : AppColors.warning,
                          fontWeight: FontWeight.w600,
                        )),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _profileTile(Icons.store_outlined, 'Business name',
                    _vendorData?['businessName'] ?? ''),
                _profileTile(Icons.phone_outlined, 'M-Pesa number',
                    _vendorData?['phone'] ?? ''),
                _profileTile(Icons.location_on_outlined, 'Location',
                    '${_vendorData?['address'] ?? _vendorData?['estate'] ?? ''}'),
                _profileTile(Icons.local_gas_station_outlined,
                    'Brands',
                    (_vendorData?['brands'] as List?)?.join(', ') ?? ''),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final done = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VendorSetupScreen(existingData: _vendorData),
                      ),
                    );
                    if (done == true) _loadVendorData();
                  },
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit business & gas prices'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors.orange.withValues(alpha: 0.15),
                    foregroundColor: AppColors.orange,
                    elevation: 0,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context.push('/vendor-support'),
                  icon: const Icon(Icons.support_agent_rounded, size: 18),
                  label: const Text('Help & Support'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.orange,
                    side: const BorderSide(color: AppColors.orange),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) context.go('/');
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
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w600,
                    )),
          ),
        ],
      ),
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    final items = [
      _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
      _NavItem(Icons.receipt_long_outlined,
          Icons.receipt_long_rounded, 'Orders'),
      _NavItem(Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet_rounded, 'Earnings'),
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
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
