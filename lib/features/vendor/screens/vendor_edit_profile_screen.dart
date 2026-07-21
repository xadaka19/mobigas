import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/services/storage_metadata.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobigas/core/screens/delete_account_screen.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/widgets/notification_permission_tile.dart';

class VendorEditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> vendorData;
  const VendorEditProfileScreen({super.key, required this.vendorData});

  @override
  State<VendorEditProfileScreen> createState() =>
      _VendorEditProfileScreenState();
}

class _VendorEditProfileScreenState extends State<VendorEditProfileScreen> {
  File? _newPhoto;
  bool _isUploading = false;
  bool _isSaving = false;
  late TextEditingController _businessNameController;
  late TextEditingController _ownerNameController;
  late TextEditingController _phoneController;
  // Second line the vendor can be reached on — the contact/payout
  // number itself is locked here (set during setup); this is the
  // only phone-related field this screen can actually change.
  late TextEditingController _altPhoneController;
  late TextEditingController _estateController;

  @override
  void initState() {
    super.initState();
    _businessNameController = TextEditingController(
        text: widget.vendorData['businessName'] ?? '');
    _ownerNameController =
        TextEditingController(text: widget.vendorData['ownerName'] ?? '');
    _phoneController =
        TextEditingController(text: widget.vendorData['phone'] ?? '');
    _altPhoneController =
        TextEditingController(text: widget.vendorData['altPhone'] ?? '');
    _estateController =
        TextEditingController(text: widget.vendorData['estate'] ?? '');
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _estateController.dispose();
    super.dispose();
  }

  String get _vendorId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  /// Turns a Firebase failure into something a human can act on.
  ///
  /// The old code showed 'Error: \$e' — an ESCAPED dollar sign, so it
  /// printed those four literal characters instead of interpolating
  /// the exception. Storage errors carry a `code` ('unauthorized',
  /// 'object-not-found', 'bucket-not-found') that says exactly what
  /// went wrong.
  String _describeError(Object e) {
    if (e is FirebaseException) {
      return '${e.plugin}/${e.code}: ${e.message ?? 'no message'}';
    }
    return e.toString();
  }

  Future<void> _showPhotoOptions() async {
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
            Text('Business photo',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.navy,
                    )),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.orange),
              title: const Text('Take photo / selfie'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.orange),
              title: const Text('Upload business logo'),
              subtitle: const Text('From gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (photo != null) {
      setState(() => _newPhoto = File(photo.path));
    }
  }

  Future<void> _saveProfile() async {
    // Bail BEFORE flipping _isSaving — otherwise the spinner runs
    // forever and Storage is handed an empty path.
    if (_vendorId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are signed out. Please sign in again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? photoUrl;

      if (_newPhoto != null) {
        setState(() => _isUploading = true);
        final ref = FirebaseStorage.instance
            .ref()
            .child('vendor_photos')
            .child(_vendorId);
        await ref.putFile(_newPhoto!, imageMetadata(_newPhoto!));
        photoUrl = await ref.getDownloadURL();
        if (mounted) setState(() => _isUploading = false);
      }

      final updates = <String, dynamic>{
        'businessName': _businessNameController.text.trim(),
        'ownerName': _ownerNameController.text.trim(),
        // 'phone' is intentionally NOT included — it's locked on this
        // screen (set once during setup) and must never be
        // overwritten from here.
        'altPhone': _altPhoneController.text.trim(),
        'estate': _estateController.text.trim(),
      };
      if (photoUrl != null) updates['photoUrl'] = photoUrl;

      await FirebaseService.vendors.doc(_vendorId).update(updates);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      // Pop LAST. Anything after this runs on a disposed widget.
      Navigator.pop(context, true); // true triggers a reload upstream
      return;
    } catch (e) {
      // A Storage failure here and a photo that won't render share one
      // suspect: the bucket. A mismatch between firebase_options.dart
      // and the real bucket name breaks uploads AND every existing URL.
      debugPrint('Profile update failed: ${_describeError(e)}');
      debugPrint('Storage bucket in use: ${FirebaseStorage.instance.bucket}');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_describeError(e)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPhoto = widget.vendorData['photoUrl'] as String?;
    final user = FirebaseAuth.instance.currentUser;
    final businessName =
        widget.vendorData['businessName'] as String? ?? 'V';

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back_ios_rounded,
                        color: AppColors.white, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Text('Edit profile',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: AppColors.white)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Photo section
                    Center(
                      child: Stack(
                        children: [
                          GestureDetector(
                            onTap: _showPhotoOptions,
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.orange, width: 3),
                              ),
                              child: ClipOval(
                                child: _avatar(
                                  currentPhoto,
                                  user?.photoURL,
                                  businessName,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _showPhotoOptions,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.orange,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.navy, width: 2),
                                ),
                                child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: AppColors.white,
                                    size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to update photo or upload logo',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppColors.gray400),
                    ),
                    if (_isUploading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(
                          color: AppColors.orange),
                    ],
                    const SizedBox(height: 28),
                    _buildField('Business name',
                        _businessNameController, Icons.store_outlined),
                    const SizedBox(height: 16),
                    _buildField('Owner name', _ownerNameController,
                        Icons.person_outline_rounded),
                    const SizedBox(height: 16),
                    // Locked — this is the vendor's registered contact
                    // / mobile money number, set once during setup.
                    // Changing it here would silently move where
                    // customers call and where payouts land, so it's
                    // display-only, same treatment as National ID on
                    // the customer profile screen.
                    _readOnlyField(
                      'Mobile money number',
                      widget.vendorData['phone'] as String? ?? '',
                      Icons.phone_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Alternate phone number (optional)',
                      _altPhoneController,
                      Icons.phone_android_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    _buildIdField(),
                    const SizedBox(height: 16),
                    _buildField('Estate / Area', _estateController,
                        Icons.location_on_outlined),
                    const SizedBox(height: 16),
                    // Mirrors signup: if the vendor allowed push
                    // notifications there, this just shows "Active".
                    // If they declined, this toggle is the only in-app
                    // way back in.
                    Text('Notifications',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 13,
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 6),
                    const NotificationPermissionTile(
                      darkMode: true,
                      inactiveMessage:
                          "Enable push notifications so you don't miss an order",
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.white),
                            )
                          : const Text('Save changes'),
                    ),
                    // ── Account deletion (Google Play requirement) ──
                    // Navigator, not context.push — this screen is
                    // pushed with a MaterialPageRoute and carries
                    // vendorData, so it never went through GoRouter.
                    const SizedBox(height: 32),
                    Divider(color: AppColors.white.withValues(alpha: 0.15)),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_forever_outlined,
                          color: AppColors.error),
                      title: Text(
                        'Delete account',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 15,
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: Text(
                        'Permanently remove your business and data',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray400),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.gray400),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeleteAccountScreen(),
                        ),
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

  /// Photo with a real fallback chain: new pick → Firestore photoUrl →
  /// Google account photo → initial.
  ///
  /// Image.network with no errorBuilder renders nothing when the URL
  /// 404s or Storage rejects the read — which is exactly what a wrong
  /// storageBucket or a `read: false` rule produces. Now each broken
  /// URL falls through to the next option and prints why.
  Widget _avatar(String? photoUrl, String? googlePhotoUrl, String name) {
    if (_newPhoto != null) {
      return Image.file(_newPhoto!, fit: BoxFit.cover);
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) {
          debugPrint('Vendor photo failed to load: $photoUrl');
          debugPrint('Reason: $error');
          return _avatar(null, googlePhotoUrl, name);
        },
      );
    }
    if (googlePhotoUrl != null && googlePhotoUrl.isNotEmpty) {
      return Image.network(
        googlePhotoUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => _initialAvatar(name),
      );
    }
    return _initialAvatar(name);
  }

  Widget _initialAvatar(String name) {
    return Container(
      color: AppColors.orange,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'V',
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /// Shows whichever identity document the vendor registered with —
  /// National ID for a sole proprietor, Business Registration Number
  /// for a registered business / petrol station. Set once during
  /// setup (VendorSetupScreen Step 0); not editable from this screen.
  Widget _buildIdField() {
    final nationalId = widget.vendorData['nationalId'] as String?;
    final brn = widget.vendorData['businessRegNumber'] as String?;
    final hasNationalId = nationalId != null && nationalId.isNotEmpty;
    return _readOnlyField(
      hasNationalId ? 'National ID' : 'Business Registration Number',
      hasNationalId ? nationalId : (brn ?? ''),
      hasNationalId ? Icons.badge_outlined : Icons.app_registration_rounded,
    );
  }

  /// Locked-field style matching the dark theme used throughout this
  /// screen — same visual language as the editable fields below, but
  /// with a lock glyph and no input behavior.
  Widget _readOnlyField(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.white.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gray400, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value.isEmpty ? 'Not set' : value,
                  style: const TextStyle(color: AppColors.white),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.lock_outline_rounded,
                  color: AppColors.gray400, size: 14),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            prefixIcon:
                Icon(icon, color: AppColors.gray400, size: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: AppColors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.orange),
            ),
            filled: true,
            fillColor: AppColors.white.withValues(alpha: 0.05),
          ),
        ),
      ],
    );
  }
}