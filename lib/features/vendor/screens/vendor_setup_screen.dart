import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire_plus/geoflutterfire_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mobigas/core/services/storage_metadata.dart';
import 'package:geocoding/geocoding.dart';
import 'package:mobigas/core/services/device_fingerprint_service.dart';
import 'package:mobigas/core/theme/app_theme.dart';
import 'package:mobigas/core/services/firebase_service.dart';
import 'package:mobigas/core/services/firestore_service.dart';
import 'package:mobigas/core/services/location_service.dart';
import 'package:mobigas/core/models/app_models.dart';
import 'package:mobigas/core/widgets/location_picker_widget.dart';
import 'package:mobigas/core/services/geo_service.dart';
import 'package:mobigas/core/config/currency.dart';
import 'package:mobigas/core/config/mobile_money.dart';
import 'package:mobigas/core/config/vendor_requirements.dart';
//import 'package:mobigas/features/vendor/widgets/country_confirmation.dart';

/// Which part of the vendor profile this screen instance edits.
/// fullOnboarding is the original 4-step wizard, used only for a
/// brand-new vendor who has nothing set up yet. Every other mode is a
/// single-purpose screen — a vendor tweaking their gas prices
/// shouldn't have to click through business details, location, and
/// documents to get there, and vice versa.
enum VendorEditMode {
  fullOnboarding,
  businessOnly,
  locationOnly,
  pricesOnly,
  documentsOnly,
}

class VendorSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? existingData;
  final VendorEditMode mode;
  const VendorSetupScreen({
    super.key,
    this.existingData,
    this.mode = VendorEditMode.fullOnboarding,
  });

  @override
  State<VendorSetupScreen> createState() => _VendorSetupScreenState();
}

class _VendorSetupScreenState extends State<VendorSetupScreen> {
  int _step = 0; // 0=business, 1=location, 2=gas products, 3=verification docs
  bool _isSaving = false;

  // Business type
  String _businessType = 'sole'; // sole, registered, petrol_station
  File? _certificateFile;
  bool _isUploadingCert = false; // ignore: prefer_final_fields

  // Step 3 - Verification documents (EPRA compliance) — new files picked
  // this session, keyed by the Firestore field they'll be saved to.
  // A null value means "no change this session"; the save step falls
  // back to whatever URL already exists rather than wiping it.
  final Map<String, File?> _docFiles = {
    'epraCertificateUrl': null,
    'subDealerAuthorizationUrl': null,
    'businessRegistrationUrl': null,
    'brandAuthorizationUrl': null,
    'dealerAssociationLetterUrl': null,
    'businessPermitUrl': null,
    'fireCertificateUrl': null,
    'weighingScaleCertUrl': null,
    'weighingScalePhotoUrl': null,
    'premisesPhotoUrl': null,
    // TZ requires a TRA tax clearance; other countries ignore this key.
    'taxClearanceUrl': null,
  };

  // Either/or toggles — true means "show the ideal document's upload
  // slot", false means "show the fallback's upload slot instead".
  // Defaulted in initState based on whichever the vendor already has.
  late bool _hasScaleCert;
  late bool _hasBrandAuth;
  // TZ/UG require the vendor to acknowledge the no-decanting rule. Kenya has
  // no such tick, so it defaults true (nothing to confirm).
  bool _ackNoDecanting = false;

  // Step 1 - Business
  late TextEditingController _businessNameController;
  late TextEditingController _ownerNameController;
  late TextEditingController _idOrBrnController; // National ID or BRN
  // The vendor's CONTACT number (Step 0) — the line a customer calls
  // about a delivery. Doubles as the payout number for phone-based
  // rails unless _payoutPhoneController is set (see below).
  late TextEditingController _phoneController;
  // Optional override: the number payments go to, when it isn't the
  // contact line. Empty means "same as contact" — which is what every
  // vendor saved before this field existed, so their `phone` (which
  // WAS their payout number) keeps paying out unchanged.
  late TextEditingController _payoutPhoneController;
  late bool _useSeparatePayoutPhone;
  late TextEditingController _deliveryTimeController;
  late TextEditingController _referralCodeController;
  String _paymentMethod = 'mpesa'; // mpesa, till, paybill, mtn, airtel, tigo
  late TextEditingController _tillController;
  late TextEditingController _paybillController;
  late TextEditingController _paybillAccountController;

  // Step 3 - Gas products & prices.
  // Refill and Full Kit prices are BRAND-scoped — different brands
  // genuinely cost different amounts at the same size (Total 6kg vs
  // a budget brand's 6kg). Keyed by composite '$brand|$size', created
  // lazily as the vendor selects brands and switches between them —
  // see _refillController/_fullKitController helpers below.
  final Map<String, TextEditingController> _priceControllers = {};
  final Map<String, bool> _sizeAvailable = {};
  // Full kit prices (gas + new cylinder)
  final Map<String, TextEditingController> _fullKitPriceControllers = {};
  final Map<String, bool> _fullKitAvailable = {};

  /// Which brand's prices are currently shown/edited in the Refill
  /// and Full Kit sections. Defaults to the first selected brand;
  /// the chip selector to change this only appears once 2+ brands
  /// are selected — a single-brand vendor never sees it at all.
  String _activePricingBrand = '';

  static const List<String> _refillFullKitSizes = [
    '3kg',
    '6kg',
    '13kg',
    '22.5kg',
    '50kg',
  ];

  TextEditingController _refillController(String brand, String size) {
    return _priceControllers.putIfAbsent(
      '$brand|$size',
      () => TextEditingController(),
    );
  }

  bool _refillIsAvailable(String brand, String size) =>
      _sizeAvailable['$brand|$size'] ?? false;

  TextEditingController _fullKitController(String brand, String size) {
    return _fullKitPriceControllers.putIfAbsent(
      '$brand|$size',
      () => TextEditingController(),
    );
  }

  bool _fullKitIsAvailable(String brand, String size) =>
      _fullKitAvailable['$brand|$size'] ?? false;

  // Grill kit (6kg only: gas + cylinder + burner + grill) — brand-
  // scoped like refill/fullKit since the gas brand affects the price.
  // Keyed by brand alone (size is always 6kg).
  final Map<String, TextEditingController> _grillKitPriceControllers = {};
  final Map<String, bool> _grillKitAvailable = {};

  TextEditingController _grillKitController(String brand) {
    return _grillKitPriceControllers.putIfAbsent(
      brand,
      () => TextEditingController(),
    );
  }

  bool _grillKitIsAvailable(String brand) => _grillKitAvailable[brand] ?? false;
  // Burner — fits 3kg or 6kg cylinders only, no gas included
  final Map<String, TextEditingController> _burnerPriceControllers = {
    '3kg': TextEditingController(),
    '6kg': TextEditingController(),
  };
  final Map<String, bool> _burnerAvailable = {'3kg': false, '6kg': false};
  // Regulator — fits 13kg cylinders only, no gas included
  final TextEditingController _regulatorPriceController =
      TextEditingController();
  bool _regulatorAvailable = false;
  // Meko + cooker set — flat product, not tied to a cylinder size
  final TextEditingController _mekoCookerPriceController =
      TextEditingController();
  bool _mekoCookerAvailable = false;

  // Step 2 - Location (Google Places, or GPS auto-detect)
  String _selectedAddress = '';
  double _selectedLat = 0.0;
  double _selectedLng = 0.0;
  // Country decided offline from the GPS pin (GeoService), not the phone
  // number. Drives which regulator's documents Step 3 asks for. Null until a
  // pin is set, or if the pin falls outside every supported market.
  String? _detectedCountry;
  // Whether the location picker is actively showing (vs. the saved
  // summary view). Starts true only when there's nothing saved yet.
  late bool _isEditingLocation;
  bool _isDetectingLocation = false;
  final List<String> _availableBrands = List<String>.from(KenyanGasBrands.all);
  final List<String> _selectedBrands = [];
  final TextEditingController _customBrandController = TextEditingController();

  // EPRA certificate either/or: own certificate, or a sub-dealer /
  // agent authorization from an already-licensed parent vendor.
  late bool _hasOwnEpra;
  late TextEditingController _parentVendorNameController;
  late TextEditingController _parentEpraNumberController;

  @override
  void initState() {
    super.initState();
    final d = widget.existingData ?? {};
    _businessType = d['businessType'] ?? 'sole';
    // Default to the "ideal document" side unless they've already
    // gone down the fallback path — then keep them there so their
    // existing upload stays visible instead of appearing to vanish.
    _hasScaleCert = (d['weighingScalePhotoUrl'] ?? '').toString().isEmpty;
    _hasBrandAuth = (d['dealerAssociationLetterUrl'] ?? '').toString().isEmpty;
    _hasOwnEpra = (d['subDealerAuthorizationUrl'] ?? '').toString().isEmpty;
    _ackNoDecanting = (d['ackNoDecanting'] ?? false) == true;
    // BUG FIX: these three were never restored from existing data,
    // so re-opening setup to edit ANYTHING silently started the
    // location step blank — failing its own validation unless the
    // vendor re-picked their address from scratch every single time.
    _selectedAddress = d['address'] ?? '';
    _selectedLat = (d['latitude'] ?? 0.0).toDouble();
    _selectedLng = (d['longitude'] ?? 0.0).toDouble();
    _detectedCountry = d['country'] as String? ??
        (_selectedLat != 0.0
            ? GeoService.countryFromLatLng(_selectedLat, _selectedLng)
            : null);
    // Location is "set once" — only show the picker if there's
    // nothing saved yet. An existing address shows as a summary with
    // an explicit Edit action instead of re-prompting every time.
    _isEditingLocation = _selectedAddress.isEmpty;
    _parentVendorNameController = TextEditingController(
      text: d['parentVendorName'] ?? '',
    );
    _parentEpraNumberController = TextEditingController(
      text: d['parentEpraNumber'] ?? '',
    );
    _businessNameController = TextEditingController(
      text: d['businessName'] ?? '',
    );
    _ownerNameController = TextEditingController(text: d['ownerName'] ?? '');
    _idOrBrnController = TextEditingController(
      text: d['nationalId'] ?? d['businessRegNumber'] ?? '',
    );
    _phoneController = TextEditingController(text: d['phone'] ?? '');
    // A saved payoutPhone means the vendor explicitly split the two
    // lines; empty (the case for every doc written before this field
    // existed) means payments follow the contact number.
    _payoutPhoneController = TextEditingController(
      text: d['payoutPhone'] ?? '',
    );
    _useSeparatePayoutPhone =
        (d['payoutPhone'] ?? '').toString().trim().isNotEmpty;
    _deliveryTimeController = TextEditingController(
      text: d['deliveryTime'] ?? '20–40 min',
    );
    _referralCodeController = TextEditingController(
      text: d['referredByCode'] ?? '',
    );
    _tillController = TextEditingController(text: d['tillNumber'] ?? '');
    _paybillController = TextEditingController(text: d['paybillNumber'] ?? '');
    _paybillAccountController = TextEditingController(
      text: d['paybillAccount'] ?? '',
    );
    // Default to the country's primary provider (KE -> M-Pesa, UG ->
    // MTN Mobile Money, TZ -> M-Pesa) rather than hardcoding 'mpesa'
    // — Uganda has no 'mpesa' option at all.
    _paymentMethod = d['paymentMethod'] ??
        MobileMoney.providersFor(_detectedCountry).first.code;

    // Brands must load BEFORE listings — legacy listings saved before
    // brand-aware pricing existed have no 'brand' field at all, and
    // need a fallback to attach to (see below). Loading brands first
    // means that fallback is actually available when the listings
    // loop runs.
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
    if (_selectedBrands.isNotEmpty) {
      _activePricingBrand = _selectedBrands.first;
    }

    // Load existing listings
    final listings = d['listings'] as List? ?? [];
    for (final l in listings) {
      final size = l['size'] as String?;
      final productType = l['productType'] as String? ?? 'refill';
      final price = (l['price'] ?? 0).toString();
      final available = l['available'] as bool? ?? false;
      // BUG FIX: listings saved before brand-aware pricing existed
      // have no 'brand' field at all. Falling back to '' created a
      // '|size' key that no brand chip ever points at — the price
      // was technically saved but silently orphaned, and because
      // GasListing.brand stayed empty, the customer app's brand-step
      // logic (which only appears when it finds a non-empty brand)
      // skipped straight to the vendor list, exactly as reported.
      // Falling back to the vendor's first selected brand instead
      // means reopening and resaving this screen actually repairs
      // the vendor's existing data.
      final rawBrand = (l['brand'] as String? ?? '').trim();
      final brand = rawBrand.isNotEmpty
          ? rawBrand
          : (_selectedBrands.isNotEmpty ? _selectedBrands.first : rawBrand);

      if (size == null) continue;

      if (productType == 'refill') {
        _refillController(brand, size).text = price;
        _sizeAvailable['$brand|$size'] = available;
      } else if (productType == 'fullKit') {
        _fullKitController(brand, size).text = price;
        _fullKitAvailable['$brand|$size'] = available;
      } else if (productType == 'grillKit') {
        _grillKitController(brand).text = price;
        _grillKitAvailable[brand] = available;
      } else if (productType == 'burner' &&
          _burnerPriceControllers.containsKey(size)) {
        _burnerPriceControllers[size]!.text = price;
        _burnerAvailable[size] = available;
      } else if (productType == 'regulator') {
        _regulatorPriceController.text = price;
        _regulatorAvailable = available;
      } else if (productType == 'mekoCooker') {
        _mekoCookerPriceController.text = price;
        _mekoCookerAvailable = available;
      }
    }
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _ownerNameController.dispose();
    _idOrBrnController.dispose();
    _phoneController.dispose();
    _payoutPhoneController.dispose();
    _deliveryTimeController.dispose();
    _tillController.dispose();
    _paybillController.dispose();
    _paybillAccountController.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    for (final c in _fullKitPriceControllers.values) {
      c.dispose();
    }
    for (final c in _grillKitPriceControllers.values) {
      c.dispose();
    }
    for (final c in _burnerPriceControllers.values) {
      c.dispose();
    }
    _regulatorPriceController.dispose();
    _mekoCookerPriceController.dispose();
    _customBrandController.dispose();
    _parentVendorNameController.dispose();
    _parentEpraNumberController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  String get _vendorId => FirebaseAuth.instance.currentUser?.uid ?? '';

  /// The number a phone-based rail actually pays out to: the override
  /// when the vendor set one, otherwise their contact line. Till and
  /// Paybill don't use this at all — their destination is the till /
  /// paybill number.
  String get _effectivePayoutPhone => _useSeparatePayoutPhone
      ? _payoutPhoneController.text.trim()
      : _phoneController.text.trim();

  bool get _step0Valid {
    if (_businessNameController.text.trim().isEmpty) {
      return false;
    }
    if (_ownerNameController.text.trim().isEmpty) {
      return false;
    }
    if (_idOrBrnController.text.trim().isEmpty) {
      return false;
    }
    // A contact number is required of EVERY vendor now, whatever rail
    // they're paid on. Previously `phone` was only ever collected as
    // part of the M-Pesa/MTN/Airtel payment field, so a Till or
    // Paybill vendor finished setup with no number at all — nothing
    // for a customer to call about a delivery.
    if (_phoneController.text.trim().length < 9) {
      return false;
    }
    return true;
  }

  /// Payment method can only be validated once the vendor's country
  /// is known (Step 1, location) — different countries offer
  /// different providers (KE: M-Pesa/Till/Paybill, UG: MTN/Airtel,
  /// TZ: M-Pesa/Tigo/Airtel), so this can't live in _step0Valid.
  bool get _paymentMethodValid {
    if (_detectedCountry == null) return false;
    final provider =
        MobileMoney.providerByCode(_detectedCountry, _paymentMethod);
    switch (provider.code) {
      case 'till':
        return _tillController.text.trim().isNotEmpty;
      case 'paybill':
        return _paybillController.text.trim().isNotEmpty &&
            _paybillAccountController.text.trim().isNotEmpty;
      default:
        // Normally already guaranteed by _step0Valid's contact check
        // — but not in locationOnly mode, where Step 0 isn't shown.
        // A vendor there whose saved contact number is blank (legacy)
        // can still satisfy this by ticking "a different number".
        return _effectivePayoutPhone.length >= 9;
    }
  }

  bool get _step1Valid =>
      _selectedAddress.isNotEmpty &&
      _selectedLat != 0.0 &&
      _detectedCountry != null &&
      _paymentMethodValid;

  bool get _step2Valid =>
      _selectedBrands.isNotEmpty &&
      _priceControllers.entries.any(
        (e) => _sizeAvailable[e.key] == true && e.value.text.isNotEmpty,
      );

  /// Called whenever _detectedCountry changes (location picked or
  /// edited) — if the vendor's current payment method isn't offered
  /// in the new country (e.g. they had 'till' selected and their pin
  /// moved from Kenya to Uganda), reset to that country's primary
  /// provider rather than leaving a stale, invalid selection.
  void _ensurePaymentMethodValidForCountry() {
    final validCodes =
        MobileMoney.providersFor(_detectedCountry).map((p) => p.code).toSet();
    if (!validCodes.contains(_paymentMethod)) {
      _paymentMethod = MobileMoney.providersFor(_detectedCountry).first.code;
    }
  }

  /// Parses the numeric kg value out of a size string like "3kg",
  /// "13kg", or "22.5kg" — replaces a hardcoded 3-way ternary that
  /// silently mislabeled anything beyond 3/6/13kg as 13kg. Used only
  /// for sort ordering / display, so rounding a fractional size
  /// (22.5 -> 23) is fine — the actual size STRING shown to
  /// customers and matched everywhere else stays exact.
  int _kgFromSize(String size) {
    final match = RegExp(r'[\d.]+').firstMatch(size);
    if (match == null) return 0;
    return (double.tryParse(match.group(0)!) ?? 0).round();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);

    if (_selectedLat == 0.0 && _selectedLng == 0.0) {
      setState(() => _isSaving = false);
      _showFocusedError('Please set your business location first');
      return;
    }

    // TZ/UG legally prohibit decanting; the vendor must acknowledge it.
    if (VendorRequirements.forCountry(_detectedCountry).acknowledgment != null &&
        !_ackNoDecanting) {
      setState(() => _isSaving = false);
      _showFocusedError(
          'Please confirm you understand the no-decanting rule to continue');
      return;
    }

    try {
      final isNewVendor = widget.existingData == null;

      // Business certificate / ID (Step 0). Preserve the existing URL
      // by default — only overwrite it if a new file was picked this
      // session. Previously this silently wrote null (wiping the
      // upload) on every edit that didn't re-pick a file.
      String? certificateUrl =
          widget.existingData?['certificateUrl'] as String?;
      if (_certificateFile != null) {
        setState(() => _isUploadingCert = true);
        final ref = FirebaseStorage.instance
            .ref()
            .child('business_certificates')
            .child(_vendorId);
        await ref.putFile(_certificateFile!, imageMetadata(_certificateFile!));
        certificateUrl = await ref.getDownloadURL();
        setState(() => _isUploadingCert = false);
      }

      // Verification documents (Step 3) — same preserve-unless-replaced
      // rule. Uploading a NEW document here means something changed
      // and MobiGas needs to re-review, so it also resets isVerified.
      final docUrls = <String, String>{};
      var anyNewVerificationDoc = false;
      for (final key in _docFiles.keys) {
        final file = _docFiles[key];
        if (file != null) {
          anyNewVerificationDoc = true;
          final ref = FirebaseStorage.instance
              .ref()
              .child('vendor_documents')
              .child(_vendorId)
              .child(key);
          await ref.putFile(file, imageMetadata(file));
          docUrls[key] = await ref.getDownloadURL();
        } else {
          docUrls[key] = (widget.existingData?[key] as String?) ?? '';
        }
      }

      final listings = <Map<String, dynamic>>[];
      // Refills — key is composite 'brand|size'. Skip entries that
      // were only lazily created (e.g. a brand tab the vendor
      // glanced at but never priced) — empty text AND never toggled
      // available means nothing was actually entered.
      for (final e in _priceControllers.entries) {
        final parts = e.key.split('|');
        if (parts.length != 2) continue;
        final brand = parts[0];
        final size = parts[1];
        final available = _sizeAvailable[e.key] ?? false;
        if (!available && e.value.text.trim().isEmpty) continue;
        listings.add({
          'size': size,
          'kg': _kgFromSize(size),
          'price': double.tryParse(e.value.text) ?? 0.0,
          'available': available,
          'productType': 'refill',
          'brand': brand,
        });
      }
      // Full kits — same composite-key pattern.
      for (final e in _fullKitPriceControllers.entries) {
        final parts = e.key.split('|');
        if (parts.length != 2) continue;
        final brand = parts[0];
        final size = parts[1];
        if (_fullKitAvailable[e.key] == true) {
          listings.add({
            'size': size,
            'kg': _kgFromSize(size),
            'price': double.tryParse(e.value.text) ?? 0.0,
            'available': true,
            'productType': 'fullKit',
            'brand': brand,
          });
        }
      }
      // Grill kit — 6kg only, brand-scoped
      for (final e in _grillKitPriceControllers.entries) {
        if (_grillKitAvailable[e.key] == true) {
          listings.add({
            'size': '6kg',
            'kg': 6,
            'price': double.tryParse(e.value.text) ?? 0.0,
            'available': true,
            'productType': 'grillKit',
            'brand': e.key,
          });
        }
      }
      // Burner — 3kg or 6kg only, no gas
      for (final e in _burnerPriceControllers.entries) {
        if (_burnerAvailable[e.key] == true) {
          listings.add({
            'size': e.key,
            'kg': e.key == '3kg' ? 3 : 6,
            'price': double.tryParse(e.value.text) ?? 0.0,
            'available': true,
            'productType': 'burner',
          });
        }
      }
      // Regulator — 13kg only, no gas
      if (_regulatorAvailable) {
        listings.add({
          'size': '13kg',
          'kg': 13,
          'price': double.tryParse(_regulatorPriceController.text) ?? 0.0,
          'available': true,
          'productType': 'regulator',
        });
      }
      // Meko + Cooker — flat product, not tied to a cylinder size
      if (_mekoCookerAvailable) {
        listings.add({
          'size': 'Standard',
          'kg': 0,
          'price': double.tryParse(_mekoCookerPriceController.text) ?? 0.0,
          'available': true,
          'productType': 'mekoCooker',
        });
      }

      await FirebaseService.vendors.doc(_vendorId).set({
        'businessName': _businessNameController.text.trim(),
        'ownerName': _ownerNameController.text.trim(),
        'email': FirebaseAuth.instance.currentUser?.email,
        'businessType': _businessType,
        if (_businessType == 'sole')
          'nationalId': _idOrBrnController.text.trim()
        else
          'businessRegNumber': _idOrBrnController.text.trim(),
        // Contact line — what a customer calls. Also the payout
        // destination for phone rails, unless payoutPhone overrides it.
        'phone': _phoneController.text.trim(),
        // Empty means "payments come to the contact number". Written
        // explicitly (rather than omitted) so unticking the box
        // actually clears a previously-set override.
        'payoutPhone':
            _useSeparatePayoutPhone ? _payoutPhoneController.text.trim() : '',
        'paymentMethod': _paymentMethod,
        'tillNumber': _tillController.text.trim(),
        'paybillNumber': _paybillController.text.trim(),
        'paybillAccount': _paybillAccountController.text.trim(),
        'address': _selectedAddress,
        'latitude': _selectedLat,
        'longitude': _selectedLng,
        // Decided offline from the pin at onboarding. A vendor doesn't change
        // country by editing their profile; defaults to KE for legacy docs.
        'country': _detectedCountry ?? 'KE',
        // Geohash + geopoint for radius queries (geoflutterfire_plus).
        // Written on every save so an edited location stays queryable.
        'geo': GeoFirePoint(GeoPoint(_selectedLat, _selectedLng)).data,
        'brands': _selectedBrands,
        'customBrands': _selectedBrands
            .where((b) => !KenyanGasBrands.all.contains(b))
            .toList(),
        'listings': listings,
        'deliveryTime': _deliveryTimeController.text.trim().isNotEmpty
            ? _deliveryTimeController.text.trim()
            : '20–40 min',
        'updatedAt': FieldValue.serverTimestamp(),
        'certificateUrl': certificateUrl,
        'epraCertificateUrl': docUrls['epraCertificateUrl'],
        'subDealerAuthorizationUrl': docUrls['subDealerAuthorizationUrl'],
        'parentVendorName': _parentVendorNameController.text.trim(),
        'parentEpraNumber': _parentEpraNumberController.text.trim(),
        'brandAuthorizationUrl': docUrls['brandAuthorizationUrl'],
        'dealerAssociationLetterUrl': docUrls['dealerAssociationLetterUrl'],
        'businessPermitUrl': docUrls['businessPermitUrl'],
        'businessRegistrationUrl': docUrls['businessRegistrationUrl'],
        // TZ tax clearance (null/absent for other countries).
        'taxClearanceUrl': docUrls['taxClearanceUrl'],
        // No-decanting acknowledgment (TZ/UG). True for KE by convention.
        'ackNoDecanting': _ackNoDecanting,
        'fireCertificateUrl': docUrls['fireCertificateUrl'],
        'weighingScaleCertUrl': docUrls['weighingScaleCertUrl'],
        'weighingScalePhotoUrl': docUrls['weighingScalePhotoUrl'],
        'premisesPhotoUrl': docUrls['premisesPhotoUrl'],
        'createdAt': isNewVendor
            ? FieldValue.serverTimestamp()
            : widget.existingData!['createdAt'],
        // These fields represent accumulated or admin-controlled state
        // (verification decision, live/offline status, rating history).
        // They are ONLY defaulted on first creation. On every later
        // edit they are omitted entirely so the merge leaves whatever
        // is already in Firestore untouched — previously this block
        // unconditionally reset all four on every single save, so a
        // verified, online vendor with real reviews would silently
        // lose their badge, go offline, and have their rating wiped
        // just by updating a gas price.
        if (isNewVendor) ...{
          'isVerified': false,
          'isOnline': false,
          'rating': 0.0,
          'totalReviews': 0,
        },
        // A brand-new verification document invalidates any prior
        // approval — force MobiGas to re-review it.
        if (!isNewVendor && anyNewVerificationDoc) ...{
          'isVerified': false,
          'verifiedAt': null,
          'verifiedBy': null,
        },
      }, SetOptions(merge: true));

      // Only on first creation, and only if a code was actually
      // entered — referredByCode is permanent, never re-processed on
      // later edits.
      final referralCode = _referralCodeController.text.trim();
      if (isNewVendor && referralCode.isNotEmpty) {
        try {
          await FirestoreService.recordReferralSignup(
            code: referralCode,
            referredType: 'vendor',
            // GAP CLOSED: previously missing. Turns out the vendor's
            // Google Sign-In flow (google_auth_service.dart) never
            // creates the Firestore profile or touches referrals at
            // all — it only handles Firebase Auth, then always routes
            // to /vendor-home regardless of whether setup is done
            // ("setup happens inside the dashboard"). This IS where
            // the vendor's profile actually gets created, so this is
            // the right place for it — same DeviceFingerprintService
            // the customer app already uses.
            deviceFingerprint: await DeviceFingerprintService.getFingerprint(),
          );
        } catch (_) {
          // Invalid/unknown code — don't block the vendor's setup
          // over it, just silently skip linking a referral.
        }
      }

      if (mounted) {
        if (widget.mode == VendorEditMode.fullOnboarding) {
          // Onboarding wizard — finishing step 3 means "I'm done", so exit.
          Navigator.pop(context, true);
        } else {
          // Focused single-purpose screens (e.g. pricesOnly) — saving
          // shouldn't kick the vendor out. Let them keep switching
          // brands and adjusting more prices; they leave via the X
          // button whenever they're actually done.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saved'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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
    if (widget.mode != VendorEditMode.fullOnboarding) {
      return _buildFocusedScaffold();
    }
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
                    : _step == 2
                    ? _buildStep2()
                    : _buildStep3(),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// Single-purpose screen for businessOnly/locationOnly/pricesOnly/
  /// documentsOnly — no step indicator, no forced walk through
  /// unrelated sections, a direct Save button. Reuses the exact same
  /// _buildStepN() content and _save() logic as the full wizard, so
  /// there's only one source of truth for what each section contains.
  Widget _buildFocusedScaffold() {
    final title = switch (widget.mode) {
      VendorEditMode.businessOnly => 'Edit business details',
      VendorEditMode.locationOnly => 'Edit location',
      VendorEditMode.pricesOnly => 'Edit gas prices & products',
      VendorEditMode.documentsOnly => 'Verification documents',
      VendorEditMode.fullOnboarding => '',
    };
    final content = switch (widget.mode) {
      VendorEditMode.businessOnly => _buildStep0(),
      VendorEditMode.locationOnly => _buildStep1(),
      VendorEditMode.pricesOnly => _buildStep2(),
      VendorEditMode.documentsOnly => _buildStep3(),
      VendorEditMode.fullOnboarding => const SizedBox.shrink(),
    };

    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),

                    child: const Icon(
                      Icons.close_rounded,
                      color: AppColors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: AppColors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: content,
              ),
            ),
            _buildFocusedFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusedFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.navy,
        border: Border(
          top: BorderSide(color: AppColors.white.withValues(alpha: 0.1)),
        ),
      ),
      child: ElevatedButton(
        onPressed: _isSaving
            ? null
            : () {
                // Validate only the section actually being edited —
                // sections not shown in this mode keep whatever was
                // already loaded from existingData, untouched.
                if (widget.mode == VendorEditMode.businessOnly &&
                    !_step0Valid) {
                  _showFocusedError('Please fill in all business details');
                  return;
                }
                if (widget.mode == VendorEditMode.locationOnly &&
                    !_step1Valid) {
                  _showFocusedError(
                    'Please set your business location and payment details',
                  );
                  return;
                }
                if (widget.mode == VendorEditMode.pricesOnly && !_step2Valid) {
                  _showFocusedError(
                    'Select at least one brand and set a price',
                  );
                  return;
                }
                // documentsOnly has no hard gate — same as onboarding.
                _save();
              },
        child: _isSaving
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.white,
                ),
              )
            : const Text('Save changes'),
      ),
    );
  }

  void _showFocusedError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildHeader() {
    final titles = [
      'Business details',
      'Your location',
      'Gas products & prices',
      'Verification documents',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.close_rounded,
              color: AppColors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titles[_step],
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: AppColors.white),
                ),
                Text(
                  'Step ${_step + 1} of 4',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.gray400),
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
        children: List.generate(4, (i) {
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
                if (i < 3) const SizedBox(width: 4),
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
        Text(
          'Business type',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _bizTypeTab(
              'sole',
              Icons.person_outline_rounded,
              'Sole Proprietor',
            ),
            const SizedBox(width: 8),
            _bizTypeTab(
              'registered',
              Icons.business_outlined,
              'Registered Biz',
            ),
            const SizedBox(width: 8),
            _bizTypeTab(
              'petrol_station',
              Icons.local_gas_station_outlined,
              'Petrol Station',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _field(
          'Business name',
          _businessNameController,
          Icons.store_outlined,
          hint: _businessType == 'sole'
              ? 'e.g. Kamau Gas Supplies'
              : _businessType == 'registered'
              ? 'e.g. Kamau Gas Ltd'
              : 'e.g. Total Mirema Station',
        ),
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
        // Contact number — asked of every vendor, on every rail. This
        // used to be collected only as part of the M-Pesa/MTN/Airtel
        // payment field in Step 1, so Till and Paybill vendors reached
        // the end of setup with no number a customer could call.
        _field(
          'Contact phone number',
          _phoneController,
          Icons.phone_outlined,
          hint: '0712 345 678',
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 6),
        Text(
          'The number customers call about a delivery. Payments come here '
          'too unless you set a different one in the next step.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 11,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _buildCertificateUpload(),
        const SizedBox(height: 16),
        _field(
          'Delivery time',
          _deliveryTimeController,
          Icons.access_time_rounded,
          hint: 'e.g. 20–40 min',
        ),
        const SizedBox(height: 16),
        _buildReferralCodeField(),
      ],
    );
  }

  // ── STEP 1: LOCATION ─────────────────────────────────────────────
  Widget _buildStep1() {
    // Location is set once. If we already have one and the vendor
    // hasn't tapped Edit, show a summary card instead of re-prompting
    // for location on every visit — this was previously forced every
    // time because the underlying state was never restored from the
    // saved data (fixed in initState), compounding the re-ask problem.
    if (_selectedAddress.isNotEmpty && !_isEditingLocation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Business location',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 13,
              color: AppColors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: AppColors.orange,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedAddress,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => setState(() => _isEditingLocation = true),
            icon: const Icon(Icons.edit_location_alt_rounded, size: 18),
            label: const Text('Edit location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.orange,
              side: const BorderSide(color: AppColors.orange),
            ),
          ),
          if (_detectedCountry != null) ...[
            const SizedBox(height: 20),
            _buildPaymentMethodSelector(),
          ],
        ],
      );
    }

    // No saved location yet, or the vendor tapped Edit — GPS
    // auto-detect is the primary path; manual search remains
    // available as a fallback, exactly as before.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business location',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Use your current location, or search for your address',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _isDetectingLocation ? null : _useCurrentLocation,
          icon: _isDetectingLocation
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : const Icon(Icons.my_location_rounded, size: 18),
          label: Text(
            _isDetectingLocation ? 'Detecting...' : 'Use my current location',
          ),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            backgroundColor: AppColors.success,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Divider(color: AppColors.white.withValues(alpha: 0.2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'OR TYPE MANUALLY',
                style: TextStyle(
                  color: AppColors.gray400,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Divider(color: AppColors.white.withValues(alpha: 0.2)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LocationPickerWidget(
          hint: 'e.g. Total Station, Mirema Drive, Nairobi...',
          darkMode: true,
          initialValue: _selectedAddress.isNotEmpty ? _selectedAddress : null,
          onSelected: (address, lat, lng) {
            setState(() {
              _selectedAddress = address;
              _selectedLat = lat;
              _selectedLng = lng;
              _detectedCountry = GeoService.countryFromLatLng(lat, lng);
              _ensurePaymentMethodValidForCountry();
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
              const Icon(
                Icons.location_on_rounded,
                color: AppColors.orange,
                size: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your exact location is shared with customers for accurate delivery matching.',
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
        if (widget.existingData?['address'] != null) ...[
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _isEditingLocation = false;
                _selectedAddress = widget.existingData!['address'] ?? '';
                _selectedLat = (widget.existingData!['latitude'] ?? 0.0)
                    .toDouble();
                _selectedLng = (widget.existingData!['longitude'] ?? 0.0)
                    .toDouble();
              }),
              child: Text('Cancel', style: TextStyle(color: AppColors.gray400)),
            ),
          ),
        ],
        if (_detectedCountry != null) ...[
          const SizedBox(height: 20),
          _buildPaymentMethodSelector(),
        ],
      ],
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isDetectingLocation = true);
    try {
      final pos = await LocationService.getCurrentPosition();
      String address =
          'Near ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      try {
        // geocoding v5.0.0 breaking change: placemarkFromCoordinates
        // is no longer a top-level function — it's a method on a
        // Geocoding instance.
        final geocoding = Geocoding();
        final placemarks = await geocoding.placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((s) => s != null && s.trim().isNotEmpty).toList();
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (_) {
        // Reverse geocoding failed (offline, no plus-code data, etc.)
        // — keep the coordinate-based fallback label above; the real
        // lat/lng is still accurate and that's what delivery actually
        // depends on.
      }
      if (!mounted) return;
      setState(() {
        _selectedAddress = address;
        _selectedLat = pos.latitude;
        _selectedLng = pos.longitude;
        _detectedCountry =
            GeoService.countryFromLatLng(pos.latitude, pos.longitude);
        _ensurePaymentMethodValidForCountry();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not get your location. Check location permissions, or type your address instead.',
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _isDetectingLocation = false);
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gas brands you stock',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
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
                  if (_activePricingBrand == brand) {
                    _activePricingBrand = _selectedBrands.isNotEmpty
                        ? _selectedBrands.first
                        : '';
                  }
                } else {
                  _selectedBrands.add(brand);
                  if (_activePricingBrand.isEmpty) {
                    _activePricingBrand = brand;
                  }
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
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
                    color: selected ? AppColors.white : AppColors.gray400,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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
                  prefixIcon: const Icon(
                    Icons.add_rounded,
                    color: AppColors.gray400,
                    size: 20,
                  ),
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
                    horizontal: 12,
                    vertical: 12,
                  ),
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
                    if (_activePricingBrand.isEmpty) {
                      _activePricingBrand = brand;
                    }
                    _customBrandController.clear();
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(60, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_selectedBrands.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.orange,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Select at least one brand above to set refill and full kit prices.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.gray400,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          )
        else ...[
          // Different brands genuinely cost different amounts at the
          // same size (e.g. Total 6kg vs a budget brand's 6kg) — this
          // only appears once 2+ brands are selected. A single-brand
          // vendor never sees it; their one brand is used silently.
          if (_selectedBrands.length > 1) ...[
            Text(
              'Setting refill & full kit prices for:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.gray400,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedBrands.map((brand) {
                final active = _activePricingBrand == brand;
                return GestureDetector(
                  onTap: () => setState(() => _activePricingBrand = brand),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.orange
                          : AppColors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? AppColors.orange
                            : AppColors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      brand,
                      style: TextStyle(
                        color: active ? AppColors.white : AppColors.gray400,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          _sectionHeader(
            'Gas Refill (Exchange empty cylinder) — $_activePricingBrand',
          ),
          const SizedBox(height: 4),
          Text(
            'Customer exchanges their empty cylinder for a filled one',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.gray400,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          ..._refillFullKitSizes.map(
            (size) => _productRow(
              size,
              _refillController(_activePricingBrand, size),
              available: _refillIsAvailable(_activePricingBrand, size),
              onToggle: (v) => setState(
                () => _sizeAvailable['$_activePricingBrand|$size'] = v,
              ),
              label: '$size cylinder',
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader(
            'Full Cylinder Kit (Gas + New Cylinder) — $_activePricingBrand',
          ),
          const SizedBox(height: 4),
          Text(
            'Customer gets a brand new cylinder — no empty needed',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.gray400,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          ..._refillFullKitSizes.map(
            (size) => _productRow(
              size,
              _fullKitController(_activePricingBrand, size),
              available: _fullKitIsAvailable(_activePricingBrand, size),
              onToggle: (v) => setState(
                () => _fullKitAvailable['$_activePricingBrand|$size'] = v,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionHeader('Grill Kit — 6kg only — $_activePricingBrand'),
          const SizedBox(height: 4),
          Text(
            'Gas + Cylinder + LPG Burner + Grill — complete package',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.gray400,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _productRow(
            '6kg',
            _grillKitController(_activePricingBrand),
            available: _grillKitIsAvailable(_activePricingBrand),
            onToggle: (v) =>
                setState(() => _grillKitAvailable[_activePricingBrand] = v),
            label: 'Grill Kit (6kg)',
          ),
        ],
        const SizedBox(height: 24),
        _sectionHeader('Burner — fits 3kg or 6kg cylinders'),
        const SizedBox(height: 4),
        Text(
          'Standalone burner sold on its own — no gas or cylinder included',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        ..._burnerPriceControllers.entries.map(
          (e) => _productRow(
            e.key,
            e.value,
            available: _burnerAvailable[e.key] ?? false,
            onToggle: (v) => setState(() => _burnerAvailable[e.key] = v),
            label: 'Burner (${e.key})',
          ),
        ),
        const SizedBox(height: 24),
        _sectionHeader('Regulator — fits 13kg cylinders'),
        const SizedBox(height: 4),
        Text(
          'Standalone regulator sold on its own — no gas or cylinder included',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        _productRow(
          '13kg',
          _regulatorPriceController,
          available: _regulatorAvailable,
          onToggle: (v) => setState(() => _regulatorAvailable = v),
          label: 'Regulator (13kg)',
        ),
        const SizedBox(height: 24),
        _sectionHeader('Meko + Cooker'),
        const SizedBox(height: 4),
        Text(
          'Meko + two burner cooker set sold on its own — gas, hosepipe + 6kg cylinder included',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        _productRow(
          'Standard',
          _mekoCookerPriceController,
          available: _mekoCookerAvailable,
          onToggle: (v) => setState(() => _mekoCookerAvailable = v),
          label: 'Meko + Cooker',
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.tips_and_updates_outlined,
                color: AppColors.orange,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap size to toggle. Customers pay you the price you set, directly on delivery.',
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

  // ── STEP 3: VERIFICATION DOCUMENTS ───────────────────────────────
  Widget _buildStep3() {
    // ONE source for every string and every document in this step.
    // Previously this read RegulatorText for the licence-tier wording and
    // VendorRequirements for the supporting docs — two files defining the
    // same nine strings, of which the screen happened to render the older,
    // vaguer set. RegulatorText is gone; this is all of it now.
    final req = VendorRequirements.forCountry(_detectedCountry);
    final isSole = _businessType == 'sole';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Get your verified badge',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Customers only see verified vendors. You can finish setup now and '
          'add these later, but you won\'t be able to go online until '
          'everything below is uploaded and approved by MobiGas.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        // ── Licence tier: own licence OR agent authorization ──────
        Text(
          req.licenceSectionTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _altToggleTab(
              label: req.ownLicenceToggle,
              selected: _hasOwnEpra,
              onTap: () => setState(() => _hasOwnEpra = true),
            ),
            const SizedBox(width: 8),
            _altToggleTab(
              label: req.agentToggle,
              selected: !_hasOwnEpra,
              onTap: () => setState(() => _hasOwnEpra = false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_hasOwnEpra)
          _buildVerificationDocUpload(
            docKey: 'epraCertificateUrl',
            title: req.ownLicenceTitle,
            description: req.ownLicenceDescription,
          )
        else ...[
          _buildVerificationDocUpload(
            docKey: 'subDealerAuthorizationUrl',
            title: req.agentAuthTitle,
            description: req.agentAuthDescription,
          ),
          const SizedBox(height: 12),
          _field(
            req.parentNameLabel,
            _parentVendorNameController,
            Icons.store_outlined,
            hint: 'e.g. Total Kenya Ltd, K-Gas main distributor',
          ),
          const SizedBox(height: 12),
          _field(
            req.parentLicenceNumberLabel,
            _parentEpraNumberController,
            Icons.badge_outlined,
            hint: 'If known — helps MobiGas verify faster',
          ),
        ],
        // ── Supporting docs, straight off the country's list ───────
        // Was: a hardcoded sole-proprietor block, a hardcoded
        // `if (_detectedCountry == 'TZ')` tax-clearance block, and three
        // firstWhere lookups for permit/fire/premises. That KE-shaped
        // sequence is why a Tanzanian vendor was asked for their BRELA
        // certificate under the title "From eCitizen / the Business
        // Registration Service" — the country's real titles were sitting
        // in supportingDocs, unread. Rendering the list itself means a new
        // market's documents appear here the moment they're added there,
        // and documentsSubmitted counts the same set (see
        // VendorRequirements.documentsSubmitted).
        for (final doc in req.supportingDocs)
          if (!doc.soleOnly || isSole) ...[
            const SizedBox(height: 16),
            _buildVerificationDocUpload(
              docKey: doc.key,
              title: doc.title,
              description: doc.description,
            ),
          ],
        const SizedBox(height: 20),
        // ── Weighing scale: certificate OR a photo of the scale ────
        Text(
          'Weighing scale',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _altToggleTab(
              label: 'I have a calibration certificate',
              selected: _hasScaleCert,
              onTap: () => setState(() => _hasScaleCert = true),
            ),
            const SizedBox(width: 8),
            _altToggleTab(
              label: "I don't have one",
              selected: !_hasScaleCert,
              onTap: () => setState(() => _hasScaleCert = false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Was hardcoded Kenyan wording + 'From ${reg.scaleAuthority}',
        // which read "From the relevant weights and measures authority"
        // in Tanzania — a placeholder, while the real answer (WMA, with
        // the 6/15/38kg detail) already existed in this country's config.
        if (_hasScaleCert)
          _buildVerificationDocUpload(
            docKey: 'weighingScaleCertUrl',
            title: req.scaleCertTitle,
            description: req.scaleCertDescription,
          )
        else
          _buildVerificationDocUpload(
            docKey: 'weighingScalePhotoUrl',
            title: req.scalePhotoTitle,
            description: req.scalePhotoDescription,
          ),
        const SizedBox(height: 20),
        // ── Brand authorization: brand letter OR association letter ─
        Text(
          'Brand authorization',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _altToggleTab(
              label: 'I have a brand authorization letter',
              selected: _hasBrandAuth,
              onTap: () => setState(() => _hasBrandAuth = true),
            ),
            const SizedBox(width: 8),
            _altToggleTab(
              label: "I don't have one",
              selected: !_hasBrandAuth,
              onTap: () => setState(() => _hasBrandAuth = false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_hasBrandAuth)
          _buildVerificationDocUpload(
            docKey: 'brandAuthorizationUrl',
            title: req.brandLetterTitle,
            description: req.brandLetterDescription,
          )
        else
          _buildVerificationDocUpload(
            docKey: 'dealerAssociationLetterUrl',
            title: req.brandAltTitle,
            description: req.brandAltDescription,
          ),
        // No-decanting acknowledgment — TZ & UG require it, KE doesn't.
        if (req.acknowledgment != null) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: () =>
                setState(() => _ackNoDecanting = !_ackNoDecanting),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _ackNoDecanting
                    ? AppColors.orange.withValues(alpha: 0.10)
                    : AppColors.gray800,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _ackNoDecanting
                      ? AppColors.orange
                      : AppColors.gray600,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _ackNoDecanting
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: _ackNoDecanting
                        ? AppColors.orange
                        : AppColors.gray400,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      req.acknowledgment!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.white,
                        height: 1.4,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.orange,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MobiGas reviews documents manually — you\'ll be notified once approved. Uploading a replacement document sends it back for re-review.',
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
  /// Small pill-style tab used for the two either/or document choices
  /// (weighing scale, brand authorization) — same visual language as
  /// the business-type tabs, sized for two-option rows.
  Widget _altToggleTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
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
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? AppColors.white : AppColors.gray400,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickVerificationDoc(String docKey) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (file != null) {
      setState(() => _docFiles[docKey] = File(file.path));
    }
  }

  Widget _buildVerificationDocUpload({
    required String docKey,
    required String title,
    required String description,
  }) {
    final newFile = _docFiles[docKey];
    final existingUrl = widget.existingData?[docKey] as String?;
    final hasDoc =
        newFile != null || (existingUrl != null && existingUrl.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickVerificationDoc(docKey),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasDoc
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasDoc
                    ? AppColors.success.withValues(alpha: 0.4)
                    : AppColors.white.withValues(alpha: 0.2),
                width: hasDoc ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasDoc
                      ? Icons.check_circle_rounded
                      : Icons.upload_file_rounded,
                  color: hasDoc ? AppColors.success : AppColors.gray400,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDoc
                            ? newFile != null
                                  ? 'Document selected ✓'
                                  : 'Document already uploaded ✓'
                            : 'Tap to upload document',
                        style: TextStyle(
                          color: hasDoc ? AppColors.success : AppColors.gray400,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        hasDoc ? 'Tap to replace' : 'JPG, PNG accepted',
                        style: const TextStyle(
                          color: AppColors.gray600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (newFile != null) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              newFile,
              height: 100,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.navy,
        border: Border(
          top: BorderSide(color: AppColors.white.withValues(alpha: 0.1)),
        ),
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
                    color: AppColors.white.withValues(alpha: 0.3),
                  ),
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
                        'Please fill in all business details, including a '
                        'contact phone number',
                      ),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (_step == 1 && !_step1Valid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please set your location and payment details',
                      ),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (_step == 2 && !_step2Valid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Select at least one brand and set a price',
                      ),
                      backgroundColor: AppColors.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                // Step 3 (verification docs) has no hard gate here —
                // a vendor can finish setup without them and upload
                // later; going online is what's actually blocked
                // until all five are approved (see vendor home screen).
                if (_step < 3) {
                  setState(() => _step++);
                } else {
                  _save();
                }
              },
              child: _isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.white,
                      ),
                    )
                  : Text(_step < 3 ? 'Continue' : 'Save profile'),
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
              Icon(
                icon,
                color: selected ? AppColors.white : AppColors.gray400,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppColors.white : AppColors.gray400,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
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

  Widget _buildReferralCodeField() {
    final alreadySet = (widget.existingData?['referredByCode'] ?? '')
        .toString()
        .isNotEmpty;
    if (alreadySet) {
      // Permanent once set — never editable again, matching the
      // model's referredByCode contract.
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.card_giftcard_rounded,
              color: AppColors.orange,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              'Referred by: ',
              style: const TextStyle(color: AppColors.gray400, fontSize: 13),
            ),
            Text(
              _referralCodeController.text,
              style: const TextStyle(
                color: AppColors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return _field(
      'Referral code (optional)',
      _referralCodeController,
      Icons.card_giftcard_rounded,
      hint: 'e.g. PAT-7F3K — enter once, can\'t be changed later',
    );
  }

  Widget _buildCertificateUpload() {
    final hasCert =
        _certificateFile != null ||
        (widget.existingData?['certificateUrl'] != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Business certificate / ID document',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _businessType == 'sole'
              ? 'Upload a photo of your National ID (front)'
              : 'Upload your Certificate of Incorporation or Business Registration',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.gray400,
            fontSize: 11,
          ),
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
                          color: AppColors.gray600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isUploadingCert)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.orange,
                    ),
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
    final providers = MobileMoney.providersFor(_detectedCountry);
    final selectedProvider =
        MobileMoney.providerByCode(_detectedCountry, _paymentMethod);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How do you want to receive payment?',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        // Payment method tabs — options depend on the vendor's
        // country (KE: M-Pesa/Till/Paybill, UG: MTN/Airtel, TZ:
        // M-Pesa/Tigo/Airtel).
        Row(
          children: [
            for (var i = 0; i < providers.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _paymentTab(providers[i]),
            ],
          ],
        ),
        const SizedBox(height: 14),
        // Fields based on selection — till/paybill are Kenya-specific
        // two-field setups; every other provider (M-Pesa, MTN,
        // Airtel, Tigo Pesa) pays out to a phone number, which
        // defaults to the contact number from Step 0.
        if (selectedProvider.code == 'till') ...[
          _field(
            'Till number',
            _tillController,
            Icons.store_rounded,
            hint: 'e.g. 123456',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          _paymentNote(selectedProvider.hint),
        ] else if (selectedProvider.code == 'paybill') ...[
          _field(
            'Paybill number',
            _paybillController,
            Icons.account_balance_outlined,
            hint: 'e.g. 400200',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          _field(
            'Account number',
            _paybillAccountController,
            Icons.tag_rounded,
            hint: 'Your account/business number',
          ),
          const SizedBox(height: 8),
          _paymentNote(selectedProvider.hint),
        ] else ...[
          _buildPayoutPhoneChoice(selectedProvider),
          const SizedBox(height: 8),
          _paymentNote(selectedProvider.hint),
        ],
      ],
    );
  }

  /// Phone-rail payout destination. One number is the common case — a
  /// vendor answers and gets paid on the same line — so the contact
  /// number from Step 0 is used by default and shown read-only here.
  /// A registered business or petrol station whose till/office line
  /// isn't the line payments land on ticks the box and enters the
  /// second number; that (and only that) writes `payoutPhone`.
  Widget _buildPayoutPhoneChoice(MobileMoneyProvider provider) {
    final contact = _phoneController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_useSeparatePayoutPhone)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.phone_outlined,
                  color: AppColors.orange,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${provider.label} payments come to',
                        style: const TextStyle(
                          color: AppColors.gray400,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // Blank only for a legacy vendor editing in
                        // locationOnly mode, where Step 0 isn't shown
                        // — the tick box below is their way out.
                        contact.isEmpty
                            ? 'No contact number set — add one in Edit '
                                  'business details, or tick below'
                            : contact,
                        style: TextStyle(
                          color: contact.isEmpty
                              ? AppColors.error
                              : AppColors.white,
                          fontSize: contact.isEmpty ? 11 : 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        InkWell(
          onTap: () => setState(
            () => _useSeparatePayoutPhone = !_useSeparatePayoutPhone,
          ),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _useSeparatePayoutPhone
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _useSeparatePayoutPhone
                      ? AppColors.orange
                      : AppColors.gray400,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Payments go to a different number',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.white,
                      height: 1.4,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_useSeparatePayoutPhone) ...[
          const SizedBox(height: 10),
          _field(
            '${provider.label} number for payments',
            _payoutPhoneController,
            Icons.payments_outlined,
            hint: '0712 345 678',
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 6),
          Text(
            contact.isEmpty
                ? 'Customers will still need a contact number — add one in '
                      'your business details.'
                : 'Customers still call $contact about deliveries.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.gray400,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _paymentTab(MobileMoneyProvider provider) {
    final selected = _paymentMethod == provider.code;
    final icon = switch (provider.code) {
      'till' => Icons.store_rounded,
      'paybill' => Icons.account_balance_outlined,
      _ => Icons.phone_android_rounded,
    };
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMethod = provider.code),
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
              Icon(
                icon,
                color: selected ? AppColors.white : AppColors.gray400,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                provider.code == 'till' ? 'Till No.' : provider.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppColors.white : AppColors.gray400,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
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
        border: Border.all(color: AppColors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.orange,
            size: 15,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.orange,
                height: 1.4,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: AppColors.white,
        fontWeight: FontWeight.w600,
      ),
    );
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
                    color: available ? AppColors.white : AppColors.gray600,
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
                    color: available ? AppColors.white : AppColors.gray600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  available ? 'Available' : 'Not offered',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: available ? AppColors.success : AppColors.gray600,
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
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              style: TextStyle(
                color: available ? AppColors.white : AppColors.gray600,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                prefixText: '${Currency.symbolFor(_detectedCountry)} ',
                prefixStyle: TextStyle(
                  color: available ? AppColors.orange : AppColors.gray600,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                hintText: '0',
                hintStyle: const TextStyle(color: AppColors.gray600),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.white.withValues(alpha: 0.2),
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.white.withValues(alpha: 0.05),
                  ),
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
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 13,
            color: AppColors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: AppColors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.gray600),
            prefixIcon: Icon(icon, color: AppColors.gray400, size: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.white.withValues(alpha: 0.2),
              ),
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