/// The per-site "Footer" form — site-wide closing details. Once per site,
/// like Client inputs (keyed by site, not a repeatable record).
///
/// Every field is optional so partial entries can be saved. Text fields default
/// to empty strings; choice / yes-no fields default to null ("not answered").
class Footer {
  const Footer({
    this.tdsPpm,
    this.tssPpm,
    this.tclService,
    this.tclServiceDetails = '',
    this.generalRemarks = '',
    this.surveyDate,
    this.surveyorName = '',
  });

  /// Total dissolved solids (ppm).
  final double? tdsPpm;

  /// Total suspended solids (ppm).
  final double? tssPpm;

  final bool? tclService;
  final String tclServiceDetails;

  final String generalRemarks;
  final DateTime? surveyDate;
  final String surveyorName;
}
