/// Regulator-specific wording for the vendor onboarding document step.
///
/// TWO-TIER MODEL (mirrors Kenya, applied to all three countries):
///
///   • Agent / sub-dealer  — the small/estate vendor selling cylinders under a
///     licensed distributor's authorization. THIS IS THE CORE MARKET. They do
///     NOT need construction approval, an EIA, or an engineer's layout plan —
///     those belong to the own-licence tier. They need a distributor
///     authorization letter, plus the light supporting docs (permit, fire,
///     premises photo, scale, brand letter).
///
///   • Own licence — the larger operator holding their own retail licence.
///
/// The toggle structure is identical across countries; only the regulator NAMES
/// and one or two own-licence-tier extras change. This class supplies the
/// country-specific strings; the Step 3 widget keeps its existing toggles.
///
/// SOURCING / STATUS:
///   KE — real, in production. EPRA. Sub-dealer authorization is an established
///        path for agents.
///   TZ — regulator + primary licence VERIFIED against EWURA
///        (ewura.go.tz, LOIS portal lois.ewura.go.tz; Petroleum Retail Licence,
///        Petroleum (LPG Operations) Rules 2020). The agent/authorization path
///        is modelled on Kenya's structure — CONFIRM with a Tanzanian
///        distributor that an authorization letter from an EWURA-licensed
///        supplier is accepted for a sub-agent, as it is in Kenya.
///   UG — NAME-SWAP PLACEHOLDER. Regulator (MEMD, Petroleum Supply Act 2003)
///        and licence name are correct, but the agent-tier document specifics
///        are NOT yet verified. Treat UG wording as provisional until confirmed.
///
/// The narrow goal, achieved now: no vendor is ever shown the WRONG regulator's
/// name. A Ugandan agent seeing "EPRA" is nonsense; seeing "operating licence"
/// on a Kenya-shaped agent form is imperfect-but-honest, and correct enough for
/// a market with no live vendors yet.
library;

class RegulatorText {
  final String regulator; // EPRA | EWURA | MEMD
  final bool verified; // false => provisional wording, confirm before real use

  /// Section header for the licence step.
  final String licenceSectionTitle;

  /// Own-licence tier.
  final String ownLicenceToggle; // "I have my own EPRA certificate"
  final String ownLicenceTitle; // upload card title
  final String ownLicenceDescription;

  /// Agent / sub-dealer tier — the core small-vendor path.
  final String agentToggle; // "I'm a sub-dealer / agent"
  final String agentAuthTitle; // authorization upload card title
  final String agentAuthDescription;
  final String parentNameLabel; // "Parent vendor / licensed business name"
  final String parentLicenceNumberLabel;

  /// Supporting docs shared by both tiers — only the trailing authority phrase
  /// differs by country.
  final String premisesPhotoNote; // "required by EPRA"
  final String scaleAuthority; // who certifies the weighing scale

  const RegulatorText({
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
    required this.premisesPhotoNote,
    required this.scaleAuthority,
  });

  // ── KENYA — real, in production ──────────────────────────────────────
  static const _ke = RegulatorText(
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
    premisesPhotoNote: 'required by EPRA',
    scaleAuthority: 'the Department of Weights and Measures',
  );

  // ── TANZANIA — regulator/licence verified; agent path modelled on KE ──
  static const _tz = RegulatorText(
    regulator: 'EWURA',
    verified: true,
    licenceSectionTitle: 'EWURA licence',
    ownLicenceToggle: 'I have my own EWURA licence',
    ownLicenceTitle: 'EWURA Petroleum Retail Licence',
    ownLicenceDescription:
        'Your EWURA Petroleum Retail Licence for LPG, applied for via the '
        'EWURA LOIS portal (lois.ewura.go.tz)',
    agentToggle: "I'm a sub-dealer / agent",
    agentAuthTitle: 'Distributor authorization letter',
    agentAuthDescription:
        'A letter or agreement showing you sell on behalf of an EWURA-licensed '
        'distributor — accepted in place of your own EWURA licence',
    parentNameLabel: 'Parent distributor / licensed business name',
    parentLicenceNumberLabel: 'Parent distributor EWURA licence number',
    // TZ weighing-scale certification authority not yet verified — use a
    // neutral phrase rather than a guessed agency name.
    premisesPhotoNote: 'required for licensing',
    scaleAuthority: 'the relevant weights and measures authority',
  );

  // ── UGANDA — NAME-SWAP PLACEHOLDER, agent specifics unverified ────────
  static const _ug = RegulatorText(
    regulator: 'MEMD',
    verified: false,
    licenceSectionTitle: 'Petroleum operating licence',
    ownLicenceToggle: 'I have my own operating licence',
    ownLicenceTitle: 'Petroleum operating licence',
    ownLicenceDescription:
        'Your operating licence for LPG retail under the Petroleum Supply Act '
        '(Ministry of Energy and Mineral Development)',
    agentToggle: "I'm a sub-dealer / agent",
    agentAuthTitle: 'Distributor authorization letter',
    agentAuthDescription:
        'A letter or agreement showing you sell on behalf of a licensed '
        'distributor — accepted in place of your own operating licence',
    parentNameLabel: 'Parent distributor / licensed business name',
    parentLicenceNumberLabel: 'Parent distributor licence number',
    premisesPhotoNote: 'required for licensing',
    scaleAuthority: 'the Uganda National Bureau of Standards',
  );

  static const Map<String, RegulatorText> _byCode = {
    'KE': _ke,
    'TZ': _tz,
    'UG': _ug,
  };

  /// Wording for a country code. Defaults to Kenya for an unknown/null code,
  /// since KE is the launch market and the screen must render something.
  static RegulatorText forCountry(String? code) => _byCode[code] ?? _ke;
}
