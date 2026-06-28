import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:geolocator/geolocator.dart';

class VendorOnboardingScreen extends StatefulWidget {
  const VendorOnboardingScreen({super.key});

  @override
  State<VendorOnboardingScreen> createState() =>
      _VendorOnboardingScreenState();
}

class _VendorOnboardingScreenState extends State<VendorOnboardingScreen> {
  int _currentStep = 0;
  final _businessNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _idController = TextEditingController();
  final _areaController = TextEditingController();
  final _estateController = TextEditingController();

  String _selectedCounty = 'Nairobi';
  bool _isLocating = false;
  double? _latitude;
  double? _longitude;

  final List<String> _counties = [
    'Nairobi', 'Kiambu', 'Muranga', 'Mombasa', 'Nakuru', 'Nyeri',
  ];

  final List<String> _selectedBrands = [];
  final List<String> _availableBrands = [
    'Total', 'K-Gas', 'Afrigaz', 'Orion', 'Pro Gas', 'Hashi'
  ];
  final TextEditingController _customBrandController = TextEditingController();

  final List<String> _selectedSizes = [];
  final List<String> _availableSizes = ['3kg', '6kg', '13kg'];

  bool _isLoading = false;

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _phoneController.dispose();
    _idController.dispose();
    _areaController.dispose();
    _estateController.dispose();
    _customBrandController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep == 0) {
      if (_businessNameController.text.trim().isEmpty) {
        _showError('Enter your business name');
        return;
      }
      if (_ownerNameController.text.trim().isEmpty) {
        _showError('Enter owner full name');
        return;
      }
      if (_idController.text.trim().length < 7) {
        _showError('Enter a valid National ID');
        return;
      }
    }
    if (_currentStep == 1) {
      if (_phoneController.text.trim().length < 9) {
        _showError('Enter a valid M-Pesa number');
        return;
      }
      if (_areaController.text.trim().isEmpty) {
        _showError('Enter your area');
        return;
      }
      if (_latitude == null) {
        _showError('Pin your shop location');
        return;
      }
    }
    if (_currentStep == 2) {
      if (_selectedBrands.isEmpty) {
        _showError('Select at least one gas brand you stock');
        return;
      }
      if (_selectedSizes.isEmpty) {
        _showError('Select at least one cylinder size you stock');
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _detectLocation() async {
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _isLocating = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isLocating = false;
      });
    } catch (e) {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isLoading = false);
    if (mounted) context.go('/vendor-home');
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
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (_currentStep == 0) _buildStep1(),
                    if (_currentStep == 1) _buildStep2(),
                    if (_currentStep == 2) _buildStep3(),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _next,
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: AppColors.white,
                              ),
                            )
                          : Text(_currentStep < 2
                              ? 'Continue'
                              : 'Submit for approval'),
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

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                    context.go('/');
                  }
                },
                child: const Icon(Icons.arrow_back_ios_rounded,
                    color: AppColors.white, size: 20),
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
                  fontSize: 22,
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
      case 0: return 'Business details';
      case 1: return 'Location & M-Pesa';
      case 2: return 'Stock & brands';
      default: return '';
    }
  }

  String _stepSubtitle() {
    switch (_currentStep) {
      case 0: return 'Tell us about your gas business';
      case 1: return 'Where is your shop? Where do we send payment?';
      case 2: return 'What gas brands and sizes do you stock?';
      default: return '';
    }
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: List.generate(3, (i) {
          final isDone = i < _currentStep;
          final isActive = i == _currentStep;
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
        _label('Business name'),
        _input(
          controller: _businessNameController,
          hint: 'e.g. Kamau Gas Supplies',
          icon: Icons.store_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),
        _label('Owner full name'),
        _input(
          controller: _ownerNameController,
          hint: 'e.g. James Kamau Njoroge',
          icon: Icons.person_outline_rounded,
          textCapitalization: TextCapitalization.words,
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
        const SizedBox(height: 16),
        _infoCard(
          icon: Icons.info_outline_rounded,
          text:
              'Your details will be verified by MobiGas before your account is activated. This usually takes 24 hours.',
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final hasLocation = _latitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('M-Pesa number (payments go here)'),
        _input(
          controller: _phoneController,
          hint: 'e.g. 0712 345 678',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
        ),
        const SizedBox(height: 8),
        _infoCard(
          icon: Icons.payments_outlined,
          text:
              'When a customer confirms delivery with their PIN, payment is sent to this M-Pesa number instantly.',
        ),
        const SizedBox(height: 20),
        _label('County'),
        _countyDropdown(),
        const SizedBox(height: 20),
        _label('Area / Town'),
        _input(
          controller: _areaController,
          hint: 'e.g. Kasarani, Westlands',
          icon: Icons.location_city_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),
        _label('Estate / Street'),
        _input(
          controller: _estateController,
          hint: 'e.g. Mirema Drive, Bypass Road',
          icon: Icons.home_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 20),
        _label('Pin your shop location'),
        GestureDetector(
          onTap: _isLocating ? null : _detectLocation,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:
                  hasLocation ? AppColors.successLight : AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasLocation
                    ? AppColors.success
                    : AppColors.gray200,
                width: hasLocation ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasLocation
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: _isLocating
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.orange,
                          ),
                        )
                      : Icon(
                          hasLocation
                              ? Icons.location_on_rounded
                              : Icons.my_location_rounded,
                          color: hasLocation
                              ? AppColors.success
                              : AppColors.orange,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasLocation
                            ? 'Shop location pinned'
                            : 'Tap to pin shop location',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              fontSize: 14,
                              color: hasLocation
                                  ? AppColors.success
                                  : AppColors.navy,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasLocation
                            ? '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}'
                            : 'Customers near you will see your shop',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: hasLocation
                                  ? AppColors.success
                                  : AppColors.gray400,
                            ),
                      ),
                    ],
                  ),
                ),
                if (hasLocation)
                  GestureDetector(
                    onTap: _detectLocation,
                    child: const Icon(Icons.refresh_rounded,
                        color: AppColors.gray400, size: 18),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Gas brands you stock'),
        const SizedBox(height: 4),
        Text(
          'Select all that apply',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray400,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableBrands.map((brand) {
            final selected = _selectedBrands.contains(brand);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (selected) {
                    _selectedBrands.remove(brand);
                  } else {
                    _selectedBrands.add(brand);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.orange
                      : AppColors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: selected
                        ? AppColors.orange
                        : AppColors.gray200,
                  ),
                ),
                child: Text(
                  brand,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? AppColors.white
                            : AppColors.navy,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Custom brand input
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _customBrandController,
                textCapitalization: TextCapitalization.words,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.navy,
                    ),
                decoration: const InputDecoration(
                  hintText: 'Add other brand...',
                  prefixIcon: Icon(Icons.add_rounded,
                      color: AppColors.gray400, size: 20),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                final brand = _customBrandController.text.trim();
                if (brand.isNotEmpty &&
                    !_selectedBrands.contains(brand) &&
                    !_availableBrands.contains(brand)) {
                  setState(() {
                    _selectedBrands.add(brand);
                    _customBrandController.clear();
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(60, 50),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _label('Cylinder sizes you stock'),
        const SizedBox(height: 12),
        Row(
          children: _availableSizes.map((size) {
            final selected = _selectedSizes.contains(size);
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedSizes.remove(size);
                    } else {
                      _selectedSizes.add(size);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.orange.withValues(alpha: 0.08)
                        : AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColors.orange
                          : AppColors.gray200,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.local_fire_department_rounded,
                        color: selected
                            ? AppColors.orange
                            : AppColors.gray400,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        size,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: selected
                                  ? AppColors.orange
                                  : AppColors.navy,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        _infoCard(
          icon: Icons.verified_outlined,
          text:
              'MobiGas team will verify your business within 24 hours. You will receive an SMS once your account is active.',
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

  Widget _countyDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gray200),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCounty,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.gray400),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w500,
              ),
          items: _counties
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _selectedCounty = v!),
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
        border:
            Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
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
