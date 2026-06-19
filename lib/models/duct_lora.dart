/// A single Duct LoRa unit belonging to a site. A site has many.
///
/// Every field is optional so partial entries can be saved. Text fields default
/// to empty strings; choice / yes-no fields default to null ("not answered").
class DuctLora {
  const DuctLora({
    required this.id,
    required this.siteId,
    this.block,
    this.seriesServed = const {},
    this.accessibleForService,
    this.rssiIfTcl,
    this.powerPointAvailableShielded,
    this.separateMcbForSeries,
    this.upsPowerSupply,
    this.cableLength,
  });

  final String id;
  final String siteId;

  final String? block;

  /// Series values served by this unit, drawn from the Series entered on the
  /// site's inlet points. Note: max 20 sensors per unit (advisory only).
  final Set<String> seriesServed;

  final bool? accessibleForService;

  /// RSSI value, relevant only when the unit is TCL.
  final double? rssiIfTcl;

  final bool? powerPointAvailableShielded;

  /// Separate MCB for the series — max 4.
  final bool? separateMcbForSeries;

  final bool? upsPowerSupply;

  /// Duct LoRa cable length (pending confirmation of unit/spec).
  final double? cableLength;

  /// Returns a copy with a different [id]. Used when the repository assigns an
  /// id to a freshly added unit.
  DuctLora copyWithId(String newId) => DuctLora(
    id: newId,
    siteId: siteId,
    block: block,
    seriesServed: seriesServed,
    accessibleForService: accessibleForService,
    rssiIfTcl: rssiIfTcl,
    powerPointAvailableShielded: powerPointAvailableShielded,
    separateMcbForSeries: separateMcbForSeries,
    upsPowerSupply: upsPowerSupply,
    cableLength: cableLength,
  );
}
