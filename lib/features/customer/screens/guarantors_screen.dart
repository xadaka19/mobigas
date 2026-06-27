import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';

class GuarantorsScreen extends StatefulWidget {
  const GuarantorsScreen({super.key});

  @override
  State<GuarantorsScreen> createState() => _GuarantorsScreenState();
}

class _GuarantorsScreenState extends State<GuarantorsScreen> {
  final List<_Guarantor> _selected = [];
  List<Contact> _contacts = [];
  List<Contact> _filtered = [];
  bool _isLoading = false;
  bool _permissionDenied = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);

    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      setState(() {
        _permissionDenied = true;
        _isLoading = false;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(
      withProperties: true,
    );

    // Only contacts with at least one phone number
    final valid = contacts
        .where((c) => c.phones.isNotEmpty)
        .toList();

    setState(() {
      _contacts = valid;
      _filtered = valid;
      _isLoading = false;
    });
  }

  void _search(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _contacts
          : _contacts.where((c) {
              final name =
                  c.displayName.toLowerCase();
              final phone = c.phones.first.number;
              return name.contains(q) || phone.contains(q);
            }).toList();
    });
  }

  void _toggleContact(Contact contact) {
    final phone = _cleanPhone(contact.phones.first.number);
    final name =
        contact.displayName;

    final alreadySelected = _selected.any((g) => g.phone == phone);

    if (alreadySelected) {
      setState(() => _selected.removeWhere((g) => g.phone == phone));
      return;
    }

    if (_selected.length >= 2) {
      _showError('You can only select 2 guarantors');
      return;
    }

    setState(() => _selected.add(_Guarantor(name: name, phone: phone)));
  }

  String _cleanPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('+254')) {
      cleaned = '0${cleaned.substring(4)}';
    }
    if (cleaned.startsWith('254')) {
      cleaned = '0${cleaned.substring(3)}';
    }
    return cleaned;
  }

  bool _isSelected(Contact contact) {
    final phone = _cleanPhone(contact.phones.first.number);
    return _selected.any((g) => g.phone == phone);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _proceed() {
    if (_selected.length < 2) {
      _showError('Please select exactly 2 guarantors to continue');
      return;
    }
    context.go('/crb-check');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSelectedBadges(),
            if (!_permissionDenied && !_isLoading) _buildSearch(),
            Expanded(child: _buildBody()),
            if (_selected.length == 2) _buildProceedButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.go('/register'),
            child: const Icon(
              Icons.arrow_back_ios_rounded,
              color: AppColors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add 2 guarantors',
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white,
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select 2 people from your contacts who can vouch for you if you miss a payment.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 16),
          // Progress indicator
          Row(
            children: [
              _progressDot(filled: _selected.isNotEmpty, label: 'Guarantor 1'),
              Expanded(
                child: Container(
                  height: 2,
                  color: _selected.length >= 2
                      ? AppColors.orange
                      : AppColors.gray600,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
              _progressDot(
                  filled: _selected.length >= 2, label: 'Guarantor 2'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _progressDot({required bool filled, required String label}) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.orange : AppColors.gray600,
            border: Border.all(
              color: filled ? AppColors.orange : AppColors.gray600,
              width: 2,
            ),
          ),
          child: filled
              ? const Icon(Icons.check_rounded,
                  color: AppColors.white, size: 16)
              : null,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: filled ? AppColors.orange : AppColors.gray400,
                fontSize: 10,
              ),
        ),
      ],
    );
  }

  Widget _buildSelectedBadges() {
    if (_selected.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Selected guarantors',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray600,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selected
                .map((g) => _selectedBadge(g))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _selectedBadge(_Guarantor g) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.orange,
            child: Text(
              g.name.isNotEmpty ? g.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                g.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
              ),
              Text(
                g.phone,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray600,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () =>
                setState(() => _selected.removeWhere((s) => s.phone == g.phone)),
            child: const Icon(Icons.close_rounded,
                size: 16, color: AppColors.orange),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextFormField(
        controller: _searchController,
        onChanged: _search,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.navy,
            ),
        decoration: InputDecoration(
          hintText: 'Search contacts by name or number...',
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.orange),
            SizedBox(height: 16),
            Text('Loading contacts...'),
          ],
        ),
      );
    }

    if (_permissionDenied) {
      return _buildPermissionDenied();
    }

    if (_filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 48, color: AppColors.gray400),
            const SizedBox(height: 12),
            Text(
              'No contacts found',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.gray600,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filtered.length,
      itemBuilder: (context, i) => _contactTile(_filtered[i]),
    );
  }

  Widget _contactTile(Contact contact) {
    final name =
        contact.displayName;
    final phone =
        _cleanPhone(contact.phones.first.number);
    final selected = _isSelected(contact);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

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
            color: selected
                ? AppColors.orange
                : AppColors.gray200,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: selected
                  ? AppColors.orange
                  : AppColors.gray200,
              child: Text(
                initial,
                style: TextStyle(
                  color: selected ? AppColors.white : AppColors.gray600,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unknown' : name,
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 14,
                              color: AppColors.navy,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.gray600,
                        ),
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppColors.orange : AppColors.white,
                border: Border.all(
                  color:
                      selected ? AppColors.orange : AppColors.gray200,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.errorLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.contacts_outlined,
                  size: 40, color: AppColors.error),
            ),
            const SizedBox(height: 24),
            Text(
              'Contacts access needed',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.navy,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'MobiGas needs access to your contacts to select guarantors. This prevents fake phone numbers and protects the platform.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.gray600,
                    height: 1.6,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () async {
                await openAppSettings();
                if (mounted) _loadContacts();
              },
              icon: const Icon(Icons.settings_outlined, size: 18),
              label: const Text('Open Settings'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadContacts,
              child: Text(
                'Try again',
                style: TextStyle(color: AppColors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProceedButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_selected[0].name} & ${_selected[1].name} selected as guarantors',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _proceed,
            child: const Text('Continue to credit check'),
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
