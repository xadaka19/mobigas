/// Per-country vendor compliance requirements.
///
/// The country a vendor operates in decides which regulator licenses them and
/// therefore which documents onboarding must collect. This file is the single
/// source of truth for that mapping, so adding or correcting a country's
/// requirements is editing a list here — never touching the onboarding screen.
///
/// STATUS (read before trusting the TZ/UG lists):
///   KE — real. Matches EPRA's actual retail requirements, already in
///        production via VendorSetupScreen.
///   TZ — regulator and primary licence name are correct (EWURA Petroleum
///        Retail Licence, applied for via LOIS). The supporting-document list
///        MIRRORS KENYA as a deliberate placeholder and must be confirmed
///        against EWURA's actual retail requirements before a real Tanzanian
///        vendor onboards.
///   UG — regulator is correct (Ministry of Energy and Mineral Development,
///        under the Petroleum Supply Act 2003). Document list MIRRORS KENYA,
///        same caveat as TZ.
///
/// The structure is per-country from day one precisely so that "refine TZ/UG
/// later" is safe: the screen already branches on country, so correcting a
/// list here cannot break KE.
library;

/// A single required document slot in onboarding.
class DocRequirement {
  /// Firestore field the uploaded URL is saved to. Must match the keys
  /// VendorSetupScreen already writes (epraCertificateUrl, businessPermitUrl,
  /// …) so existing upload/preserve logic keeps working unchanged.
  final String docKey;
  final String title;
  final String description;

  /// If non-null, this requirement is the fallback half of an either/or pair,
  /// and [altDocKey] is its partner. The vendor satisfies the requirement with
  /// whichever one they can actually produce. Mirrors the existing KE pairs
  /// (own EPRA cert OR sub-dealer letter; scale cert OR scale photo; brand
  /// letter OR association letter).
  final String? altDocKey;

  const DocRequirement({
    required this.docKey,
    required this.title,
    required this.description,
    this.altDocKey,
  });
}

/// Everything about a country that onboarding and display need. The money
/// fields (currency, symbol, threshold) intentionally duplicate the Firestore
/// countries/{code} doc — this Dart copy is the offline default so the app
/// renders correct labels before the remote config has loaded. The Firestore
/// doc remains authoritative once fetched.
class CountryRequirements {
  final String code;
  final String name;
  final String currency;
  final String currencySymbol;

  /// Regulator shown throughout onboarding. EPRA / EWURA / MEMD.
  final String regulator;

  /// Label for the primary licence, e.g. "EPRA Licence No.".
  final String licenceLabel;

  /// Human name of the primary operating licence, used in upload copy.
  final String primaryLicenceName;

  /// Vendor-lock threshold in MAJOR units of [currency] (minorUnits is 0 for
  /// all three markets). A deliberate local figure, NOT a live FX conversion —
  /// a lock threshold is a stable policy number, not a market-tracking value.
  /// Duplicated from countries/{code}.platformFeeLockThreshold; the Firestore
  /// value wins once loaded.
  final double feeLockThreshold;

  /// The primary licence upload (EPRA cert / EWURA retail licence / MEMD
  /// petroleum operating licence), including its sub-dealer fallback.
  final DocRequirement primaryLicence;

  /// Everything else onboarding collects, in display order.
  final List<DocRequirement> supportingDocuments;

  const CountryRequirements({
    required this.code,
    required this.name,
    required this.currency,
    required this.currencySymbol,
    required this.regulator,
    required this.licenceLabel,
    required this.primaryLicenceName,
    required this.feeLockThreshold,
    required this.primaryLicence,
    required this.supportingDocuments,
  });

  static const CountryRequirements _ke = CountryRequirements(
    code: 'KE',
    name: 'Kenya',
    currency: 'KES',
    currencySymbol: 'KSh',
    regulator: 'EPRA',
    licenceLabel: 'EPRA Licence No.',
    primaryLicenceName: 'EPRA certificate',
    feeLockThreshold: 500,
    primaryLicence: DocRequirement(
      docKey: 'epraCertificateUrl',
      altDocKey: 'subDealerAuthorizationUrl',
      title: 'EPRA certificate',
      description: 'Your EPRA operating certificate/license for LPG retail',
    ),
    supportingDocuments: [
      DocRequirement(
        docKey: 'businessRegistrationUrl',
        title: 'Business name registration certificate',
        description:
            'From eCitizen / the Business Registration Service — required '
            'even for a sole proprietorship',
      ),
      DocRequirement(
        docKey: 'businessPermitUrl',
        title: 'County business permit',
        description: 'Your Single Business Permit from the county government',
      ),
      DocRequirement(
        docKey: 'fireCertificateUrl',
        title: 'Fire clearance certificate',
        description: 'Valid fire safety certificate for your premises',
      ),
      DocRequirement(
        docKey: 'premisesPhotoUrl',
        title: 'Photo of your retail point',
        description:
            'Showing the cylinder holding cage and neighbouring premises — '
            'required by EPRA',
      ),
      DocRequirement(
        docKey: 'weighingScaleCertUrl',
        altDocKey: 'weighingScalePhotoUrl',
        title: 'Weighing scale calibration certificate',
        description: 'From the Department of Weights and Measures',
      ),
      DocRequirement(
        docKey: 'brandAuthorizationUrl',
        altDocKey: 'dealerAssociationLetterUrl',
        title: 'Brand authorization letter',
        description:
            'Written consent to sell from the gas brand(s) you stock',
      ),
    ],
  );

  // ── TANZANIA ────────────────────────────────────────────────────────
  // Regulator + primary licence: REAL. Supporting list: MIRRORS KENYA,
  // placeholder pending EWURA confirmation. Note the doc keys are reused
  // from KE so Firestore/storage plumbing is identical; only labels differ.
  static const CountryRequirements _tz = CountryRequirements(
    code: 'TZ',
    name: 'Tanzania',
    currency: 'TZS',
    currencySymbol: 'TSh',
    regulator: 'EWURA',
    licenceLabel: 'EWURA Licence No.',
    primaryLicenceName: 'EWURA Petroleum Retail Licence',
    feeLockThreshold: 10000,
    primaryLicence: DocRequirement(
      docKey: 'epraCertificateUrl',
      altDocKey: 'subDealerAuthorizationUrl',
      title: 'EWURA Petroleum Retail Licence',
      description:
          'Your EWURA retail licence for LPG (applied for via the EWURA '
          'LOIS portal)',
    ),
    supportingDocuments: [
      DocRequirement(
        docKey: 'businessRegistrationUrl',
        title: 'Business registration (BRELA)',
        description: 'Certificate of business registration from BRELA',
      ),
      DocRequirement(
        docKey: 'businessPermitUrl',
        title: 'Local business licence',
        description: 'Your business licence from the local authority',
      ),
      DocRequirement(
        docKey: 'fireCertificateUrl',
        title: 'Fire clearance certificate',
        description: 'Valid fire safety certificate for your premises',
      ),
      DocRequirement(
        docKey: 'premisesPhotoUrl',
        title: 'Photo of your retail point',
        description:
            'Showing the cylinder holding area and neighbouring premises',
      ),
      DocRequirement(
        docKey: 'weighingScaleCertUrl',
        altDocKey: 'weighingScalePhotoUrl',
        title: 'Weighing scale certificate',
        description: 'Calibration certificate for your weighing scale',
      ),
      DocRequirement(
        docKey: 'brandAuthorizationUrl',
        altDocKey: 'dealerAssociationLetterUrl',
        title: 'Brand authorization letter',
        description:
            'Written consent to sell from the gas brand(s) you stock',
      ),
    ],
  );

  // ── UGANDA ──────────────────────────────────────────────────────────
  // Regulator REAL (MEMD, Petroleum Supply Act 2003). Supporting list
  // MIRRORS KENYA, placeholder pending confirmation.
  static const CountryRequirements _ug = CountryRequirements(
    code: 'UG',
    name: 'Uganda',
    currency: 'UGX',
    currencySymbol: 'USh',
    regulator: 'MEMD',
    licenceLabel: 'Petroleum Operating Licence No.',
    primaryLicenceName: 'Petroleum operating licence',
    feeLockThreshold: 15000,
    primaryLicence: DocRequirement(
      docKey: 'epraCertificateUrl',
      altDocKey: 'subDealerAuthorizationUrl',
      title: 'Petroleum operating licence',
      description:
          'Your operating licence for LPG retail under the Petroleum '
          'Supply Act (Ministry of Energy and Mineral Development)',
    ),
    supportingDocuments: [
      DocRequirement(
        docKey: 'businessRegistrationUrl',
        title: 'Certificate of registration (URSB)',
        description: 'Business registration from the Uganda Registration '
            'Services Bureau',
      ),
      DocRequirement(
        docKey: 'businessPermitUrl',
        title: 'Trading licence',
        description: 'Your trading licence from the local authority',
      ),
      DocRequirement(
        docKey: 'fireCertificateUrl',
        title: 'Fire clearance certificate',
        description: 'Valid fire safety certificate for your premises',
      ),
      DocRequirement(
        docKey: 'premisesPhotoUrl',
        title: 'Photo of your retail point',
        description:
            'Showing the cylinder holding area and neighbouring premises',
      ),
      DocRequirement(
        docKey: 'weighingScaleCertUrl',
        altDocKey: 'weighingScalePhotoUrl',
        title: 'Weighing scale certificate',
        description: 'Calibration certificate for your weighing scale',
      ),
      DocRequirement(
        docKey: 'brandAuthorizationUrl',
        altDocKey: 'dealerAssociationLetterUrl',
        title: 'Brand authorization letter',
        description:
            'Written consent to sell from the gas brand(s) you stock',
      ),
    ],
  );

  static const Map<String, CountryRequirements> _all = {
    'KE': _ke,
    'TZ': _tz,
    'UG': _ug,
  };

  /// Requirements for a country code, defaulting to Kenya for an unknown or
  /// null code so the UI never crashes on a missing country. Callers that need
  /// to reject unsupported countries should check GeoService first.
  static CountryRequirements forCode(String? code) => _all[code] ?? _ke;

  static bool isSupported(String? code) => _all.containsKey(code);
}
