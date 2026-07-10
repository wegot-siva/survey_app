import 'survey_options.dart';

/// A single source point belonging to a site. A site has many.
///
/// Every field is optional so partial entries can be saved. Text fields default
/// to empty strings; choice / yes-no fields default to null ("not answered").
class SourcePoint {
  const SourcePoint({
    required this.id,
    required this.siteId,
    this.block,
    this.apartment = '',
    this.inletDescription = '',
    this.sensorSize,
    this.sensorOd,
    this.pipeSize,
    this.pipeType,
    this.qty,
    this.sensorType,
    this.rework,
    this.reworkDetails = '',
    this.flowDirection,
    this.clearance10x,
    this.pipeFull,
    this.valveDownstream,
    this.reducerSpec,
    this.reducerSpecDetails = '',
    this.downstreamOutletAbovePipeFig1,
    this.airVentNeededFig2,
    this.reverseFlow,
    this.distanceFromMotorPumpFig3,
    this.noFlexiblePipeWithin20x,
    this.maxAndContinuousPressureBar,
    this.strainerScreenFilter,
    this.chamberInstallation,
    this.antennaRequired,
    this.transmittingPartOpenToAir,
    this.nrvFeasibility,
  });

  final String id;
  final String siteId;

  final String? block;
  final String apartment;
  final String inletDescription;

  final SensorSize? sensorSize;
  final SensorOd? sensorOd;
  final PipeSize? pipeSize;
  final PipeType? pipeType;
  final int? qty;
  final SensorType? sensorType;

  final bool? rework;
  final String reworkDetails;

  final FlowDirection? flowDirection;
  final bool? clearance10x;
  final bool? pipeFull;
  final bool? valveDownstream;

  final bool? reducerSpec;
  final String reducerSpecDetails;

  final bool? downstreamOutletAbovePipeFig1;
  final bool? airVentNeededFig2;
  final bool? reverseFlow;
  final bool? distanceFromMotorPumpFig3;
  final bool? noFlexiblePipeWithin20x;

  final double? maxAndContinuousPressureBar;
  final bool? strainerScreenFilter;
  final bool? chamberInstallation;

  // Shown only when [sensorType] is Wireless.
  final bool? antennaRequired;
  final bool? transmittingPartOpenToAir;
  final bool? nrvFeasibility;

  bool get isWireless => sensorType == SensorType.wireless;

  /// Returns a copy with a different [id]. Used when the repository assigns an
  /// id to a freshly added source point (avoids a full nullable copyWith).
  SourcePoint copyWithId(String newId) => SourcePoint(
    id: newId,
    siteId: siteId,
    block: block,
    apartment: apartment,
    inletDescription: inletDescription,
    sensorSize: sensorSize,
    sensorOd: sensorOd,
    pipeSize: pipeSize,
    pipeType: pipeType,
    qty: qty,
    sensorType: sensorType,
    rework: rework,
    reworkDetails: reworkDetails,
    flowDirection: flowDirection,
    clearance10x: clearance10x,
    pipeFull: pipeFull,
    valveDownstream: valveDownstream,
    reducerSpec: reducerSpec,
    reducerSpecDetails: reducerSpecDetails,
    downstreamOutletAbovePipeFig1: downstreamOutletAbovePipeFig1,
    airVentNeededFig2: airVentNeededFig2,
    reverseFlow: reverseFlow,
    distanceFromMotorPumpFig3: distanceFromMotorPumpFig3,
    noFlexiblePipeWithin20x: noFlexiblePipeWithin20x,
    maxAndContinuousPressureBar: maxAndContinuousPressureBar,
    strainerScreenFilter: strainerScreenFilter,
    chamberInstallation: chamberInstallation,
    antennaRequired: antennaRequired,
    transmittingPartOpenToAir: transmittingPartOpenToAir,
    nrvFeasibility: nrvFeasibility,
  );

  /// Returns a duplicate-ready draft: every technical/spec field copied, but
  /// unpersisted (empty [id]). [apartment] is copied too (pre-filled, not
  /// cleared) — the form auto-focuses it so the user reviews/edits it before
  /// saving, rather than being forced to type it from scratch. [inletDescription]
  /// still clears, since it's free-text detail specific to this physical
  /// point and shouldn't silently carry onto a new one. Never copies photos
  /// (photos are looked up by id in a separate table, and a fresh id never
  /// matches an existing photo row).
  SourcePoint copyAsDuplicate() => SourcePoint(
    id: '',
    siteId: siteId,
    block: block,
    apartment: apartment,
    inletDescription: '',
    sensorSize: sensorSize,
    sensorOd: sensorOd,
    pipeSize: pipeSize,
    pipeType: pipeType,
    qty: qty,
    sensorType: sensorType,
    rework: rework,
    reworkDetails: reworkDetails,
    flowDirection: flowDirection,
    clearance10x: clearance10x,
    pipeFull: pipeFull,
    valveDownstream: valveDownstream,
    reducerSpec: reducerSpec,
    reducerSpecDetails: reducerSpecDetails,
    downstreamOutletAbovePipeFig1: downstreamOutletAbovePipeFig1,
    airVentNeededFig2: airVentNeededFig2,
    reverseFlow: reverseFlow,
    distanceFromMotorPumpFig3: distanceFromMotorPumpFig3,
    noFlexiblePipeWithin20x: noFlexiblePipeWithin20x,
    maxAndContinuousPressureBar: maxAndContinuousPressureBar,
    strainerScreenFilter: strainerScreenFilter,
    chamberInstallation: chamberInstallation,
    antennaRequired: antennaRequired,
    transmittingPartOpenToAir: transmittingPartOpenToAir,
    nrvFeasibility: nrvFeasibility,
  );
}
