/// Domain enums + model for the per-site "Client inputs" form (Phase 0).
///
/// Every field is optional so partial entries can be saved. Text fields
/// default to empty strings; choice fields default to null ("not answered").
library;

enum InformationSource {
  physicalSurvey('Physical survey'),
  drawing('Drawing');

  const InformationSource(this.label);
  final String label;
}

enum WaterSource {
  municipality('Municipality'),
  borewell('Borewell'),
  tanker('Tanker'),
  rainwater('Rainwater'),
  stp('STP'),
  etp('ETP'),
  ro('RO');

  const WaterSource(this.label);
  final String label;
}

enum OhtHns {
  oht('OHT'),
  hns('HNS'),
  both('Both');

  const OhtHns(this.label);
  final String label;
}

/// Immutable snapshot of the Client inputs form for a single site.
class ClientInputs {
  const ClientInputs({
    this.siteName = '',
    this.informationSource,
    this.clientPocName = '',
    this.clientPocContact = '',
    this.goalOfInstallation = '',
    this.waterSources = const {},
    this.ohtHns,
    this.finalisedPlumbingDrawings,
    this.pointsIdentified,
    this.maxAndContinuousPressure = '',
    this.pressureBoosters,
    this.materialsAndBrandGuidelines = '',
    this.reworkRequired,
    this.reworkDetails = '',
    this.ageOfPlumbingLines = '',
    this.aestheticGuidelines,
    this.aestheticDetails = '',
  });

  final String siteName;
  final InformationSource? informationSource;
  final String clientPocName;
  final String clientPocContact;
  final String goalOfInstallation;
  final Set<WaterSource> waterSources;
  final OhtHns? ohtHns;

  /// Finalised plumbing drawings yes/no. File attach is a Phase 0 placeholder.
  final bool? finalisedPlumbingDrawings;

  /// No. of points identified by client (optional).
  final int? pointsIdentified;
  final String maxAndContinuousPressure;
  final bool? pressureBoosters;
  final String materialsAndBrandGuidelines;

  final bool? reworkRequired;
  final String reworkDetails;

  final String ageOfPlumbingLines;

  final bool? aestheticGuidelines;
  final String aestheticDetails;
}
