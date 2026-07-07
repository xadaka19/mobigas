import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/services/firestore_service.dart';

/// Shared referral dashboard — used by both the customer and vendor
/// apps (same codebase, two flavors). The caller passes in who's
/// looking at it; everything else (code generation, live referral
/// list, earnings split by customer-vs-vendor referrals) is the same
/// either way.
class ReferEarnScreen extends StatefulWidget {
  final String ownerId;
  final String ownerType; // 'customer' | 'vendor'
  final String ownerName;
  const ReferEarnScreen({
    super.key,
    required this.ownerId,
    required this.ownerType,
    required this.ownerName,
  });

  @override
  State<ReferEarnScreen> createState() => _ReferEarnScreenState();
}

class _ReferEarnScreenState extends State<ReferEarnScreen> {
  String? _code;
  bool _isLoadingCode = true;
  double _customerRate = 0;
  double _vendorRate = 0;

  // Payout preferences
  String _payoutMethod = 'mpesa'; // 'mpesa' | 'bank'
  String _payoutCadence = '30days'; // '14days' | '30days'
  final _mpesaController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _bankAccountNameController = TextEditingController();
  bool _isSavingPrefs = false;
  bool _prefsSaved = false;

  @override
  void initState() {
    super.initState();
    _loadCode();
    _loadRates();
    _loadPayoutPreferences();
  }

  @override
  void dispose() {
    _mpesaController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _bankAccountNameController.dispose();
    super.dispose();
  }

  Future<void> _loadRates() async {
    final rates = await FirestoreService.getReferralRewardRates();
    if (mounted) {
      setState(() {
        _customerRate = rates['customerReward'] ?? 0;
        _vendorRate = rates['vendorReward'] ?? 0;
      });
    }
  }

  Future<void> _loadPayoutPreferences() async {
    final prefs = await FirestoreService.getPayoutPreferences(
      ownerId: widget.ownerId,
      ownerType: widget.ownerType,
    );
    if (!mounted) return;
    setState(() {
      if ((prefs['payoutMethod'] as String).isNotEmpty) {
        _payoutMethod = prefs['payoutMethod'];
      }
      if ((prefs['payoutCadence'] as String).isNotEmpty) {
        _payoutCadence = prefs['payoutCadence'];
      }
      _mpesaController.text = prefs['payoutMpesaNumber'] ?? '';
      _bankNameController.text = prefs['payoutBankName'] ?? '';
      _bankAccountController.text = prefs['payoutBankAccountNumber'] ?? '';
      _bankAccountNameController.text = prefs['payoutBankAccountName'] ?? '';
    });
  }

  Future<void> _savePayoutPreferences() async {
    setState(() {
      _isSavingPrefs = true;
      _prefsSaved = false;
    });
    try {
      await FirestoreService.savePayoutPreferences(
        ownerId: widget.ownerId,
        ownerType: widget.ownerType,
        payoutMethod: _payoutMethod,
        payoutCadence: _payoutCadence,
        mpesaNumber: _mpesaController.text.trim(),
        bankName: _bankNameController.text.trim(),
        bankAccountNumber: _bankAccountController.text.trim(),
        bankAccountName: _bankAccountNameController.text.trim(),
      );
      if (mounted) setState(() => _prefsSaved = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not save payout preferences. Try again.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _isSavingPrefs = false);
  }

  Future<void> _loadCode() async {
    try {
      final code = await FirestoreService.getOrCreateReferralCode(
        ownerId: widget.ownerId,
        ownerType: widget.ownerType,
        ownerName: widget.ownerName,
      );
      if (mounted) setState(() {
        _code = code;
        _isLoadingCode = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingCode = false);
    }
  }

  void _copyCode() {
    if (_code == null) return;
    Clipboard.setData(ClipboardData(text: _code!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Referral code copied'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // TODO: replace with your actual Play Store package name once
  // published — find it in Google Play Console under App integrity,
  // or it's whatever you set as applicationId in android/app/build.gradle.
  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mobigas.app';

  void _shareCode() {
    if (_code == null) return;
    Share.share(
      'Get gas delivered fast on MobiGas! Use my code $_code when you sign up '
      'and we both benefit.\n\nDownload the app: $_playStoreUrl',
      subject: 'Join MobiGas with my referral code',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: StreamBuilder<List<ReferralModel>>(
                stream: FirestoreService.watchMyReferrals(widget.ownerId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.orange));
                  }
                  final referrals = snap.data!;
                  final customerRefs = referrals
                      .where((r) => r.referredType == 'customer')
                      .toList();
                  final vendorRefs = referrals
                      .where((r) => r.referredType == 'vendor')
                      .toList();

                  double earned(List<ReferralModel> list) => list
                      .where((r) =>
                          r.status == ReferralStatus.qualified ||
                          r.status == ReferralStatus.paid)
                      .fold(0.0, (a, r) => a + r.rewardAmount);
                  double paid(List<ReferralModel> list) => list
                      .where((r) => r.status == ReferralStatus.paid)
                      .fold(0.0, (a, r) => a + r.rewardAmount);

                  final totalEarned =
                      earned(customerRefs) + earned(vendorRefs);
                  final totalPaid = paid(customerRefs) + paid(vendorRefs);
                  final pendingPayout = totalEarned - totalPaid;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _codeCard(),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            _statCard('Total earned',
                                'KES ${totalEarned.toStringAsFixed(0)}',
                                AppColors.success),
                            const SizedBox(width: 12),
                            _statCard('Pending payout',
                                'KES ${pendingPayout.toStringAsFixed(0)}',
                                AppColors.orange),
                            const SizedBox(width: 12),
                            _statCard('Paid out',
                                'KES ${totalPaid.toStringAsFixed(0)}',
                                AppColors.navy),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _categorySection(
                          title: 'Customers you referred',
                          icon: Icons.person_add_alt_1_rounded,
                          list: customerRefs,
                          rewardEach: _customerRate,
                          qualifyHint: 'earns when they complete their first order',
                        ),
                        const SizedBox(height: 20),
                        _categorySection(
                          title: 'Vendors you referred',
                          icon: Icons.store_rounded,
                          list: vendorRefs,
                          rewardEach: _vendorRate,
                          qualifyHint: 'earns when MobiGas verifies them',
                        ),
                        const SizedBox(height: 24),
                        _payoutPreferencesCard(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_rounded,
                color: AppColors.white, size: 20),
          ),
          const SizedBox(width: 16),
          Text('Refer & Earn',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: AppColors.white)),
        ],
      ),
    );
  }

  Widget _codeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your referral code',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.gray400)),
          const SizedBox(height: 8),
          _isLoadingCode
              ? const SizedBox(
                  height: 32,
                  width: 32,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.orange),
                )
              : Text(_code ?? '—',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: AppColors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      )),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _code == null ? null : _copyCode,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    side: BorderSide(
                        color: AppColors.white.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _code == null ? null : _shareCode,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Share with friends'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.orange,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
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
            Text(value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color, fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.gray400, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _categorySection({
    required String title,
    required IconData icon,
    required List<ReferralModel> list,
    required double rewardEach,
    required String qualifyHint,
  }) {
    final qualifiedCount = list
        .where((r) =>
            r.status == ReferralStatus.qualified ||
            r.status == ReferralStatus.paid)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.navy, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.navy, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('KES ${rewardEach.toStringAsFixed(0)} each',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.gray400, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 4),
        Text('$qualifiedCount of ${list.length} qualified — $qualifyHint',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.gray400, fontSize: 11)),
        const SizedBox(height: 10),
        if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.gray200),
            ),
            child: Text('None yet — share your code to get started',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.gray400)),
          )
        else
          ...list.map((r) => _referralTile(r)),
      ],
    );
  }

  Widget _payoutPreferencesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
              const Icon(Icons.account_balance_wallet_outlined,
                  color: AppColors.navy, size: 20),
              const SizedBox(width: 8),
              Text('How should we pay you?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.navy, fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'MobiGas settles qualified referral earnings manually, on your chosen schedule.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.gray400, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 14),
          Text('Payment method',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray600, fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            _prefTab('M-Pesa', _payoutMethod == 'mpesa',
                () => setState(() => _payoutMethod = 'mpesa')),
            const SizedBox(width: 8),
            _prefTab('Bank transfer', _payoutMethod == 'bank',
                () => setState(() => _payoutMethod = 'bank')),
          ]),
          const SizedBox(height: 14),
          if (_payoutMethod == 'mpesa')
            TextField(
              controller: _mpesaController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'M-Pesa phone number',
                hintText: '07XX XXX XXX',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.orange),
                ),
              ),
            )
          else ...[
            TextField(
              controller: _bankNameController,
              decoration: InputDecoration(
                labelText: 'Bank name',
                hintText: 'e.g. Equity Bank',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.orange),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bankAccountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Account number',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.orange),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bankAccountNameController,
              decoration: InputDecoration(
                labelText: 'Account name',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gray200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.orange),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Payout schedule',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray600, fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 8),
          Row(children: [
            _prefTab('Every 14 days', _payoutCadence == '14days',
                () => setState(() => _payoutCadence = '14days')),
            const SizedBox(width: 8),
            _prefTab('Every 30 days', _payoutCadence == '30days',
                () => setState(() => _payoutCadence = '30days')),
          ]),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isSavingPrefs ? null : _savePayoutPreferences,
            icon: _isSavingPrefs
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white))
                : const Icon(Icons.check_rounded, size: 16),
            label: Text(_isSavingPrefs
                ? 'Saving...'
                : _prefsSaved
                    ? 'Saved ✓'
                    : 'Save payout preferences'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 46),
              backgroundColor: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }

  Widget _prefTab(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.orange : AppColors.gray100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: selected ? AppColors.orange : AppColors.gray200),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected ? AppColors.white : AppColors.gray600,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _referralTile(ReferralModel r) {
    final statusColor = switch (r.status) {
      ReferralStatus.pending => AppColors.warning,
      ReferralStatus.qualified => AppColors.success,
      ReferralStatus.paid => AppColors.navy,
    };
    final statusLabel = switch (r.status) {
      ReferralStatus.pending => 'Pending',
      ReferralStatus.qualified => 'Qualified',
      ReferralStatus.paid => 'Paid',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(r.referredName.isNotEmpty ? r.referredName : 'Referral',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.navy, fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}