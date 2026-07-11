import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/google_auth_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/features/vendor/screens/vendor_edit_profile_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_setup_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_order_screen.dart';
import 'package:mobigas/features/vendor/screens/vendor_statistics_screen.dart';
import 'package:mobigas/features/shared/refer_earn_screen.dart';
import 'package:mobigas/core/widgets/double_back_to_exit.dart';
import 'package:mobigas/core/widgets/vendor_fees_banner.dart';

/// Server-computed earnings. Reading every delivered order just to add
/// up a number does not scale, and capping the read at N silently
/// caps the number too — a vendor with 50 deliveries would watch their
/// "total earnings" stop growing at 20.
class _VendorEarnings {
  final double total;
  final double today;
  final int deliveries;
  const _VendorEarnings({
    required this.total,
    required this.today,
    required this.deliveries,
  });
  static const zero = _VendorEarnings(total: 0, today: 0, deliveries: 0);
}

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
  StreamSubscription<User?>? _authSub;

  _VendorEarnings? _earnings;
  bool _earningsFailed = false;

  String get _vendorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _businessName => (_vendorData?['businessName'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    // BUG FIX: reading currentUser once, right here, could catch
    // Firebase Auth mid-restore on a fresh install/cold start — the
    // session is being silently re-established (especially with
    // Google Sign-In's cached Play Services credential) but hasn't
    // finished yet, so currentUser is still null for a moment. The
    // old code saw an empty _vendorId, gave up immediately, and
    // never tried again — leaving the screen blank until the vendor
    // manually logged out and back in. Listening instead guarantees
    // we load the profile the moment a real user becomes available,
    // however long that takes.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _refreshAll();
    });
    // Also try immediately, in case auth is already resolved (the
    // normal case for anyone who didn't just reinstall).
    _refreshAll();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadVendorData(), _loadEarnings()]);
  }

  Future<void> _loadVendorData() async {
    if (_vendorId.isEmpty) {
      // Don't give up permanently — authStateChanges will call this
      // again once a user actually becomes available.
      if (mounted) setState(() => _isLoadingVendor = false);
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

  /// Totals come from Firestore aggregate queries — sum() and count()
  /// run server-side and cost roughly one document read each, however
  /// many delivered orders the vendor has. The alternative (streaming
  /// every order and folding over it) gets slower and more expensive
  /// with every delivery, which is backwards.
  ///
  /// Trade-off: aggregates are a Future, not a Stream, so these
  /// numbers refresh on pull-to-refresh and after an order completes
  /// rather than tick live. Correct and slightly stale beats live and
  /// wrong.
  Future<void> _loadEarnings() async {
    if (_vendorId.isEmpty) return;

    final base = FirebaseService.orders
        .where('vendorId', isEqualTo: _vendorId)
        .where('status', isEqualTo: OrderStatus.delivered.name);

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    try {
      final allSnap = await base.aggregate(sum('gasPrice'), count()).get();
      final todaySnap = await base
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .aggregate(sum('gasPrice'))
          .get();

      if (!mounted) return;
      setState(() {
        _earnings = _VendorEarnings(
          total: allSnap.getSum('gasPrice') ?? 0,
          deliveries: allSnap.count ?? 0,
          today: todaySnap.getSum('gasPrice') ?? 0,
        );
        _earningsFailed = false;
      });
    } catch (e) {
      // Most likely a missing composite index the first time this
      // runs — Firestore prints a create-index link in the console.
      debugPrint('Earnings aggregate failed: $e');
      if (mounted) setState(() => _earningsFailed = true);
    }
  }

  /// Mirrors VendorModel.documentsSubmitted (app_models.dart) — kept
  /// as a raw-map check here since this screen reads _vendorData
  /// directly rather than through the model. Update both together.
  bool get _documentsSubmitted {
    String s(String key) => (_vendorData?[key] ?? '').toString();
    final hasEpraProof = s('epraCertificateUrl').isNotEmpty ||
        s('subDealerAuthorizationUrl').isNotEmpty;
    final hasScaleProof = s('weighingScaleCertUrl').isNotEmpty ||
        s('weighingScalePhotoUrl').isNotEmpty;
    final hasBrandProof = s('brandAuthorizationUrl').isNotEmpty ||
        s('dealerAssociationLetterUrl').isNotEmpty;
    final isSole = (_vendorData?['businessType'] ?? 'sole') == 'sole';
    final hasBusinessReg = !isSole || s('businessRegistrationUrl').isNotEmpty;
    return hasEpraProof &&
        s('businessPermitUrl').isNotEmpty &&
        s('fireCertificateUrl').isNotEmpty &&
        s('premisesPhotoUrl').isNotEmpty &&
        hasScaleProof &&
        hasBrandProof &&
        hasBusinessReg;
  }

  Future<void> _toggleOnline() async {
    // Going online requires admin-approved verification, not just
    // self-reported document upload — documentsSubmitted is spoofable
    // (a vendor could upload blank images), so it's not a real gate.
    // isVerified is the only flag a human has actually checked.
    if (_vendorData?['isVerified'] != true) {
      final docsIn = _documentsSubmitted;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(docsIn
              ? 'Your documents are under review. You can go online as soon as MobiGas approves your account.'
              : 'Upload your verification documents before going online.'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final newStatus = !_isOnline;
    setState(() => _isOnline = newStatus);
    try {
      await FirebaseService.vendors.doc(_vendorId).update({
        'isOnline': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // The write failed but the toggle already flipped — a vendor
      // sitting on a green "You are online" badge while Firestore
      // still says offline will never understand why no orders come.
      if (!mounted) return;
      setState(() => _isOnline = !newStatus);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Could not update your status. Check your connection.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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

  /// The 20 most recent completed orders, for the Orders tab list.
  /// This limit is about how many rows to render — earnings totals do
  /// NOT derive from it (see _loadEarnings).
  Stream<List<OrderModel>> get _recentCompletedOrdersStream {
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
      customerPhone: data['customerPhone'] ?? '',
      // BUG FIX: this local copy of the mapper silently dropped the
      // customer's coordinates, so every OrderModel handed to
      // VendorOrderScreen carried 0,0 and any map or navigation
      // pointed at the Gulf of Guinea. The FirestoreService mapper
      // always had these; the two drifted because this one exists.
      customerLatitude: (data['customerLatitude'] ?? 0.0).toDouble(),
      customerLongitude: (data['customerLongitude'] ?? 0.0).toDouble(),
      listing: GasListing(
        size: data['gasSize'] ?? '',
        kg: data['gasKg'] ?? 0,
        price: (data['gasPrice'] ?? 0).toDouble(),
        available: true,
        productType: GasProductType.values.firstWhere(
          (t) => t.name == (data['gasProductType'] ?? 'refill'),
          orElse: () => GasProductType.refill,
        ),
        brand: data['gasBrand'] ?? '',
      ),
      paymentMethod: PaymentMethod.values.firstWhere(
        (m) => m.name == (data['paymentMethod'] ?? 'cash'),
        orElse: () => PaymentMethod.cash,
      ),
      finderFee: (data['finderFee'] ?? 0).toDouble(),
      cancelledBy: data['cancelledBy'],
      bankDisbursementAmount: (data['bankDisbursementAmount'] ?? 0).toDouble(),
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

  /// Accepting re-reads the order first. The vendor's list can be a
  /// few seconds stale, and the old code wrote `status: accepted`
  /// unconditionally — a customer who cancelled while the vendor was
  /// deciding would find their order resurrected. The write also
  /// wasn't awaited, so failures vanished.
  Future<void> _acceptOrder(OrderModel order) async {
    try {
      final snap = await FirebaseService.orders
          .where('orderId', isEqualTo: order.orderId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return;

      final doc = snap.docs.first;
      final current = (doc.data() as Map<String, dynamic>)['status'];
      if (current != OrderStatus.pending.name) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(current == OrderStatus.cancelled.name
                ? 'This order was cancelled by the customer.'
                : 'This order is no longer pending.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      await doc.reference.update({
        'status': OrderStatus.accepted.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not accept the order. Try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _declineOrder(OrderModel order) async {
    // Goes through the service so declines are handled consistently
    // (status update + customer notification).
    await FirestoreService.updateOrderStatus(
        order.orderId, OrderStatus.cancelled,
        cancelledBy: 'vendor');
  }

  /// launchUrl RETURNS false on failure — it does not throw. The old
  /// try/catch could never fire, so on a device with no dialer the
  /// Call button silently did nothing.
  Future<void> _callCustomer(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open the phone app. Call $phone directly.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingVendor) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(child: CircularProgressIndicator(color: AppColors.orange)),
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
    return RefreshIndicator(
      color: AppColors.orange,
      backgroundColor: AppColors.white,
      onRefresh: _refreshAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            _buildVendorHeader(),
            // Platform fees (cash-order finder fees) banner
            const VendorFeesBanner(),
            if (_vendorData == null || _businessName.isEmpty)
              _setupBanner()
            else if (!_documentsSubmitted)
              _documentsBanner()
            else if (_vendorData?['isVerified'] != true)
              _underReviewBanner(),
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
      ),
    );
  }

  Widget _setupBanner() {
    return GestureDetector(
      onTap: () async {
        final done = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VendorSetupScreen(existingData: _vendorData),
          ),
        );
        if (done == true) _refreshAll();
      },
      child: _banner(
        icon: Icons.store_outlined,
        color: AppColors.orange,
        title: 'Complete your business setup',
        body:
            'Add your business details and gas prices to start receiving orders',
        showChevron: true,
      ),
    );
  }

  Widget _documentsBanner() {
    // No customer will see this vendor until these are submitted AND
    // approved — but they can go online and prepare their shop in the
    // meantime.
    return GestureDetector(
      onTap: () async {
        final done = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VendorSetupScreen(
                existingData: _vendorData,
                mode: VendorEditMode.documentsOnly),
          ),
        );
        if (done == true) _refreshAll();
      },
      child: _banner(
        icon: Icons.fact_check_outlined,
        color: AppColors.orange,
        title: 'Get your verified badge',
        body:
            'Upload your EPRA certificate, business permit, fire certificate and the rest — customers only see verified vendors',
        showChevron: true,
      ),
    );
  }

  Widget _underReviewBanner() {
    // All documents are in — now it's on MobiGas, not the vendor.
    // Informational only; nothing actionable left for them to tap.
    return _banner(
      icon: Icons.hourglass_top_rounded,
      color: AppColors.warning,
      title: 'Documents under review',
      body:
          'MobiGas is verifying your documents. You can prepare orders now — customers will see you as soon as you\'re approved.',
      showChevron: false,
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    required bool showChevron,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        )),
                const SizedBox(height: 2),
                Text(body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: color,
                          height: 1.4,
                          fontSize: 11,
                        )),
              ],
            ),
          ),
          if (showChevron)
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
        ],
      ),
    );
  }

  /// Joins two location parts without duplication — if either
  /// contains the other (e.g. address already ends with the county),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back 👋',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.gray400,
                          ),
                    ),
                    Text(
                      _businessName.isEmpty ? 'Vendor' : _businessName,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            color: AppColors.white,
                            fontSize: 20,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        color: _isOnline ? AppColors.success : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                _isOnline ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildNotificationBell(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _dedupeJoin(
                (_vendorData?['address'] ?? _vendorData?['estate'] ?? '')
                    .toString(),
                (_vendorData?['county'] ?? '').toString()),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
        ],
      ),
    );
  }

  /// Notification bell with unread badge — mirrors the customer app's
  /// bell. Notifications are stored by auth uid (userId == _vendorId),
  /// written by notification_service.dart when a push arrives, so the
  /// same FirestoreService.watchNotifications stream works here.
  Widget _buildNotificationBell() {
    if (_vendorId.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.watchNotifications(_vendorId),
      builder: (context, snap) {
        final unreadCount =
            (snap.data ?? []).where((n) => n['read'] != true).length;
        return GestureDetector(
          onTap: () => _showNotifications(context, _vendorId),
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
                    constraints:
                        const BoxConstraints(minWidth: 18, minHeight: 18),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: AppColors.navy, width: 1.5),
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
    );
  }

  void _showNotifications(BuildContext context, String userId) {
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
                          FirestoreService.markAllNotificationsRead(userId),
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
                    stream: FirestoreService.watchNotifications(userId),
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
                            onDismissed: (_) =>
                                FirestoreService.deleteNotification(
                                    n['id'] as String),
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
                                                        color:
                                                            AppColors.gray400,
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

  Widget _buildOnlineToggle() {
    final isVerified = _vendorData?['isVerified'] == true;
    return GestureDetector(
      onTap: _toggleOnline,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: !isVerified
              ? AppColors.gray400.withValues(alpha: 0.5)
              : _isOnline
                  ? AppColors.success
                  : AppColors.gray400,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _isOnline && isVerified
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
                !isVerified
                    ? Icons.lock_outline_rounded
                    : _isOnline
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
                    !isVerified
                        ? 'Locked until verified'
                        : _isOnline
                            ? 'You are online'
                            : 'You are offline',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.white,
                          fontSize: 18,
                        ),
                  ),
                  Text(
                    !isVerified
                        ? 'Complete verification above to unlock'
                        : _isOnline
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

  String _money(double? v) =>
      v == null ? '—' : 'KES ${v.toStringAsFixed(0)}';

  Widget _buildStatsRow() {
    final e = _earnings;
    return Row(
      children: [
        _statCard('Today', _money(e?.today), Icons.today_rounded,
            AppColors.orange),
        const SizedBox(width: 12),
        _statCard('Total earnings', _money(e?.total),
            Icons.account_balance_wallet_rounded, AppColors.success),
        const SizedBox(width: 12),
        _statCard('Deliveries', e == null ? '—' : '${e.deliveries}',
            Icons.two_wheeler_rounded, AppColors.navy),
      ],
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
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
                  child: CircularProgressIndicator(color: AppColors.orange));
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
          const Icon(Icons.inbox_outlined, size: 48, color: AppColors.gray400),
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
    final isOutForDelivery = order.status == OrderStatus.outForDelivery;

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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        )),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Pay on delivery',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
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
                          'KES ${order.listing.price.toStringAsFixed(0)}',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
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
                const SizedBox(height: 10),
                // BUG FIX: previously a vendor saw only name, area,
                // price, and size before deciding to accept — no
                // product type, no brand, no way to check they
                // actually stock what's being asked for, and no
                // phone number to call the customer.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.gray100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            order.listing.productType.isAccessoryOnly
                                ? Icons.build_outlined
                                : Icons.local_fire_department_outlined,
                            size: 15,
                            color: AppColors.gray600,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              order.listing.brand.isNotEmpty
                                  ? '${order.listing.brand} · ${order.listing.productType.label}'
                                  : order.listing.productType.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      if (order.customerPhone.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.phone_outlined,
                                size: 15, color: AppColors.gray600),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(order.customerPhone,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.navy, fontSize: 12)),
                            ),
                            GestureDetector(
                              onTap: () => _callCustomer(order.customerPhone),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.success,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.call_rounded,
                                        size: 12, color: AppColors.white),
                                    const SizedBox(width: 4),
                                    Text('Call',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: AppColors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Collect KES ${order.listing.price.toStringAsFixed(0)} from the customer on delivery (cash or M-Pesa to you).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.navy,
                          fontSize: 11,
                          height: 1.4,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                if (isPending) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _declineOrder(order),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: const BorderSide(color: AppColors.error),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 12),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Decline', maxLines: 1),
                          ),
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
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VendorOrderScreen(order: order),
                        ),
                      );
                      // A completed delivery changes the totals.
                      _loadEarnings();
                    },
                    child: Text(
                        isAccepted ? 'Start delivery' : 'Continue delivery'),
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
            Text('Recent orders',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.white,
                    )),
          ]),
        ),
        Expanded(
          child: StreamBuilder<List<OrderModel>>(
            stream: _recentCompletedOrdersStream,
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
                itemCount: orders.length + 1,
                itemBuilder: (_, i) {
                  if (i == orders.length) {
                    // The list is capped at 20; the earnings totals
                    // are not. Say so rather than let a vendor think
                    // these are all the orders they've ever had.
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        orders.length < 20
                            ? ''
                            : 'Showing your 20 most recent deliveries. '
                                'Full history is in Statistics & Reports.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray400, fontSize: 11),
                      ),
                    );
                  }
                  return _completedOrderTile(orders[i]);
                },
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
          Text('KES ${order.listing.price.toStringAsFixed(0)}',
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
    final e = _earnings;

    return RefreshIndicator(
      color: AppColors.orange,
      backgroundColor: AppColors.white,
      onRefresh: _loadEarnings,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                    _money(e?.total),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          color: AppColors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text('Today: ${_money(e?.today)}',
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
                  if (_earningsFailed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Could not load your totals. Pull down to retry.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.error),
                      ),
                    ),
                  Text(
                      e == null
                          ? 'Loading deliveries…'
                          : '${e.deliveries} deliveries completed',
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
                        _earningsRow('How you get paid',
                            'Customer pays you directly on delivery — cash or M-Pesa'),
                        _earningsRow(
                            'Your M-Pesa', _vendorData?['phone'] ?? ''),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VendorStatisticsScreen(
                            vendorData: _vendorData ?? {}),
                      ),
                    ),
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
                            child: const Icon(Icons.bar_chart_rounded,
                                color: AppColors.orange, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Statistics & Reports',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            color: AppColors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                    'Month-on-month sales, fulfillment rate, PDF export',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: AppColors.gray400,
                                            fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded,
                              color: AppColors.orange, size: 14),
                        ],
                      ),
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

  Widget _earningsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

  // ── PROFILE TAB ───────────────────────────────────────────────────
  Widget _buildProfileTab() {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl =
        (_vendorData?['photoUrl'] as String?) ?? user?.photoURL;

    // BUG FIX: `(_vendorData?['businessName'] ?? 'V')[0]` — `??` only
    // catches null, and a vendor who hasn't run setup has an EMPTY
    // businessName, which is exactly the condition the setup banner
    // tests for. ''[0] throws RangeError, so every brand-new vendor
    // crashed the moment they opened this tab.
    final initial = _businessName.isEmpty ? 'V' : _businessName[0].toUpperCase();

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
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.orange,
                  backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                      ? NetworkImage(photoUrl)
                      : null,
                  child: (photoUrl == null || photoUrl.isEmpty)
                      ? Text(
                          initial,
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
                  _businessName.isEmpty ? 'Your business' : _businessName,
                  textAlign: TextAlign.center,
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
                    if (updated == true) _refreshAll();
                  },
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
                Text(
                  user?.email ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.gray400),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                    _businessName.isEmpty ? 'Not set' : _businessName),
                _profileTile(Icons.phone_outlined, 'M-Pesa number',
                    (_vendorData?['phone'] ?? '').toString()),
                _profileTile(
                    Icons.location_on_outlined,
                    'Location',
                    (_vendorData?['address'] ?? _vendorData?['estate'] ?? '')
                        .toString()),
                _profileTile(Icons.local_gas_station_outlined, 'Brands',
                    (_vendorData?['brands'] as List?)?.join(', ') ?? ''),
                const SizedBox(height: 8),
                _editEntryButton(
                  icon: Icons.store_outlined,
                  label: 'Edit business details',
                  mode: VendorEditMode.businessOnly,
                ),
                const SizedBox(height: 10),
                _editEntryButton(
                  icon: Icons.location_on_outlined,
                  label: 'Edit location',
                  mode: VendorEditMode.locationOnly,
                ),
                const SizedBox(height: 10),
                _editEntryButton(
                  icon: Icons.local_gas_station_outlined,
                  label: 'Edit gas prices & products',
                  mode: VendorEditMode.pricesOnly,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReferEarnScreen(
                        ownerId: _vendorId,
                        ownerType: 'vendor',
                        ownerName: _businessName,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.card_giftcard_rounded, size: 16),
                  label: const Text('Refer & Earn'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    backgroundColor: AppColors.success.withValues(alpha: 0.15),
                    foregroundColor: AppColors.success,
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
                    final router = GoRouter.of(context);
                    // Signs out of Google as well as Firebase. Without
                    // the Google half, Play Services keeps the cached
                    // credential and the next "Continue with Google"
                    // silently re-signs the SAME account with no
                    // picker — a vendor who used the wrong account can
                    // never switch.
                    await GoogleAuthService.signOut();
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

  Widget _editEntryButton({
    required IconData icon,
    required String label,
    required VendorEditMode mode,
  }) {
    return ElevatedButton.icon(
      onPressed: () async {
        final done = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                VendorSetupScreen(existingData: _vendorData, mode: mode),
          ),
        );
        if (done == true) _refreshAll();
      },
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 44),
        backgroundColor: AppColors.orange.withValues(alpha: 0.15),
        foregroundColor: AppColors.orange,
        elevation: 0,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.orange, size: 20),
              const SizedBox(width: 12),
              Text(label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.gray600,
                      )),
            ],
          ),
          const SizedBox(height: 6),
          // Full-width line for the value — a phone number has no
          // spaces to wrap on, so squeezing it into the same row as
          // the label (as before) forced Flutter to hard-break it
          // mid-digit whenever it didn't fit.
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(value.isEmpty ? '—' : value,
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
      _NavItem(
          Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
      _NavItem(Icons.account_balance_wallet_outlined,
          Icons.account_balance_wallet_rounded, 'Earnings'),
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
                  onTap: () {
                    setState(() => _currentTab = i);
                    // Earnings and Home both show totals — refresh
                    // them when the vendor actually looks.
                    if (i == 0 || i == 2) _loadEarnings();
                  },
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