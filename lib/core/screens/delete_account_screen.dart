import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/flavors/flavor_config.dart';

/// In-app account deletion, shared by both flavors.
///
/// Google Play requires BOTH this in-app path and the public web form
/// at mobigas.co.ke/delete-account. This is the easy case: the user is
/// already signed in, so `requestMyAccountDeletion` reads the uid off
/// the auth token and the request lands as `verified` — no phone
/// callback needed.
///
/// Nothing is deleted on tap. The request is queued for review in the
/// admin dashboard, then we sign the user out — leaving someone inside
/// a session whose account is queued for deletion invites them to
/// place an order that's about to vanish.
///
/// Sign-out goes through FirebaseService.auth directly rather than
/// AuthProvider.logout(). Two reasons: AuthProvider is customer-only
/// (it loads a CustomerModel, and the vendor tree never reads it), and
/// its constructor already listens to authStateChanges() — so signing
/// out clears _customer and fires notifyListeners() on its own.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _reasonController = TextEditingController();
  bool _acknowledged = false;
  bool _submitting = false;
  String? _errorText;

  bool get _isVendor => FlavorConfig.isVendor;

  // Vendor screens sit on navy; customer screens on orangeWarm.
  Color get _background => _isVendor ? AppColors.navy : AppColors.orangeWarm;
  Color get _onBackground => _isVendor ? AppColors.white : AppColors.navy;
  Color get _muted => _isVendor ? AppColors.gray400 : AppColors.gray600;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSubmit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.white,
        title: const Text('Delete your account?'),
        content: const Text(
          'This cannot be undone. Your profile, saved details and account '
          'access will be permanently removed, and you will be signed out '
          'now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep my account'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('requestMyAccountDeletion');
      await callable.call<Map<String, dynamic>>({
        'app': _isVendor ? 'vendor' : 'customer',
        'reason': _reasonController.text.trim(),
      });

      // AuthProvider's authStateChanges() listener picks this up and
      // clears its own state — no provider call needed here.
      await FirebaseService.auth.signOut();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Deletion requested. Your account will be removed within 7 '
            'days and you will get an SMS confirmation.',
          ),
          backgroundColor: AppColors.navy,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
      context.go('/');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = e.code == 'already-exists'
            ? 'A deletion request for this account is already being '
                'processed. We will contact you shortly.'
            : 'We could not submit your request. Check your connection '
                'and try again, or email support@mobigas.co.ke.';
      });
    } catch (e) {
      debugPrint('Account deletion request failed: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = 'We could not submit your request. Check your '
            'connection and try again, or email support@mobigas.co.ke.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: Column(
          children: [
            // Header — mirrors the edit-profile screens' back-arrow row.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: _isVendor
                    ? null
                    : const BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _submitting ? null : () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: AppColors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Text('Delete account',
                      style: text.titleLarge?.copyWith(color: AppColors.white)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.08),
                        border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.35),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: AppColors.error),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Deleting your account is permanent. You will '
                              'lose access to MobiGas and cannot recover '
                              'your data.',
                              style: text.bodyMedium
                                  ?.copyWith(color: _onBackground),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    _sectionTitle('What gets deleted', text),
                    ..._bullets(
                      _isVendor
                          ? const [
                              'Your business profile, listings and prices',
                              'Your contact details and saved locations',
                              'Chat messages and notifications',
                              'Referral code and referral history',
                              'Your sign-in — you cannot log in again',
                            ]
                          : const [
                              'Your name, phone number, email and photo',
                              'Saved delivery addresses and location data',
                              'Chat messages and notifications',
                              'Referral code and referral history',
                              'Your sign-in — you cannot log in again',
                            ],
                      text,
                    ),

                    const SizedBox(height: 24),
                    _sectionTitle('What we must keep', text),
                    ..._bullets(
                      _isVendor
                          ? const [
                              'Records of completed orders and M-Pesa '
                                  'payments, kept in minimal form for up to '
                                  '7 years as Kenyan tax law requires',
                              'Any unpaid platform fees, until settled',
                              'Records needed for an open dispute',
                            ]
                          : const [
                              'Records of completed orders and M-Pesa '
                                  'payments, kept in minimal form for up to '
                                  '7 years as Kenyan tax law requires',
                              'Any outstanding gas credit, until repaid',
                              'Records needed for an open dispute',
                            ],
                      text,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'These records are no longer linked to a usable '
                      'account and are never used for marketing.',
                      style: text.bodySmall?.copyWith(color: _muted),
                    ),

                    const SizedBox(height: 28),
                    _sectionTitle('Why are you leaving? (optional)', text),
                    TextField(
                      controller: _reasonController,
                      enabled: !_submitting,
                      maxLines: 3,
                      maxLength: 500,
                      style: TextStyle(color: _onBackground),
                      decoration: InputDecoration(
                        hintText: 'This helps us improve. Not required.',
                        hintStyle: TextStyle(color: _muted),
                        counterStyle: TextStyle(color: _muted),
                      ),
                    ),

                    const SizedBox(height: 4),
                    CheckboxListTile(
                      value: _acknowledged,
                      onChanged: _submitting
                          ? null
                          : (v) => setState(() => _acknowledged = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppColors.error,
                      title: Text(
                        'I understand this is permanent and cannot be undone.',
                        style: text.bodyMedium?.copyWith(color: _onBackground),
                      ),
                    ),

                    if (_errorText != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorText!,
                          style:
                              text.bodySmall?.copyWith(color: AppColors.error),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_acknowledged && !_submitting)
                            ? _confirmAndSubmit
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          disabledBackgroundColor:
                              AppColors.error.withValues(alpha: 0.4),
                        ),
                        child: _submitting
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.white,
                                ),
                              )
                            : const Text('Delete my account'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed:
                            _submitting ? null : () => Navigator.pop(context),
                        child: Text('Cancel',
                            style: TextStyle(color: _onBackground)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String label, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: text.titleMedium?.copyWith(
          fontSize: 14,
          color: _onBackground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _bullets(List<String> items, TextTheme text) {
    return items
        .map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 7, right: 10),
                  child: SizedBox(
                    width: 5,
                    height: 5,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    line,
                    style: text.bodyMedium?.copyWith(color: _onBackground),
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }
}