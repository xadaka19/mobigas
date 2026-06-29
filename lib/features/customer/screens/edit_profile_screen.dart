import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/widgets/location_picker_widget.dart';

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
  String _selectedAddress = '';
  double _selectedLat = 0.0;
  double _selectedLng = 0.0;

  @override
  void initState() {
    super.initState();
    final customer = context.read<AuthProvider>().customer;
    _nameController = TextEditingController(text: customer?.name ?? '');
    _phoneController = TextEditingController(text: customer?.phone ?? '');
    _selectedAddress = customer?.estate ?? '';
    _selectedLat = customer?.latitude ?? 0;
    _selectedLng = customer?.longitude ?? 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _takeSelfie() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (photo != null) {
      setState(() => _newSelfie = File(photo.path));
    }
  }


  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    final auth = context.read<AuthProvider>();
    if (!mounted) return;
    final uid = auth.customer?.id;
    if (uid == null) return;

    try {
      String? selfieUrl;

      // Upload new selfie if selected
      if (_newSelfie != null) {
        setState(() => _isUploading = true);
        final ref = FirebaseStorage.instance
            .ref()
            .child('selfies')
            .child(uid);
        await ref.putFile(_newSelfie!);
        selfieUrl = await ref.getDownloadURL();
        setState(() => _isUploading = false);
      }

      // Update Firestore
      final updates = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'estate': _selectedAddress,
        'area': _selectedAddress,
        'latitude': _selectedLat,
        'longitude': _selectedLng,
      };
      if (selfieUrl != null) updates['selfieUrl'] = selfieUrl;

      await FirebaseService.users.doc(uid).update(updates);
      if (mounted) await auth.refreshCustomer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: \$e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final customer = context.watch<AuthProvider>().customer;

    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: const BoxDecoration(
                color: AppColors.navy,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(24)),
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
                    // Selfie section
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
                                child: _newSelfie != null
                                    ? Image.file(_newSelfie!,
                                        fit: BoxFit.cover)
                                    : customer?.selfieUrl != null
                                        ? Image.network(
                                            customer!.selfieUrl!,
                                            fit: BoxFit.cover,
                                            loadingBuilder:
                                                (_, child, progress) =>
                                                    progress == null
                                                        ? child
                                                        : const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                    color: AppColors
                                                                        .orange)),
                                          )
                                        : Container(
                                            color: AppColors.orange,
                                            child: Center(
                                              child: Text(
                                                customer?.name
                                                        .isNotEmpty ==
                                                    true
                                                    ? customer!.name[0]
                                                        .toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  color: AppColors.white,
                                                  fontSize: 48,
                                                  fontWeight:
                                                      FontWeight.w700,
                                                ),
                                              ),
                                            ),
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
                      const LinearProgressIndicator(
                          color: AppColors.orange),
                      Text('Uploading...',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppColors.orange)),
                    ],
                    const SizedBox(height: 24),
                    // Fields
                    _buildField('Full name', _nameController,
                        Icons.person_outline_rounded),
                    const SizedBox(height: 16),
                    _buildField('Phone number', _phoneController,
                        Icons.phone_outlined,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 16),
                    Text('Location',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 13,
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            )),
                    const SizedBox(height: 6),
                    LocationPickerWidget(
                      hint: 'Search your home address...',
                      darkMode: false,
                      initialValue: _selectedAddress.isNotEmpty
                          ? _selectedAddress
                          : null,
                      onSelected: (address, lat, lng) {
                        setState(() {
                          _selectedAddress = address;
                          _selectedLat = lat;
                          _selectedLng = lng;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    // Read-only fields
                    _readOnlyField('National ID',
                        customer?.nationalId ?? '', Icons.badge_outlined),
                    const SizedBox(height: 16),
                    _readOnlyField('County', customer?.county ?? '',
                        Icons.map_outlined),
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
                  ],
                ),
              ),
            ),
          ],
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.navy,
              ),
          decoration: InputDecoration(
            prefixIcon:
                Icon(icon, color: AppColors.gray400, size: 20),
          ),
        ),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.gray100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gray200),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.gray400, size: 20),
              const SizedBox(width: 12),
              Text(value,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray600,
                      )),
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
