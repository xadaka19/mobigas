/// Per-country LPG retail vendor requirements — the documents each market's
/// regulator actually requires of a SMALL/AGENT cylinder retailer, and the
/// wording used to ask for them.
///
/// Lives in core/config (not features/vendor/widgets) because it holds no
/// widgets: it's const data, and core/models/app_models.dart depends on it
/// for VendorModel.documentsSubmitted. Same shelf as mobile_money.dart.
///
/// MERGED: this file used to have a twin, features/vendor/widgets/
/// regulator_text.dart, which defined the same nine licence-tier strings for
/// the same three countries. Step 3 read the twin, so vendors got ITS values
/// — and it was the older, less-researched set: it punted on Tanzania's scale
/// authority ("the relevant weights and measures authority") where this file
/// names the WMA, and gave a generic agent path where this file names the
/// actual wholesalers. The twin is deleted; this is the only source now.
///
/// TWO-TIER, per country:
///   • Agent / sub-dealer — sells cylinders under a licensed distributor's
///     authorization. The core market. No plant/construction/EIA requirements.
///   • Own licence — holds their own retail licence.
///
/// The licence tier (own vs agent) uses the same either/or toggle in every
/// country; only its wording changes. The SUPPORTING documents genuinely differ
/// by country and are listed per country below.
///
/// SOURCING:
///   KE — EPRA, in production (unchanged from the live Kenyan flow).
///   TZ — EWURA Petroleum Retail Operations Rules. Verified: BRELA registration,
///        TIN + Tax Clearance (TRA), municipal business licence, Tanzania Fire
///        and Rescue Force clearance, WMA-certified scale, wholesale
///        authorization letter, no-decanting prohibition.
///   UG — MEMD / Petroleum Supply Act 2003. Verified: URSB registration, local
///        trading licence (town council/KCCA), Police Fire Prevention inspection
///        + clearance, UNBS-certified scale, brand authorization letters,
///        no-decanting prohibition.
library;

/// One required document slot.
class VendorDoc {
  /// Firestore field the uploaded URL is stored under. Reuse existing KE keys
  /// where the document is the same thing, so storage/preserve logic is shared.
  final String key;
  final String title;
  final String description;

  /// Only required for sole proprietors (KE pattern). Companies prove
  /// registration via their incorporation cert instead.
  final bool soleOnly;

  const VendorDoc({
    required this.key,
    required this.title,
    required this.description,
    this.soleOnly = false,
  });
}

/// The full requirement set for one country.
class VendorRequirements {
  final String code; // KE | TZ | UG

  final String regulator;

  /// Documentation only — nothing reads this. Kept as a marker of how much
  /// trust the wording below has earned. NOTE: the deleted regulator_text.dart
  /// marked UG `false` ("NAME-SWAP PLACEHOLDER, agent specifics unverified")
  /// while this file marks it `true` with sourced specifics. This file's value
  /// is carried forward as the later judgement — but nothing depends on it
  /// either way, so if UG's agent tier is in fact still provisional, flipping
  /// this changes no behaviour and needs no other edit.
  final bool verified;

  // ── Licence tier (either/or toggle) ──
  final String licenceSectionTitle;
  final String ownLicenceToggle;
  final String ownLicenceTitle;
  final String ownLicenceDescription;
  final String agentToggle;
  final String agentAuthTitle;
  final String agentAuthDescription;
  final String parentNameLabel;
  final String parentLicenceNumberLabel;

  // ── Supporting docs, in display order (country-specific) ──
  /// Step 3 renders these in order, skipping soleOnly entries for a registered
  /// business or petrol station. Adding a country's document here is all it
  /// takes to have it asked for AND counted by [documentsSubmitted] — the
  /// screen and the getter both drive off this list, so they can't drift.
  final List<VendorDoc> supportingDocs;

  // ── Scale sub-toggle wording (cert vs photo — all three share the toggle) ──
  final String scaleCertTitle;
  final String scaleCertDescription;
  final String scalePhotoTitle;
  final String scalePhotoDescription;

  // ── Brand authorization sub-toggle wording ──
  final String brandLetterTitle;
  final String brandLetterDescription;
  final String brandAltTitle;
  final String brandAltDescription;

  // ── Legal acknowledgment (null = none, e.g. Kenya) ──
  /// A rule the vendor must tick to confirm they understand. TZ & UG legally
  /// prohibit decanting (refilling one cylinder from another); vendors must
  /// acknowledge it. Null where the flow doesn't require an explicit tick.
  final String? acknowledgment;

  const VendorRequirements({
    required this.code,
    required this.regulator,
    required this.verified,
    required this.licenceSectionTitle,
    required this.ownLicenceToggle,
    required this.ownLicenceTitle,
    required this.ownLicenceDescription,
    required this.agentToggle,
    required this.agentAuthTitle,
    required this.agentAuthDescription,
    required this.parentNameLabel,
    required this.parentLicenceNumberLabel,
    required this.supportingDocs,
    required this.scaleCertTitle,
    required this.scaleCertDescription,
    required this.scalePhotoTitle,
    required this.scalePhotoDescription,
    required this.brandLetterTitle,
    required this.brandLetterDescription,
    required this.brandAltTitle,
    required this.brandAltDescription,
    this.acknowledgment,
  });

  /// The three either/or pairs, identical in every market — a vendor satisfies
  /// each with whichever form they can actually get, never both.
  static const licenceKeys = ['epraCertificateUrl', 'subDealerAuthorizationUrl'];
  static const scaleKeys = ['weighingScaleCertUrl', 'weighingScalePhotoUrl'];
  static const brandKeys = [
    'brandAuthorizationUrl',
    'dealerAssociationLetterUrl',
  ];

  /// Whether every document THIS country requires has an acceptable form
  /// uploaded — independent of admin approval (isVerified), so the UI can
  /// distinguish "nothing submitted yet" from "submitted, awaiting review".
  ///
  /// [urlFor] resolves a Firestore key to its stored URL. It's a callback
  /// because the vendor's data reaches callers in two shapes — VendorModel's
  /// typed fields, or the raw Firestore map on the vendor home screen — and
  /// that is the only difference between them. Both used to hand-roll this
  /// check with a hardcoded KE-shaped document list, which meant a Tanzanian
  /// vendor missing their TRA tax clearance still counted as fully submitted
  /// and was told "Documents under review" while they were still short a
  /// document. Driving off [supportingDocs] is what fixes that, and what stops
  /// the next market's extra document from silently repeating it.
  ///
  /// ackNoDecanting is deliberately NOT checked: VendorSetupScreen._save()
  /// refuses to write at all without it where a country requires it, so a
  /// vendor with documents on file cannot have it false.
  bool documentsSubmitted({
    required String Function(String key) urlFor,
    required bool isSole,
  }) {
    bool has(String key) => urlFor(key).trim().isNotEmpty;
    bool either(List<String> keys) => keys.any(has);

    final supportingIn = supportingDocs
        .where((d) => !d.soleOnly || isSole)
        .every((d) => has(d.key));

    return either(licenceKeys) &&
        either(scaleKeys) &&
        either(brandKeys) &&
        supportingIn;
  }

  // ════════════════════════════════════════════════════════════════════
  //  KENYA — unchanged from production
  // ════════════════════════════════════════════════════════════════════
  static const _ke = VendorRequirements(
    code: 'KE',
    regulator: 'EPRA',
    verified: true,
    licenceSectionTitle: 'EPRA licence',
    ownLicenceToggle: 'I have my own EPRA certificate',
    ownLicenceTitle: 'EPRA certificate',
    ownLicenceDescription:
        'Your EPRA operating certificate/license for LPG retail',
    agentToggle: "I'm a sub-dealer / agent",
    agentAuthTitle: 'Sub-dealer / agent authorization letter',
    agentAuthDescription:
        'A letter or agreement showing you sell on behalf of an already '
        'EPRA-licensed vendor — accepted in place of your own EPRA certificate',
    parentNameLabel: 'Parent vendor / licensed business name',
    parentLicenceNumberLabel: 'Parent vendor EPRA certificate number',
    supportingDocs: [
      VendorDoc(
        key: 'businessRegistrationUrl',
        title: 'Business name registration certificate',
        description:
            'From eCitizen / the Business Registration Service — required '
            'even for a sole proprietorship',
        soleOnly: true,
      ),
      VendorDoc(
        key: 'businessPermitUrl',
        title: 'County business permit',
        description: 'Your Single Business Permit from the county government',
      ),
      VendorDoc(
        key: 'fireCertificateUrl',
        title: 'Fire clearance certificate',
        description: 'Valid fire safety certificate for your premises',
      ),
      VendorDoc(
        key: 'premisesPhotoUrl',
        title: 'Photo of your retail point',
        description:
            'Showing the cylinder holding cage and neighbouring premises — '
            'required by EPRA',
      ),
    ],
    scaleCertTitle: 'Weighing scale calibration certificate',
    scaleCertDescription: 'From the Department of Weights and Measures',
    scalePhotoTitle: 'Photo of your weighing scale',
    scalePhotoDescription:
        'Clear photo showing the scale is rated for at least 300kg — accepted '
        'in place of a calibration certificate',
    brandLetterTitle: 'Brand authorization letter',
    brandLetterDescription:
        'Written consent to sell from the gas brand(s) you stock (e.g. an '
        'appointment letter from Total Gas, K-Gas, Hashi, Africa Gas, etc.)',
    brandAltTitle: 'Independent dealer association letter',
    brandAltDescription:
        'Authorization letter from an independent LPG dealer association, in '
        'place of a direct brand letter',
    acknowledgment: null,
  );

  // ════════════════════════════════════════════════════════════════════
  //  TANZANIA — EWURA, verified
  // ════════════════════════════════════════════════════════════════════
  static const _tz = VendorRequirements(
    code: 'TZ',
    regulator: 'EWURA',
    verified: true,
    licenceSectionTitle: 'EWURA licence',
    ownLicenceToggle: 'I have my own EWURA licence',
    ownLicenceTitle: 'EWURA Petroleum Retail Licence',
    ownLicenceDescription:
        'Your EWURA Petroleum Retail Licence for LPG (via the EWURA LOIS '
        'portal, lois.ewura.go.tz)',
    agentToggle: "I'm a sub-dealer / agent",
    agentAuthTitle: 'Wholesale supplier authorization letter',
    agentAuthDescription:
        'A written contract or authorization letter from an EWURA-licensed '
        'wholesale supplier (e.g. Taifa Gas, Oryx Energies, Manjis Gas) — '
        'accepted in place of your own EWURA licence',
    parentNameLabel: 'Wholesale supplier / licensed business name',
    parentLicenceNumberLabel: 'Supplier EWURA licence number',
    supportingDocs: [
      VendorDoc(
        key: 'businessRegistrationUrl',
        title: 'BRELA registration certificate',
        description:
            'Certificate of Incorporation or Business Name registration from '
            'BRELA (Business Registrations and Licensing Agency)',
        soleOnly: true,
      ),
      // TZ-specific: TRA tax clearance is a hard requirement Kenya doesn't have.
      VendorDoc(
        key: 'taxClearanceUrl',
        title: 'TIN & Tax Clearance Certificate',
        description:
            'Your Taxpayer Identification Number and a valid Tax Clearance '
            'Certificate from the Tanzania Revenue Authority (TRA)',
      ),
      VendorDoc(
        key: 'businessPermitUrl',
        title: 'Municipal business licence',
        description:
            'Business licence from your local Municipal Council '
            '(e.g. Ilala, Kinondoni) or the Ministry of Industry and Trade',
      ),
      VendorDoc(
        key: 'fireCertificateUrl',
        title: 'Fire safety clearance',
        description:
            'Inspection report and certificate from the Tanzania Fire and '
            'Rescue Force. A 9kg DCP fire extinguisher must be mounted nearby',
      ),
      VendorDoc(
        key: 'premisesPhotoUrl',
        title: 'Photo of your storage cage',
        description:
            'Showing your open-air, non-combustible wire-mesh cylinder cage. '
            'Indoor or residential storage is an offence under EWURA rules',
      ),
    ],
    scaleCertTitle: 'WMA weighing scale certificate',
    scaleCertDescription:
        'Scale calibrated and stamped by the Weights and Measures Agency (WMA) '
        'so customers can verify exact weight (6kg, 15kg, 38kg)',
    scalePhotoTitle: 'Photo of your weighing scale',
    scalePhotoDescription:
        'Clear photo of your WMA-stamped scale — accepted temporarily in place '
        'of the certificate',
    brandLetterTitle: 'Brand / wholesale authorization letter',
    brandLetterDescription:
        'Written consent to sell from the LPG brand(s) you stock '
        '(e.g. Taifa Gas, Oryx, Manjis, TotalEnergies)',
    brandAltTitle: 'Dealer association letter',
    brandAltDescription:
        'Authorization from a recognised LPG dealer association, in place of a '
        'direct brand letter',
    acknowledgment:
        'I understand that decanting (transferring gas between cylinders) is '
        'strictly prohibited. I will only buy and exchange pre-filled cylinders '
        'from licensed distributors.',
  );

  // ════════════════════════════════════════════════════════════════════
  //  UGANDA — MEMD / Petroleum Supply Act 2003, verified
  // ════════════════════════════════════════════════════════════════════
  static const _ug = VendorRequirements(
    code: 'UG',
    regulator: 'MEMD',
    verified: true,
    licenceSectionTitle: 'Petroleum operating licence',
    ownLicenceToggle: 'I have my own operating licence',
    ownLicenceTitle: 'Petroleum operating licence',
    ownLicenceDescription:
        'Your operating licence for LPG retail under the Petroleum Supply Act '
        '(Ministry of Energy and Mineral Development)',
    agentToggle: "I'm a sub-dealer / agent",
    agentAuthTitle: 'Distributor authorization letter',
    agentAuthDescription:
        'A retail supply contract or authorization letter from a major LPG '
        'brand owner (e.g. Stabex, TotalEnergies, Shell/Vivo Energy) — accepted '
        'in place of your own operating licence',
    parentNameLabel: 'Distributor / brand owner name',
    parentLicenceNumberLabel: 'Distributor licence number (if known)',
    supportingDocs: [
      VendorDoc(
        key: 'businessRegistrationUrl',
        title: 'URSB business registration certificate',
        description:
            'Business Registration Certificate from the Uganda Registration '
            'Services Bureau (URSB)',
        soleOnly: true,
      ),
      VendorDoc(
        key: 'businessPermitUrl',
        title: 'Trading licence',
        description:
            'Trading licence from your local town council or the KCCA (Kampala '
            'Capital City Authority)',
      ),
      VendorDoc(
        key: 'fireCertificateUrl',
        title: 'Fire clearance certificate',
        description:
            'Inspection report and clearance from the local Police Fire '
            'Prevention Department. A 9kg DCP fire extinguisher must be present',
      ),
      VendorDoc(
        key: 'premisesPhotoUrl',
        title: 'Photo of your storage cage',
        description:
            'Showing your open-air, non-combustible (metal grille) cage, '
            'shielded from direct sunlight. Indoor/basement storage is banned. '
            'Display "No Smoking" and "Highly Inflammable" signs',
      ),
    ],
    scaleCertTitle: 'UNBS weighing scale certificate',
    scaleCertDescription:
        'Scale verified by the Uganda National Bureau of Standards (UNBS) so '
        'customers can verify the exact weight of gas before purchase',
    scalePhotoTitle: 'Photo of your weighing scale',
    scalePhotoDescription:
        'Clear photo of your UNBS-verified scale — accepted temporarily in '
        'place of the certificate',
    brandLetterTitle: 'Brand authorization letter',
    brandLetterDescription:
        'Written retail supply contract or authorization letter from a major '
        'LPG brand owner (Stabex, TotalEnergies, Shell/Vivo Energy, etc.)',
    brandAltTitle: 'Dealer association letter',
    brandAltDescription:
        'Authorization from a recognised LPG dealer association, in place of a '
        'direct brand letter',
    acknowledgment:
        'I understand that decanting (transferring gas between cylinders) is '
        'strictly prohibited. I will only buy and exchange pre-filled cylinders '
        'from licensed distributors.',
  );

  static const Map<String, VendorRequirements> _byCode = {
    'KE': _ke,
    'TZ': _tz,
    'UG': _ug,
  };

  /// Requirements for a country code. Defaults to Kenya for unknown/null.
  static VendorRequirements forCountry(String? code) => _byCode[code] ?? _ke;
}
