import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/widgets/map_location_picker_widget.dart';

/// Sits at the top of the home screen until the customer has added
/// their phone number, pinned a delivery location, and (optionally)
/// verified their identity. These are the three steps that used to
/// block signup.
class ProfileCompletionBanner extends StatelessWidget {
  const ProfileCompletionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.showProfileBanner) return const SizedBox.shrink();

    final done = auth.profileStepsDone;
    final firstName = (auth.customer?.name ?? '').split(' ').first;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.rocket_launch_rounded,
                    color: AppColors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstName.isEmpty
                          ? 'Finish setting up'
                          : 'Finish setting up, $firstName',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$done of 3 done · about a minute left',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray400,
                            fontSize: 12,
                          ),
                    ),
                  ],
                ),
              ),
              if (auth.isProfileComplete)
                GestureDetector(
                  onTap: auth.dismissBanner,
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.gray600, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _stepRow(
            context,
            index: 0,
            icon: Icons.phone_outlined,
            title: 'Add your phone number',
            subtitle: 'So the rider can reach you on delivery',
            done: auth.hasPhone,
          ),
          _stepRow(
            context,
            index: 1,
            icon: Icons.location_on_outlined,
            title: 'Pin your delivery location',
            subtitle: 'Finds the nearest gas vendor to you',
            done: auth.hasLocation,
          ),
          _stepRow(
            context,
            index: 2,
            icon: Icons.verified_user_outlined,
            title: 'Verify your account',
            subtitle: 'Optional · National ID and photo',
            done: auth.hasVerification,
            isLast: true,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => ProfileCompletionSheet.show(
                context,
                initialStep: auth.firstIncompleteStep,
              ),
              child: Text(done == 0 ? 'Get started' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepRow(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool done,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: GestureDetector(
        onTap: () => ProfileCompletionSheet.show(context, initialStep: index),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle_rounded : icon,
              size: 18,
              color: done ? AppColors.success : AppColors.gray400,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: done ? AppColors.gray600 : AppColors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: AppColors.gray600,
                        ),
                  ),
                  if (!done)
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.gray600,
                            fontSize: 11,
                          ),
                    ),
                ],
              ),
            ),
            if (!done)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.gray600, size: 18),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------

class ProfileCompletionSheet extends StatefulWidget {
  const ProfileCompletionSheet({super.key, this.initialStep = 0});

  final int initialStep;

  static Future<void> show(BuildContext context, {int initialStep = 0}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProfileCompletionSheet(initialStep: initialStep),
    );
  }

  @override
  State<ProfileCompletionSheet> createState() => _ProfileCompletionSheetState();
}

class _ProfileCompletionSheetState extends State<ProfileCompletionSheet> {
  late int _step = widget.initialStep;
  bool _saving = false;
  String? _errorText;

  final _phoneController = TextEditingController();
  final _areaController = TextEditingController();
  final _idController = TextEditingController();

  double? _latitude;
  double? _longitude;
  File? _selfie;

  @override
  void initState() {
    super.initState();
    final customer = context.read<AuthProvider>().customer;
    _phoneController.text = customer?.phone ?? '';
    _areaController.text = customer?.area ?? '';
    if ((customer?.latitude ?? 0) != 0) _latitude = customer!.latitude;
    if ((customer?.longitude ?? 0) != 0) _longitude = customer!.longitude;
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _areaController.dispose();
    _idController.dispose();
    super.dispose();
  }

  /// BUG FIX: this used to call ScaffoldMessenger.showSnackBar. A
  /// floating snackbar renders at the bottom of the HOME screen's
  /// Scaffold — underneath this modal sheet, which covers up to 90%
  /// of the screen (see maxHeight in build()). So every validation
  /// failure ("Tell us your area, estate or landmark.", "Pin your
  /// exact location on the map.") was painted behind the sheet and
  /// never seen: the button spun, stopped, and the step didn't
  /// advance — indistinguishable from a save that silently did
  /// nothing. Rendering inline, just above the button, puts the
  /// message where the user is already looking.
  void _showError(String msg) {
    setState(() => _errorText = msg);
  }

  Future<void> _captureSelfie() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (photo != null && mounted) {
        setState(() => _selfie = File(photo.path));
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not open the camera. Allow camera access to add a photo.');
      }
    }
  }

  Future<void> _saveCurrentStep() async {
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final auth = context.read<AuthProvider>();
    String? problem;

    switch (_step) {
      case 0:
        problem = await auth.savePhone(_phoneController.text);
        break;
      case 1:
        problem = await auth.saveLocation(
          area: _areaController.text,
          latitude: _latitude ?? 0,
          longitude: _longitude ?? 0,
        );
        break;
      case 2:
        if (_idController.text.trim().isEmpty && _selfie == null) {
          problem = 'Add a National ID or a photo, or skip this step.';
        } else {
          problem = await auth.saveVerification(
            nationalId: _idController.text,
            selfie: _selfie,
          );
        }
        break;
    }

    if (!mounted) return;
    setState(() => _saving = false);

    if (problem != null) {
      _showError(problem);
      return;
    }
    _advance();
  }

  void _advance() {
    if (_step < 2) {
      setState(() {
        _step++;
        _errorText = null;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.gray200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildStepIndicator(),
              const SizedBox(height: 20),
              Text(
                _title(),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: AppColors.navy,
                      fontSize: 22,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _subtitle(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.gray600,
                    ),
              ),
              const SizedBox(height: 24),
              if (_step == 0) _buildPhoneStep(),
              if (_step == 1) _buildLocationStep(),
              if (_step == 2) _buildVerificationStep(),
              if (_errorText != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.error,
                                    height: 1.5,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _saveCurrentStep,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.white,
                        ),
                      )
                    : Text(_step < 2 ? 'Save and continue' : 'Save'),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _saving
                      ? null
                      : () {
                          if (_step < 2) {
                            setState(() {
                              _step++;
                              _errorText = null;
                            });
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                  child: Text(
                    _step == 2 ? 'Skip for now' : 'Do this later',
                    style: const TextStyle(color: AppColors.gray600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _title() {
    switch (_step) {
      case 0:
        return 'Your phone number';
      case 1:
        return 'Where should we deliver?';
      default:
        return 'Verify your account';
    }
  }

  String _subtitle() {
    switch (_step) {
      case 0:
        return 'The rider calls this number when your gas arrives.';
      case 1:
        return 'We match you with the closest vendor to this pin.';
      default:
        return 'Optional. Adds a verified badge and speeds up support.';
    }
  }

  Widget _buildStepIndicator() {
    return Row(
      children: List.generate(3, (i) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              decoration: BoxDecoration(
                color: i <= _step ? AppColors.orange : AppColors.gray200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPhoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Phone number'),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          style: _fieldStyle(),
          decoration: const InputDecoration(
            hintText: 'e.g. 0712 345 678',
            prefixIcon:
                Icon(Icons.phone_outlined, color: AppColors.gray400, size: 20),
          ),
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.lock_outline_rounded,
          text: 'Only the vendor delivering your order can see this number.',
        ),
      ],
    );
  }

  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Pin your exact location'),
        MapLocationPickerWidget(
          initialLat: _latitude,
          initialLng: _longitude,
          onLocationSelected: (lat, lng) {
            setState(() {
              _latitude = lat;
              _longitude = lng;
            });
          },
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.location_on_rounded,
          text: 'Drag the pin to your building or gate so the rider '
              'finds you first time.',
        ),
        const SizedBox(height: 20),
        _label('Landmark for the rider (optional)'),
        TextFormField(
          controller: _areaController,
          textCapitalization: TextCapitalization.words,
          style: _fieldStyle(),
          decoration: const InputDecoration(
            hintText: 'e.g. blue gate opposite Mzuzi Park',
            prefixIcon: Icon(Icons.signpost_outlined,
                color: AppColors.gray400, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('National ID number (optional)'),
        TextFormField(
          controller: _idController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
          style: _fieldStyle(),
          decoration: const InputDecoration(
            hintText: 'e.g. 12345678',
            prefixIcon:
                Icon(Icons.badge_outlined, color: AppColors.gray400, size: 20),
          ),
        ),
        const SizedBox(height: 20),
        _label('Profile photo (optional)'),
        GestureDetector(
          onTap: _captureSelfie,
          child: Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _selfie != null ? AppColors.success : AppColors.gray200,
                width: _selfie != null ? 2 : 1,
              ),
            ),
            child: _selfie != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(_selfie!,
                        width: double.infinity,
                        height: 150,
                        fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_outlined,
                            color: AppColors.orange, size: 28),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tap to add a photo',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.shield_outlined,
          text: 'Stored securely and never shared with vendors or riders.',
        ),
      ],
    );
  }

  TextStyle? _fieldStyle() =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.navy,
            fontWeight: FontWeight.w500,
          );

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.navy,
            ),
      ),
    );
  }

  Widget _infoCard({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.orangeLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.orangeDeep,
                    height: 1.5,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
