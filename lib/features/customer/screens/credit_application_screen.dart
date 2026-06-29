import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/models/app_models.dart';

class CreditApplicationScreen extends StatefulWidget {
  const CreditApplicationScreen({super.key});

  @override
  State<CreditApplicationScreen> createState() =>
      _CreditApplicationScreenState();
}

class _CreditApplicationScreenState extends State<CreditApplicationScreen> {
  int _step = 0; // 0=intro, 1=guarantors, 2=submitting, 3=submitted

  final List<_Guarantor> _selected = [];
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _isLoadingContacts = false;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoadingContacts = true);
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      setState(() => _isLoadingContacts = false);
      return;
    }
    final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.phone});
    final valid = contacts.where((c) => c.phones.isNotEmpty).toList();
    setState(() {
      _contacts = valid;
      _filtered = valid;
      _isLoadingContacts = false;
    });
  }

  void _search(String q) {
    final query = q.toLowerCase().trim();
    setState(() {
      _filtered = query.isEmpty
          ? _contacts
          : _contacts.where((c) {
              final name = (c.displayName ?? '').toLowerCase();
              final phone = c.phones.first.number;
              return name.contains(query) || phone.contains(query);
            }).toList();
    });
  }

  void _toggleContact(Contact contact) {
    final phone = _cleanPhone(contact.phones.first.number);
    final name = contact.displayName;
    final alreadySelected = _selected.any((g) => g.phone == phone);
    if (alreadySelected) {
      setState(() => _selected.removeWhere((g) => g.phone == phone));
      return;
    }
    if (_selected.length >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You can only select 2 guarantors'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    setState(() => _selected.add(_Guarantor(name: name ?? '', phone: phone)));
  }

  String _cleanPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+254')) cleaned = '0${cleaned.substring(4)}';
    if (cleaned.startsWith('254')) cleaned = '0${cleaned.substring(3)}';
    return cleaned;
  }

  bool _isSelected(Contact c) {
    final phone = _cleanPhone(c.phones.first.number);
    return _selected.any((g) => g.phone == phone);
  }

  Future<void> _submitApplication() async {
    setState(() {
      _step = 2;

    });

    final auth = context.read<AuthProvider>();

    // Update customer with guarantors
    await auth.submitCreditApplication(
      guarantors: _selected
          .map((g) => GuarantorModel(name: g.name, phone: g.phone))
          .toList(),
    );

    setState(() {

      _step = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: _step == 0
            ? _buildIntro()
            : _step == 1
                ? _buildGuarantors()
                : _step == 2
                    ? _buildSubmitting()
                    : _buildSubmitted(),
      ),
    );
  }

  // ── STEP 0: INTRO ─────────────────────────────────────────────────
  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: GestureDetector(
              onTap: () => context.go('/home'),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.navy),
            ),
          ),
          const Spacer(),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_outlined,
                color: AppColors.orange, size: 52),
          ),
          const SizedBox(height: 32),
          Text(
            'Apply for gas credit',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.navy,
                  fontSize: 26,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Our partner bank will review your application and set your gas credit limit. This takes less than a minute.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.gray600,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: 32),
          _infoCard(Icons.people_outline_rounded,
              'You need 2 guarantors from your contacts'),
          const SizedBox(height: 12),
          _infoCard(Icons.account_balance_outlined,
              'Bank reviews and sets your credit limit'),
          const SizedBox(height: 12),
          _infoCard(Icons.local_fire_department_rounded,
              'Start ordering gas immediately after approval'),
          const Spacer(),
          ElevatedButton(
            onPressed: () {
              setState(() => _step = 1);
              _loadContacts();
            },
            child: const Text('Start application'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.go('/home'),
            child: Text('Maybe later',
                style: TextStyle(color: AppColors.gray600)),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(IconData icon, String text) {
    return Container(
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
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.navy,
                    )),
          ),
        ],
      ),
    );
  }

  // ── STEP 1: GUARANTORS ────────────────────────────────────────────
  Widget _buildGuarantors() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: AppColors.navy,
            borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: () => setState(() => _step = 0),
                child: const Icon(Icons.arrow_back_ios_rounded,
                    color: AppColors.white, size: 20),
              ),
              const SizedBox(height: 16),
              Text('Add 2 guarantors',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(
                        color: AppColors.white,
                        fontSize: 22,
                      )),
              const SizedBox(height: 4),
              Text(
                'Select 2 people from your contacts who can vouch for you',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray400,
                    ),
              ),
              const SizedBox(height: 12),
              // Progress dots
              Row(
                children: [
                  _dot(_selected.isNotEmpty, 'Guarantor 1'),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: _selected.length >= 2
                          ? AppColors.orange
                          : AppColors.gray600,
                      margin:
                          const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  _dot(_selected.length >= 2, 'Guarantor 2'),
                ],
              ),
            ],
          ),
        ),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              spacing: 8,
              children:
                  _selected.map((g) => _selectedChip(g)).toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextFormField(
            controller: _searchController,
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Search contacts...',
              prefixIcon: const Icon(Icons.search_rounded,
                  color: AppColors.gray400, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _search('');
                      },
                      icon: const Icon(Icons.clear_rounded,
                          color: AppColors.gray400, size: 18),
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: _isLoadingContacts
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.orange))
              : _filtered.isEmpty
                  ? const Center(child: Text('No contacts found'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) =>
                          _contactTile(_filtered[i]),
                    ),
        ),
        if (_selected.length == 2)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            color: AppColors.white,
            child: ElevatedButton(
              onPressed: _submitApplication,
              child: const Text('Submit to bank for approval'),
            ),
          ),
      ],
    );
  }

  Widget _dot(bool filled, String label) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.orange : AppColors.gray600,
          ),
          child: filled
              ? const Icon(Icons.check_rounded,
                  color: AppColors.white, size: 14)
              : null,
        ),
        const SizedBox(height: 4),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      filled ? AppColors.orange : AppColors.gray400,
                  fontSize: 10,
                )),
      ],
    );
  }

  Widget _selectedChip(_Guarantor g) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: AppColors.orange,
        child: Text(g.name.isNotEmpty ? g.name[0].toUpperCase() : '?',
            style: const TextStyle(
                color: AppColors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ),
      label: Text('${g.name} · ${g.phone}',
          style: const TextStyle(fontSize: 11)),
      deleteIcon: const Icon(Icons.close_rounded, size: 14),
      onDeleted: () =>
          setState(() => _selected.removeWhere((s) => s.phone == g.phone)),
      backgroundColor: AppColors.orangeLight,
      side: BorderSide(color: AppColors.orange.withValues(alpha: 0.4)),
    );
  }

  Widget _contactTile(Contact contact) {
    final name = contact.displayName;
    final phone = _cleanPhone(contact.phones.first.number);
    final selected = _isSelected(contact);

    return GestureDetector(
      onTap: () => _toggleContact(contact),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.orange.withValues(alpha: 0.08)
              : AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.orange : AppColors.gray200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  selected ? AppColors.orange : AppColors.gray200,
              child: Text(
                (name?.isNotEmpty == true) ? name![0].toUpperCase() : '?',
                style: TextStyle(
                  color: selected
                      ? AppColors.white
                      : AppColors.gray600,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((name?.isEmpty ?? true) ? 'Unknown' : name!,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontSize: 14,
                            color: AppColors.navy,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          )),
                  Text(phone,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray600)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.orange : AppColors.white,
                border: Border.all(
                  color: selected
                      ? AppColors.orange
                      : AppColors.gray200,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.white, size: 13)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── STEP 2: SUBMITTING ────────────────────────────────────────────
  Widget _buildSubmitting() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.orange),
          SizedBox(height: 24),
          Text('Submitting to partner bank...',
              style: TextStyle(
                  color: AppColors.navy, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── STEP 3: SUBMITTED ─────────────────────────────────────────────
  Widget _buildSubmitted() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: AppColors.success, size: 56),
          ),
          const SizedBox(height: 32),
          Text('Checking your credit...',
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: AppColors.navy,
                    fontSize: 26,
                  ),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Our partner bank is reviewing your application. You will receive a notification once approved — usually in seconds.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.gray600,
                  height: 1.6,
                ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.orangeLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_outlined,
                    color: AppColors.orange, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'We will notify you on your phone as soon as the bank approves your limit.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: AppColors.orangeDeep,
                          height: 1.4,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.go('/home'),
            child: const Text('Back to home'),
          ),
        ],
      ),
    );
  }
}

class _Guarantor {
  final String name;
  final String phone;
  const _Guarantor({required this.name, required this.phone});
}
