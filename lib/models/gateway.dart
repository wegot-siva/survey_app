import 'survey_options.dart';

/// A single Gateway unit belonging to a site. A site has many.
///
/// Every field is optional so partial entries can be saved. Text fields default
/// to empty strings; choice / yes-no fields default to null ("not answered").
class Gateway {
  const Gateway({
    required this.id,
    required this.siteId,
    this.placement,
    this.locationDescription = '',
    this.blocksCovered = const {},
    this.quantity,
    this.uplinkType,
    this.wifiInterferenceCheck,
    this.wifiInterferenceDetails = '',
    this.simCoverage,
    this.uninterruptedPowerSource,
    this.mountingHardwareNeeded = '',
  });

  final String id;
  final String siteId;

  final GatewayPlacement? placement;
  final String locationDescription;

  /// Blocks covered by this gateway, drawn from the site's block list.
  final Set<String> blocksCovered;

  final int? quantity;
  final UplinkType? uplinkType;

  /// WiFi interference check — only relevant when [uplinkType] is router/both.
  final bool? wifiInterferenceCheck;
  final String wifiInterferenceDetails;

  final SimCoverage? simCoverage;
  final bool? uninterruptedPowerSource;
  final String mountingHardwareNeeded;

  /// Whether the WiFi-interference question applies to the chosen uplink.
  bool get usesRouter =>
      uplinkType == UplinkType.router || uplinkType == UplinkType.both;

  /// Returns a copy with a different [id]. Used when the repository assigns an
  /// id to a freshly added gateway.
  Gateway copyWithId(String newId) => Gateway(
    id: newId,
    siteId: siteId,
    placement: placement,
    locationDescription: locationDescription,
    blocksCovered: blocksCovered,
    quantity: quantity,
    uplinkType: uplinkType,
    wifiInterferenceCheck: wifiInterferenceCheck,
    wifiInterferenceDetails: wifiInterferenceDetails,
    simCoverage: simCoverage,
    uninterruptedPowerSource: uninterruptedPowerSource,
    mountingHardwareNeeded: mountingHardwareNeeded,
  );
}
