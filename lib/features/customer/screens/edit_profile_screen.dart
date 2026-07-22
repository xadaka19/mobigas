import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/services/storage_metadata.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/services/device_fingerprint_service.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/widgets/location_picker_widget.dart';
import 'package:mobigas/core/widgets/notification_permission_tile.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  File? _newSelfie;
  bool _isUploading = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  // A second number the customer can be reached on, alongside the
  // locked primary phone number below. Purely informational.
  late TextEditingController _altPhoneController;
  late TextEditingController _idController;

  /// The alt phone we started with. Like _originalPhone before it —
  /// checkDuplicates matches against the whole users collection,
  /// including this account, so re-saving an unchanged alt number
  /// would otherwise always come back "taken" against itself... except
  /// it wouldn't, because checkDuplicates excludes the current uid.
  /// What this DOES prevent is calling checkDuplicates at all when
  /// nothing changed — no point spending a network round trip re-
  /// verifying a value that's already saved and valid.
  late String _originalAltPhone;

  /// A National ID is write-once. Blank means the customer skipped it
  /// at signup (it's optional in v1) and can still add one here.
  /// Once set, it's locked — changing it would invalidate any KYC.
  late bool _idWasSet;

  String _selectedAddress = '';
  double _selectedLat = 0.0;
  double _selectedLng = 0.0;

  @override
  void initState() {
    super.initState();
    final customer = context.read<AuthProvider>().customer;
    _nameController = TextEditingController(text: customer?.name ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _altPhoneController =
        TextEditingController(text: customer?.altPhone ?? '');
    _originalAltPhone = (customer?.altPhone ?? '').trim();
    _idController = TextEditingController(text: customer?.nationalId ?? '');
    _idWasSet = (customer?.nationalId ?? '').trim().isNotEmpty;
    _selectedAddress = customer?.estate ?? '';
    _selectedLat = customer?.latitude ?? 0;
    _selectedLng = customer?.longitude ?? 0;
    if (Platform.isAndroid) _retrieveLostPhoto();
  }

  /// BUG FIX: pickImage(source: camera) launches the camera as a
  /// SEPARATE Android activity. On a low-memory device Android
  /// destroys this activity while it's backgrounded — so on return
  /// the screen is recreated from scratch (looks like "the app
  /// restarted"), _newSelfie is null again, and the await inside
  /// _takeSelfie never resolves. The photo is gone with no error.
  /// Android caches it and image_picker exposes it here exactly once;
  /// without this call it is silently dropped every time.
  Future<void> _retrieveLostPhoto() async {
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.isEmpty) return;
      final file = response.file;
      if (file != null && mounted) {
        setState(() => _newSelfie = File(file.path));
        _error('Photo recovered — tap "Save changes" to keep it.');
      }
    } catch (e) {
      debugPrint('retrieveLostData failed: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _idController.dispose();
    super.dispose();
  }

  Future<void> _takeSelfie() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (photo != null && mounted) {
        setState(() => _newSelfie = File(photo.path));
      }
    } catch (e) {
      // Denying the camera permission throws — don't let it crash the
      // screen the way an unguarded pickImage() does.
      if (mounted) {
        _error('Could not open the camera. Allow camera access to add a photo.');
      }
    }
  }

  void _error(String msg, {Duration? duration}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: duration ?? const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  /// Turns a Firebase failure into something a human can act on.
  ///
  /// The old code showed 'Error: \$e' — an ESCAPED dollar sign, so it
  /// printed those four literal characters instead of interpolating
  /// the exception. Every upload failure looked identical and told us
  /// nothing. Storage errors carry a `code` ('unauthorized',
  /// 'object-not-found', 'bucket-not-found') that says exactly what
  /// went wrong, so surface it.
  String _describeError(Object e) {
    if (e is FirebaseException) {
      return '${e.plugin}/${e.code}: ${e.message ?? 'no message'}';
    }
    return e.toString();
  }

  /// Returns an error message, or null when everything is valid.
  String? _validate() {
    if (_nameController.text.trim().isEmpty) {
      return 'Enter your full name';
    }
    // The primary phone number is locked (write-once, set at signup)
    // so it no longer needs validating here — only the optional
    // alternate number does.
    final altPhone = _altPhoneController.text.trim();
    if (altPhone.isNotEmpty && altPhone.length < 9) {
      return 'Enter a valid alternate phone number, or leave it blank';
    }
    if (!_idWasSet) {
      final id = _idController.text.trim();
      if (id.isNotEmpty && id.length < 7) {
        return 'Enter a valid National ID number, or leave it blank';
      }
    }
    return null;
  }

  Future<void> _saveProfile() async {
    final auth = context.read<AuthProvider>();
    final uid = auth.customer?.id;
    // Bail BEFORE flipping _isSaving — the old order left the spinner
    // running forever when uid was null, and the button never came back.
    if (uid == null) {
      _error('You are signed out. Please sign in again.');
      return;
    }

    final problem = _validate();
    if (problem != null) {
      _error(problem);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newId = _idWasSet ? null : _idController.text.trim();
      final altPhone = _altPhoneController.text.trim();

      // The primary phone number is locked, so it can never be the
      // thing that changed here. What CAN change: the National ID
      // (write-once, same as before) and the new alt phone. Only
      // check whichever actually changed — checkDuplicates scans
      // every user, this account included, so a value that's
      // unchanged from what's already saved would be pointless to
      // re-verify.
      final addingId = newId != null && newId.isNotEmpty;
      final altPhoneChanged = altPhone != _originalAltPhone;

      if (addingId || altPhoneChanged) {
        final fingerprint = await DeviceFingerprintService.getFingerprint();
        // checkDuplicates now takes altPhone as its own axis — it's
        // checked against everyone else's primary AND alt phone
        // fields, not just folded into the `phone` param the way an
        // earlier version of this did. See FirestoreService for the
        // Cloud Function dependency this relies on.
        final duplicates = await FirestoreService.checkDuplicates(
          phone: '',
          nationalId: addingId ? newId : '',
          altPhone: altPhoneChanged ? altPhone : null,
          deviceFingerprint: fingerprint,
        );

        if (altPhoneChanged && duplicates['altPhoneTaken'] == true) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          _error('Another account already uses this phone number.');
          return;
        }
        if (addingId && duplicates['idTaken'] == true) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          _error('Another account already uses this National ID.');
          return;
        }
      }

      String? selfieUrl;

      if (_newSelfie != null) {
        setState(() => _isUploading = true);
        final ref = FirebaseStorage.instance.ref().child('selfies').child(uid);
        await ref.putFile(_newSelfie!, imageMetadata(_newSelfie!));
        selfieUrl = await ref.getDownloadURL();
        if (mounted) setState(() => _isUploading = false);
      }

      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        // 'phone' is intentionally NOT included — it's locked on this
        // screen (write-once, set at signup) and must never be
        // overwritten from here.
        'altPhone': _altPhoneController.text.trim(),
        'estate': _selectedAddress,
        'area': _selectedAddress,
        // BUG FIX: county was never written, so the locked County field
        // displayed a value that nothing in the app could ever change.
        // Location is a single free-text area in v1 — mirror it, the
        // same way saveLocation() does from the profile banner.
        'county': _selectedAddress,
        'latitude': _selectedLat,
        'longitude': _selectedLng,
      };
      if (selfieUrl != null) updates['selfieUrl'] = selfieUrl;
      if (addingId) updates['nationalId'] = newId;

      await FirebaseService.users.doc(uid).update(updates);
      if (mounted) await auth.refreshCustomer();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Profile updated'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      // Pop LAST. Anything after this runs on a disposed widget.
      Navigator.pop(context);
      return;
    } catch (e) {
      // If this is a Storage failure, the bucket is the first thing
      // worth eyeballing: a mismatch between firebase_options.dart and
      // the real bucket name breaks uploads AND breaks every existing
      // photo URL at the same time.
      debugPrint('Profile save failed: ${_describeError(e)}');
      debugPrint('Storage bucket in use: ${FirebaseStorage.instance.bucket}');
      if (mounted) {
        setState(() {
          _isUploading = false;
          _isSaving = false;
        });
        _error(_describeError(e), duration: const Duration(seconds: 8));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthProvider>().customer;

    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
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
                                    customer?.selfieUrl, customer?.name ?? ''),
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
                                      color: AppColors.white, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt_rounded,
                                    color: AppColors.white, size: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap to update your photo',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                          ),
                    ),
                    if (_isUploading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(color: AppColors.orange),
                      Text('Uploading...',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.orange)),
                    ],
                    const SizedBox(height: 24),
                    _buildField('Full name', _nameController,
                        Icons.person_outline_rounded,
                        textCapitalization: TextCapitalization.words),
                    const SizedBox(height: 16),
                    // Locked — the customer's registered phone number,
                    // set at signup. Changing it here would silently
                    // move where order updates and verification codes
                    // go, so it's display-only, same treatment as
                    // National ID below.
                    _readOnlyField(
                      'Phone number',
                      customer?.phone ?? '',
                      Icons.phone_outlined,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Alternate phone number (optional)',
                      _altPhoneController,
                      Icons.phone_android_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      helper: 'A second number you can be reached on.',
                    ),
                    const SizedBox(height: 16),
                    Text('Location',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontSize: 13,
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w600,
                                )),
                    const SizedBox(height: 6),
                    LocationPickerWidget(
                      hint: 'Search your home address...',
                      darkMode: false,
                      initialValue:
                          _selectedAddress.isNotEmpty ? _selectedAddress : null,
                      onSelected: (address, lat, lng) {
                        setState(() {
                          _selectedAddress = address;
                          _selectedLat = lat;
                          _selectedLng = lng;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // A skipped National ID stays addable. Once set it
                    // locks, since changing it would invalidate KYC.
                    if (_idWasSet)
                      _readOnlyField('National ID', customer?.nationalId ?? '',
                          Icons.badge_outlined)
                    else
                      _buildField(
                        'National ID (optional)',
                        _idController,
                        Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                        ],
                        helper: 'You can only set this once.',
                      ),
                    const SizedBox(height: 16),
                    // Mirrors signup: if the customer allowed push
                    // notifications there, this just shows "Active".
                    // If they declined, this toggle is the only in-app
                    // way back in.
                    Text('Notifications',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 13,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 6),
                    const NotificationPermissionTile(
                      darkMode: false,
                      inactiveMessage:
                          'Enable push notifications to get live updates on your order',
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveProfile,
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: AppColors.white),
                            )
                          : const Text('Save changes'),
                    ),
                    // ── Account deletion (Google Play requirement) ──
                    // Play needs this path to be REACHABLE in-app, not
                    // just to exist on the website.
                    const SizedBox(height: 32),
                    const Divider(color: AppColors.gray200),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.delete_forever_outlined,
                          color: AppColors.error),
                      title: Text(
                        'Delete account',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 15,
                              color: AppColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      subtitle: Text(
                        'Permanently remove your account and data',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.gray600),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppColors.gray400),
                      onTap: () => context.push('/delete-account'),
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

  /// Avatar with a real fallback path.
  ///
  /// Image.network with no errorBuilder renders nothing when the URL
  /// 404s or the bucket rejects the read — which is exactly what a
  /// wrong storageBucket or a `read: false` rule produces. Now a
  /// broken URL degrades to the initial instead of a blank circle, and
  /// the reason is printed to the console.
  Widget _avatar(String? url, String name) {
    if (_newSelfie != null) {
      return Image.file(_newSelfie!, fit: BoxFit.cover);
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const Center(
                child: CircularProgressIndicator(color: AppColors.orange),
              ),
        errorBuilder: (_, error, stack) {
          debugPrint('Selfie failed to load: $url');
          debugPrint('Reason: $error');
          return _initialAvatar(name);
        },
      );
    }
    return _initialAvatar(name);
  }

  Widget _initialAvatar(String name) {
    return Container(
      color: AppColors.orange,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(
            color: AppColors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _showPhotoOptions() {
    // Customer selfie only — no gallery for security
    _takeSelfie();
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? helper,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.navy,
              ),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: AppColors.gray400, size: 20),
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.gray400, fontSize: 11)),
        ],
      ],
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gray200),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gray400, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(value.isEmpty ? 'Not set' : value,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.gray600,
                        )),
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
}