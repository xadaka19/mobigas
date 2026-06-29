import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:mobigas/core/providers/auth_provider.dart';
import 'package:mobigas/core/widgets/location_picker_widget.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailController = TextEditingController();
  File? _selfie;
  bool _isCapturingSelfie = false;
  String _selectedAddress = '';

  bool _isLoading = false;
  int _currentStep = 0;

  double? _latitude;
  double? _longitude;


  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_nameController.text.trim().isEmpty) {
        _showError('Please enter your full name');
        return;
      }
      if (!_emailController.text.contains('@')) {
        _showError('Please enter a valid email address');
        return;
      }
      if (_idController.text.trim().length < 7) {
        _showError('Please enter a valid National ID number');
        return;
      }
      if (_selfie == null) {
        _showError('Please take a selfie for identity verification');
        return;
      }
    }
    if (_currentStep == 1) {
      if (_phoneController.text.trim().length < 9) {
        _showError('Please enter a valid phone number');
        return;
      }
      if (_latitude == null || _longitude == null) {
        _showError('Please pin your exact location on the map');
        return;
      }
    }
    if (_currentStep == 2) {
      if (_passwordController.text != _confirmPasswordController.text) {
        _showError('Passwords do not match');
        return;
      }
      if (_passwordController.text.length < 6) {
        _showError('Password must be at least 6 characters');
        return;
      }
      _submit();
      return;
    }
    setState(() => _currentStep++);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _captureSelfie() async {
    setState(() => _isCapturingSelfie = true);
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (photo != null) {
        setState(() => _selfie = File(photo.path));
      }
    } catch (e) {
      _showError('Could not access camera. Please allow camera access.');
    }
    setState(() => _isCapturingSelfie = false);
  }


  Future<void> _submit() async {
    setState(() => _isLoading = true);

    try {
      final auth = context.read<AuthProvider>();
      await auth.register(
        name: _nameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        phone: _phoneController.text.trim(),
        nationalId: _idController.text.trim(),
        county: _selectedAddress.split(',').last.trim(),
        area: _selectedAddress,
        estate: _selectedAddress,
        latitude: _latitude ?? 0.0,
        longitude: _longitude ?? 0.0,
        password: _passwordController.text,
        guarantors: [],
        selfieFile: _selfie,
      );

      if (auth.error != null) {
        _showError(auth.error!);
        setState(() => _isLoading = false);
        return;
      }

      if (mounted) context.go('/home');
    } catch (e) {
      _showError('Registration failed. Please try again.');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.orangeWarm,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_currentStep == 0) _buildStep1(),
                      if (_currentStep == 1) _buildStep2(),
                      if (_currentStep == 2) _buildStep3(),
                      const SizedBox(height: 32),
                      _buildNextButton(),
                      const SizedBox(height: 16),
                      _buildLoginLink(),
                    ],
                  ),
                ),
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
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  if (_currentStep > 0) {
                    setState(() => _currentStep--);
                  } else {
                    context.go('/onboarding');
                  }
                },
                child: const Icon(
                  Icons.arrow_back_ios_rounded,
                  color: AppColors.white,
                  size: 20,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Step ${_currentStep + 1} of 3',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _stepTitle(),
            style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: AppColors.white,
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _stepSubtitle(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.gray400,
                ),
          ),
        ],
      ),
    );
  }

  String _stepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Personal details';
      case 1:
        return 'Location & contact';
      case 2:
        return 'Secure your account';
      default:
        return '';
    }
  }

  String _stepSubtitle() {
    switch (_currentStep) {
      case 0:
        return 'Your ID is used for bank credit approval';
      case 1:
        return 'Your location helps us find the nearest gas vendor';
      case 2:
        return 'Choose a strong password for your MobiGas account';
      default:
        return '';
    }
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(3, (i) {
          final isActive = i == _currentStep;
          final isDone = i < _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDone || isActive
                          ? AppColors.orange
                          : AppColors.gray200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: 4),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Full name'),
        _input(
          controller: _nameController,
          hint: 'e.g. Jane Wanjiku Mwangi',
          icon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),
        _label('Email address'),
        _input(
          controller: _emailController,
          hint: 'e.g. jane@gmail.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 20),
        _label('National ID number'),
        _input(
          controller: _idController,
          hint: 'e.g. 12345678',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(8),
          ],
        ),
        const SizedBox(height: 20),
        _label('Selfie photo'),
        _buildSelfieCapture(),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.info_outline_rounded,
          text:
              'Your selfie is used for identity verification only. It is stored securely and never shared.',
        ),
      ],
    );
  }

  Widget _buildSelfieCapture() {
    return GestureDetector(
      onTap: _isCapturingSelfie ? null : _captureSelfie,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: _selfie != null
              ? Colors.transparent
              : AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _selfie != null
                ? AppColors.success
                : AppColors.gray200,
            width: _selfie != null ? 2 : 1,
          ),
        ),
        child: _selfie != null
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      _selfie!,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: _captureSelfie,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            color: AppColors.white, size: 18),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.white, size: 14),
                          const SizedBox(width: 4),
                          Text('Selfie captured',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  )),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : _isCapturingSelfie
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.orange),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.orange.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: AppColors.orange,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Take a selfie',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Front camera only · Used for identity verification',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: AppColors.gray400,
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Your home location'),
        LocationPickerWidget(
          hint: 'Search your home address in Kenya...',
          darkMode: false,
          initialValue: _selectedAddress.isNotEmpty ? _selectedAddress : null,
          onSelected: (address, lat, lng) {
            setState(() {
              _selectedAddress = address;
              _latitude = lat;
              _longitude = lng;
            });
          },
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.location_on_rounded,
          text:
              'Your location is used to find the nearest gas vendor to you. Be as specific as possible — include your building or street name.',
        ),
      ],
    );
  }


  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Password'),
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w500,
              ),
          decoration: const InputDecoration(
            hintText: 'At least 6 characters',
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: AppColors.gray400, size: 20),
          ),
        ),
        const SizedBox(height: 20),
        _label('Confirm password'),
        TextFormField(
          controller: _confirmPasswordController,
          obscureText: true,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w500,
              ),
          decoration: const InputDecoration(
            hintText: 'Re-enter your password',
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: AppColors.gray400, size: 20),
          ),
        ),
        const SizedBox(height: 20),
        _infoCard(
          icon: Icons.shield_outlined,
          text:
              'After creating your account you can immediately explore the app. Apply for gas credit when you are ready to place your first order.',
        ),
      ],
    );
  }




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

  Widget _input({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: AppColors.navy,
            fontWeight: FontWeight.w500,
          ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.gray400, size: 20),
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

  Widget _buildNextButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _nextStep,
      child: _isLoading
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.white,
              ),
            )
          : Text(_currentStep < 2 ? 'Continue' : 'Create Account'),
    );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: Text(
            'Sign in',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}
