import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/widgets/location_picker_widget.dart';

class VendorSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? existingData;
  const VendorSetupScreen({super.key, this.existingData});

  @override
  State<VendorSetupScreen> createState() => _VendorSetupScreenState();
}

class _VendorSetupScreenState extends State<VendorSetupScreen> {
  int _step = 0; // 0=business, 1=location, 2=gas products
  bool _isSaving = false;

  // Business type
  String _businessType = 'sole'; // sole, registered, petrol_station
  File? _certificateFile;
  bool _isUploadingCert = false; // ignore: prefer_final_fields

  // Step 1 - Business
  late TextEditingController _businessNameController;
  late TextEditingController _ownerNameController;
  late TextEditingController _idOrBrnController; // National ID or BRN
  late TextEditingController _phoneController;
  late TextEditingController _deliveryTimeController;
  String _paymentMethod = 'mpesa'; // mpesa, till, paybill
  late TextEditingController _tillController;
  late TextEditingController _paybillController;
  late TextEditingController _paybillAccountController;

  // Step 2 - Location

  // Step 3 - Gas products & prices
  // Refill prices
  final Map<String, TextEditingController> _priceControllers = {
    '3kg': TextEditingController(),
    '6kg': TextEditingController(),
    '13kg': TextEditingController(),
  };
  final Map<String, bool> _sizeAvailable = {
    '3kg': true,
    '6kg': true,
    '13kg': false,
  };
  // Full kit prices (gas + new cylinder)
  final Map<String, TextEditingController> _fullKitPriceControllers = {
    '3kg': TextEditingController(),
    '6kg': TextEditingController(),
    '13kg': TextEditingController(),
  };
  final Map<String, bool> _fullKitAvailable = {
    '3kg': false,
    '6kg': false,
    '13kg': false,
  };
  // Grill kit (6kg only: gas + cylinder + stove + grill)
  final TextEditingController _grillKitPriceController = TextEditingController();
  bool _grillKitAvailable = false;

  // Step 2 - Location (Google Places)
  String _selectedAddress = '';
  double _selectedLat = 0.0;
  double _selectedLng = 0.0;
  final List<String> _availableBrands = List<String>.from(KenyanGasBrands.all);
  final List<String> _selectedBrands = [];
  final TextEditingController _customBrandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.existingData ?? {};
    _businessType = d['businessType'] ?? 'sole';
    _businessNameController =
        TextEditingController(text: d['businessName'] ?? '');
    _ownerNameController =
        TextEditingController(text: d['ownerName'] ?? '');
    _idOrBrnController = TextEditingController(
        text: d['nationalId'] ?? d['businessRegNumber'] ?? '');
    _phoneController = TextEditingController(text: d['phone'] ?? '');
    _deliveryTimeController = TextEditingController(text: d['deliveryTime'] ?? '20–40 min');
    _tillController = TextEditingController(text: d['tillNumber'] ?? '');
    _paybillController = TextEditingController(text: d['paybillNumber'] ?? '');
    _paybillAccountController = TextEditingController(text: d['paybillAccount'] ?? '');
    _paymentMethod = d['paymentMethod'] ?? 'mpesa';

    // Load existing listings
    final listings = d['listings'] as List? ?? [];
    for (final l in listings) {
      final size = l['size'] as String?;
      final productType = l['productType'] as String? ?? 'refill';
      final price = (l['price'] ?? 0).toString();
      final available = l['available'] as bool? ?? false;

      if (size == null) continue;

      if (productType == 'refill' && _priceControllers.containsKey(size)) {
        _priceControllers[size]!.text = price;
        _sizeAvailable[size] = available;
      } else if (productType == 'fullKit' &&
          _fullKitPriceControllers.containsKey(size)) {
        _fullKitPriceControllers[size]!.text = price;
        _fullKitAvailable[size] = available;
      } else if (productType == 'grillKit') {
        _grillKitPriceController.text = price;
        _grillKitAvailable = available;
      }
    }

    // Load custom brands first so they appear in the list
    final customBrands = d['customBrands'] as List? ?? [];
    for (final b in customBrands) {
      final brand = b as String;
      if (!_availableBrands.contains(brand)) {
        _availableBrands.add(brand);
      }
    }

    // Load existing brands - including custom ones not in default list
    final brands = d['brands'] as List? ?? [];
    for (final b in brands) {
      final brand = b as String;
      // Add to available list if it's a custom brand
      if (!_availableBrands.contains(brand)) {
        _availableBrands.add(brand);
      }
      // Mark as selected
      if (!_selectedBrands.contains(brand)) {
        _selectedBrands.add(brand);
      }
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _idOrBrnController.dispose();
    _phoneController.dispose();
    _deliveryTimeController.dispose();
    _tillController.dispose();
    _paybillController.dispose();
    _paybillAccountController.dispose();
    for (final c in _priceControllers.values) { c.dispose(); }
    for (final c in _fullKitPriceControllers.values) { c.dispose(); }
    _grillKitPriceController.dispose();
    _customBrandController.dispose();
    super.dispose();
  }

  String get _vendorId =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  bool get _step0Valid {
    if (_businessNameController.text.trim().isEmpty) { return false; }
    if (_ownerNameController.text.trim().isEmpty) { return false; }
    if (_idOrBrnController.text.trim().isEmpty) { return false; }
    if (_paymentMethod == 'mpesa' &&
        _phoneController.text.trim().length < 9) { return false; }
    if (_paymentMethod == 'till' &&
        _tillController.text.trim().isEmpty) { return false; }
    if (_paymentMethod == 'paybill' &&
        (_paybillController.text.trim().isEmpty ||
            _paybillAccountController.text.trim().isEmpty)) { return false; }
    return true;
  }

  bool get _step1Valid => _selectedAddress.isNotEmpty && _selectedLat != 0.0;

  bool get _step2Valid =>
      _selectedBrands.isNotEmpty &&
      _priceControllers.entries
          .any((e) => _sizeAvailable[e.key] == true && e.value.text.isNotEmpty);

  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      // Upload certificate if selected
      String? certificateUrl;
      if (_certificateFile != null) {
        setState(() => _isUploadingCert = true);
        final ref = FirebaseStorage.instance
            .ref()
            .child('business_certificates')
            .child(_vendorId);
        await ref.putFile(_certificateFile!);
        certificateUrl = await ref.getDownloadURL();
        setState(() => _isUploadingCert = false);
      }

      final listings = <Map<String, dynamic>>[];
      // Refills
      for (final e in _priceControllers.entries) {
        listings.add({
          'size': e.key,
          'kg': e.key == '3kg' ? 3 : e.key == '6kg' ? 6 : 13,
          'price': double.tryParse(e.value.text) ?? 0.0,
          'available': _sizeAvailable[e.key] ?? false,
          'productType': 'refill',
        });
      }
      // Full kits
      for (final e in _fullKitPriceControllers.entries) {
        if (_fullKitAvailable[e.key] == true) {
          listings.add({
            'size': e.key,
            'kg': e.key == '3kg' ? 3 : e.key == '6kg' ? 6 : 13,
            'price': double.tryParse(e.value.text) ?? 0.0,
            'available': true,
            'productType': 'fullKit',
          });
        }
      }
      // Grill kit
      if (_grillKitAvailable) {
        listings.add({
          'size': '6kg',
          'kg': 6,
          'price': double.tryParse(_grillKitPriceController.text) ?? 0.0,
          'available': true,
          'productType': 'grillKit',
        });
      }

      await FirebaseService.vendors.doc(_vendorId).set({
        'businessName': _businessNameController.text.trim(),
        'ownerName': _ownerNameController.text.trim(),
        'businessType': _businessType,
        if (_businessType == 'sole')
          'nationalId': _idOrBrnController.text.trim()
        else
          'businessRegNumber': _idOrBrnController.text.trim(),
        'phone': _phoneController.text.trim(),
        'paymentMethod': _paymentMethod,
        'tillNumber': _tillController.text.trim(),
        'paybillNumber': _paybillController.text.trim(),
        'paybillAccount': _paybillAccountController.text.trim(),
        'address': _selectedAddress,
        'latitude': _selectedLat,
        'longitude': _selectedLng,
        'brands': _selectedBrands,
        'customBrands': _selectedBrands
            .where((b) => !KenyanGasBrands.all.contains(b))
            .toList(),
        'listings': listings,
        'isVerified': false,
        'isOnline': false,
        'rating': 0.0,
        'totalReviews': 0,
        'deliveryTime': _deliveryTimeController.text.trim().isNotEmpty ? _deliveryTimeController.text.trim() : '20–40 min',
        'updatedAt': FieldValue.serverTimestamp(),
        'certificateUrl': certificateUrl,
        'createdAt': widget.existingData == null
            ? FieldValue.serverTimestamp()
            : widget.existingData!['createdAt'],
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save. Try again.'),
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
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStepIndicator(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: _step == 0
                    ? _buildStep0()
                    : _step == 1
                        ? _buildStep1()
                        : _buildStep2(),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.close_rounded,
                color: AppColors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _step == 0
                      ? 'Business details'
                      : _step == 1
                          ? 'Your location'
                          : 'Gas products & prices',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.white,
                      ),
                ),
                Text(
                  'Step ${_step + 1} of 3',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.gray400,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: List.generate(3, (i) {
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= _step
                          ? AppColors.orange
                          : AppColors.white.withValues(alpha: 0.1),
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

  // ── STEP 0: BUSINESS ─────────────────────────────────────────────
  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Business type selector
        Text('Business type',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 10),
        Row(
          children: [
            _bizTypeTab('sole', Icons.person_outline_rounded,
                'Sole Proprietor'),
            const SizedBox(width: 8),
            _bizTypeTab('registered', Icons.business_outlined,
                'Registered Biz'),
            const SizedBox(width: 8),
            _bizTypeTab('petrol_station', Icons.local_gas_station_outlined,
                'Petrol Station'),
          ],
        ),
        const SizedBox(height: 20),
        _field('Business name', _businessNameController,
            Icons.store_outlined,
            hint: _businessType == 'sole'
                ? 'e.g. Kamau Gas Supplies'
                : _businessType == 'registered'
                    ? 'e.g. Kamau Gas Ltd'
                    : 'e.g. Total Mirema Station'),
        const SizedBox(height: 16),
        _field(
          _businessType == 'sole' ? 'Owner full name' : 'Contact person',
          _ownerNameController,
          Icons.person_outline_rounded,
          hint: 'e.g. James Kamau',
        ),
        const SizedBox(height: 16),
        _field(
          _businessType == 'sole'
              ? 'National ID number'
              : 'Business Registration Number',
          _idOrBrnController,
          _businessType == 'sole'
              ? Icons.badge_outlined
              : Icons.app_registration_rounded,
          hint: _businessType == 'sole'
              ? 'e.g. 12345678'
              : 'e.g. BRN/2024/123456',
          keyboardType: _businessType == 'sole'
              ? TextInputType.number
              : TextInputType.text,
        ),
        const SizedBox(height: 16),
        _buildCertificateUpload(),
        const SizedBox(height: 16),
        _buildPaymentMethodSelector(),
        const SizedBox(height: 16),
        _field('Delivery time', _deliveryTimeController,
            Icons.access_time_rounded,
            hint: 'e.g. 20–40 min'),
      ],
    );
  }

  // ── STEP 1: LOCATION ─────────────────────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Business location',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 4),
        Text('Search and select your exact business address',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400, fontSize: 12)),
        const SizedBox(height: 12),
        LocationPickerWidget(
          hint: 'e.g. Total Station, Mirema Drive, Nairobi...',
          darkMode: true,
          initialValue: _selectedAddress.isNotEmpty ? _selectedAddress : null,
          onSelected: (address, lat, lng) {
            setState(() {
              _selectedAddress = address;
              _selectedLat = lat;
              _selectedLng = lng;
            });
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppColors.orange, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your exact location is shared with customers for accurate delivery matching.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.orange, height: 1.4, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Gas brands you stock',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableBrands.map((brand) {
            final selected = _selectedBrands.contains(brand);
            return GestureDetector(
              onTap: () => setState(() {
                if (selected) {
                  _selectedBrands.remove(brand);
                } else {
                  _selectedBrands.add(brand);
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.orange
                      : AppColors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? AppColors.orange
                        : AppColors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  brand,
                  style: TextStyle(
                    color: selected
                        ? AppColors.white
                        : AppColors.gray400,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _customBrandController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppColors.navy, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Add other brand...',
                  hintStyle: const TextStyle(color: AppColors.gray400),
                  prefixIcon: const Icon(Icons.add_rounded,
                      color: AppColors.gray400, size: 20),
                  filled: true,
                  fillColor: AppColors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gray200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.orange),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () {
                final brand = _customBrandController.text.trim();
                if (brand.isNotEmpty) {
                  setState(() {
                    if (!_availableBrands.contains(brand)) {
                      _availableBrands.add(brand);
                    }
                    if (!_selectedBrands.contains(brand)) {
                      _selectedBrands.add(brand);
                    }
                    _customBrandController.clear();
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(60, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _sectionHeader('Gas Refill (Exchange empty cylinder)'),
        const SizedBox(height: 4),
        Text('Customer exchanges their empty cylinder for a filled one',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400, fontSize: 11)),
        const SizedBox(height: 10),
        ..._priceControllers.entries.map((e) {
          final size = e.key;
          final controller = e.value;
          final available = _sizeAvailable[size] ?? false;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: available
                    ? AppColors.orange.withValues(alpha: 0.3)
                    : AppColors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                // Available toggle
                GestureDetector(
                  onTap: () => setState(
                      () => _sizeAvailable[size] = !available),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: available
                          ? AppColors.orange
                          : AppColors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: available
                            ? AppColors.orange
                            : AppColors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        size,
                        style: TextStyle(
                          color: available
                              ? AppColors.white
                              : AppColors.gray600,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        size == '3kg'
                            ? '3kg cylinder'
                            : size == '6kg'
                                ? '6kg cylinder'
                                : '13kg cylinder',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                              color: available
                                  ? AppColors.white
                                  : AppColors.gray600,
                              fontSize: 14,
                            ),
                      ),
                      Text(
                        available ? 'Available' : 'Not in stock',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: available
                                  ? AppColors.success
                                  : AppColors.gray600,
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Price input
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: controller,
                    enabled: available,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    style: TextStyle(
                      color: available
                          ? AppColors.white
                          : AppColors.gray600,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      prefixText: 'KES ',
                      prefixStyle: TextStyle(
                        color: available
                            ? AppColors.orange
                            : AppColors.gray600,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      hintText: '0',
                      hintStyle:
                          const TextStyle(color: AppColors.gray600),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color:
                                AppColors.white.withValues(alpha: 0.2)),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color:
                                AppColors.white.withValues(alpha: 0.05)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.orange),
                      ),
                      filled: true,
                      fillColor: AppColors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
        // Full Kit Section
        _sectionHeader('Full Cylinder Kit (Gas + New Cylinder)'),
        const SizedBox(height: 4),
        Text('Customer gets a brand new cylinder — no empty needed',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400, fontSize: 11)),
        const SizedBox(height: 10),
        ..._fullKitPriceControllers.entries.map((e) =>
            _productRow(e.key, e.value,
                available: _fullKitAvailable[e.key] ?? false,
                onToggle: (v) =>
                    setState(() => _fullKitAvailable[e.key] = v))),
        const SizedBox(height: 24),
        // Grill Kit Section
        _sectionHeader('Grill Kit — 6kg only'),
        const SizedBox(height: 4),
        Text('Gas + Cylinder + LPG Stove + Grill — complete package',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.gray400, fontSize: 11)),
        const SizedBox(height: 10),
        _productRow('6kg', _grillKitPriceController,
            available: _grillKitAvailable,
            onToggle: (v) => setState(() => _grillKitAvailable = v),
            label: 'Grill Kit (6kg)'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.orange.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.tips_and_updates_outlined,
                  color: AppColors.orange, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap size to toggle. Bank pays you the price you set directly on delivery confirmation.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.orange,
                        height: 1.4,
                        fontSize: 11,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).padding.bottom + 16),
      decoration: BoxDecoration(
        color: AppColors.navy,
        border: Border(
            top: BorderSide(
                color: AppColors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.white,
                  side: BorderSide(
                      color: AppColors.white.withValues(alpha: 0.3)),
                ),
                child: const Text('Back'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () {
                if (_step == 0 && !_step0Valid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Please fill in all business details'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (_step == 1 && !_step1Valid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Please fill in your location details'),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (_step < 2) {
                  setState(() => _step++);
                } else {
                  if (!_step2Valid) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Select at least one brand and set a price'),
                        backgroundColor: AppColors.error,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  _save();
                }
              },
              child: _isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.white),
                    )
                  : Text(_step < 2 ? 'Continue' : 'Save & go live'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bizTypeTab(String type, IconData icon, String label) {
    final selected = _businessType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _businessType = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.orange
                : AppColors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.orange
                  : AppColors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color:
                      selected ? AppColors.white : AppColors.gray400,
                  size: 18),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? AppColors.white
                        : AppColors.gray400,
                    fontSize: 10,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCertificate() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file != null) {
      setState(() => _certificateFile = File(file.path));
    }
  }

  Widget _buildCertificateUpload() {
    final hasCert = _certificateFile != null ||
        (widget.existingData?['certificateUrl'] != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Business certificate / ID document',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 4),
        Text(
          _businessType == 'sole'
              ? 'Upload a photo of your National ID (front)'
              : 'Upload your Certificate of Incorporation or Business Registration',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.gray400, fontSize: 11),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickCertificate,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasCert
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasCert
                    ? AppColors.success.withValues(alpha: 0.4)
                    : AppColors.white.withValues(alpha: 0.2),
                width: hasCert ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasCert
                      ? Icons.check_circle_rounded
                      : Icons.upload_file_rounded,
                  color: hasCert ? AppColors.success : AppColors.gray400,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasCert
                            ? _certificateFile != null
                                ? 'Document selected ✓'
                                : 'Document already uploaded ✓'
                            : 'Tap to upload document',
                        style: TextStyle(
                          color: hasCert
                              ? AppColors.success
                              : AppColors.gray400,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        hasCert
                            ? 'Tap to change'
                            : 'JPG, PNG accepted · Used for verification only',
                        style: TextStyle(
                            color: AppColors.gray600, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_isUploadingCert)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.orange),
                  ),
              ],
            ),
          ),
        ),
        if (_certificateFile != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _certificateFile!,
              height: 120,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How do you want to receive payment?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 13,
                  color: AppColors.white,
                  fontWeight: FontWeight.w600,
                )),
        const SizedBox(height: 10),
        // Payment method tabs
        Row(
          children: [
            _paymentTab('mpesa', Icons.phone_android_rounded, 'M-Pesa'),
            const SizedBox(width: 8),
            _paymentTab('till', Icons.store_rounded, 'Till No.'),
            const SizedBox(width: 8),
            _paymentTab('paybill', Icons.account_balance_outlined, 'Paybill'),
          ],
        ),
        const SizedBox(height: 14),
        // Fields based on selection
        if (_paymentMethod == 'mpesa') ...[
          _field('M-Pesa phone number', _phoneController,
              Icons.phone_outlined,
              hint: '0712 345 678',
              keyboardType: TextInputType.phone),
          const SizedBox(height: 8),
          _paymentNote(
              'Bank sends payment directly to this M-Pesa number on delivery confirmation.'),
        ] else if (_paymentMethod == 'till') ...[
          _field('Till number', _tillController,
              Icons.store_rounded,
              hint: 'e.g. 123456',
              keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          _paymentNote(
              'Bank pays to your M-Pesa till (Buy Goods) number. Works with Equity, KCB, Co-op and most major banks.'),
        ] else ...[
          _field('Paybill number', _paybillController,
              Icons.account_balance_outlined,
              hint: 'e.g. 400200',
              keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _field('Account number', _paybillAccountController,
              Icons.tag_rounded,
              hint: 'Your account/business number'),
          const SizedBox(height: 8),
          _paymentNote(
              'Bank pays to your paybill. Use this if your business has a dedicated M-Pesa paybill.'),
        ],
      ],
    );
  }

  Widget _paymentTab(String method, IconData icon, String label) {
    final selected = _paymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMethod = method),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.orange
                : AppColors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.orange
                  : AppColors.white.withValues(alpha: 0.1),
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? AppColors.white : AppColors.gray400,
                  size: 18),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    color:
                        selected ? AppColors.white : AppColors.gray400,
                    fontSize: 11,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentNote(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.orange, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.orange,
                      height: 1.4,
                      fontSize: 11,
                    )),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.white,
              fontWeight: FontWeight.w600,
            ));
  }

  Widget _productRow(
    String size,
    TextEditingController controller, {
    required bool available,
    required ValueChanged<bool> onToggle,
    String? label,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: available
              ? AppColors.orange.withValues(alpha: 0.3)
              : AppColors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => onToggle(!available),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: available
                    ? AppColors.orange
                    : AppColors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: available
                      ? AppColors.orange
                      : AppColors.white.withValues(alpha: 0.2),
                ),
              ),
              child: Center(
                child: Text(
                  size,
                  style: TextStyle(
                    color: available
                        ? AppColors.white
                        : AppColors.gray600,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label ?? '$size cylinder',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: available
                            ? AppColors.white
                            : AppColors.gray600,
                        fontSize: 13,
                      ),
                ),
                Text(
                  available ? 'Available' : 'Not offered',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: available
                            ? AppColors.success
                            : AppColors.gray600,
                        fontSize: 11,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: controller,
              enabled: available,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d+\.?\d{0,2}')),
              ],
              style: TextStyle(
                color: available ? AppColors.white : AppColors.gray600,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                prefixText: 'KES ',
                prefixStyle: TextStyle(
                  color:
                      available ? AppColors.orange : AppColors.gray600,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                hintText: '0',
                hintStyle: const TextStyle(color: AppColors.gray600),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: AppColors.white.withValues(alpha: 0.2)),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: AppColors.white.withValues(alpha: 0.05)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.orange),
                ),
                filled: true,
                fillColor: AppColors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    String? hint,
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
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.gray600),
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
