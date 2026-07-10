import 'survey_options.dart';

/// A single inlet point belonging to a site. A site has many.
///
/// Every field is optional so partial entries can be saved. Text fields default
/// to empty strings; choice / yes-no fields default to null ("not answered").
class InletPoint {
  const InletPoint({
    required this.id,
    required this.siteId,
    this.block,
    this.apartmentBhk = '',
    this.sensorSize,
    this.series = '',
    this.sensorOd,
    this.pipeSize,
    this.pipeType,
    this.qty,
    this.sensorType,
    this.rework,
    this.reworkDetails = '',
    this.linearDistanceClearance10x,
    this.reverseFlow,
    this.ohtHns,
    this.distanceFromMotorPump,
    this.maxAndContinuousPressureBar,
    this.strainerScreenFilter,
    this.flowDirection,
    this.accessMode,
    this.cableRunLength,
    this.conduitClamping,
    this.civilWorkNeeded,
    this.civilWorkDetails = '',
  });

  final String id;
  final String siteId;

  final String? block;
  final String apartmentBhk;

  final SensorSize? sensorSize;
  final String series;
  final SensorOd? sensorOd;
  final PipeSize? pipeSize;
  final PipeType? pipeType;
  final int? qty;
  final SensorType? sensorType;

  final bool? rework;
  final String reworkDetails;

  final bool? linearDistanceClearance10x;
  final bool? reverseFlow;
  final OhtHns? ohtHns;
  final bool? distanceFromMotorPump;
  final double? maxAndContinuousPressureBar;
  final bool? strainerScreenFilter;
  final FlowDirection? flowDirection;
  final AccessMode? accessMode;
  final CableRunLength? cableRunLength;
  final bool? conduitClamping;

  final bool? civilWorkNeeded;
  final String civilWorkDetails;

  /// Returns a copy with a different [id]. Used when the repository assigns an
  /// id to a freshly added inlet point.
  InletPoint copyWithId(String newId) => InletPoint(
    id: newId,
    siteId: siteId,
    block: block,
    apartmentBhk: apartmentBhk,
    sensorSize: sensorSize,
    series: series,
    sensorOd: sensorOd,
    pipeSize: pipeSize,
    pipeType: pipeType,
    qty: qty,
    sensorType: sensorType,
    rework: rework,
    reworkDetails: reworkDetails,
    linearDistanceClearance10x: linearDistanceClearance10x,
    reverseFlow: reverseFlow,
    ohtHns: ohtHns,
    distanceFromMotorPump: distanceFromMotorPump,
    maxAndContinuousPressureBar: maxAndContinuousPressureBar,
    strainerScreenFilter: strainerScreenFilter,
    flowDirection: flowDirection,
    accessMode: accessMode,
    cableRunLength: cableRunLength,
    conduitClamping: conduitClamping,
    civilWorkNeeded: civilWorkNeeded,
    civilWorkDetails: civilWorkDetails,
  );

  /// Returns a duplicate-ready draft: every technical/spec field copied
  /// (including [series]), but unpersisted (empty [id]). [apartmentBhk] is
  /// copied too (pre-filled, not cleared) — the form auto-focuses it so the
  /// user reviews/edits it before saving, rather than being forced to type
  /// it from scratch. Never copies photos (photos are looked up by id in a
  /// separate table, and a fresh id never matches an existing photo row).
  InletPoint copyAsDuplicate() => InletPoint(
    id: '',
    siteId: siteId,
    block: block,
    apartmentBhk: apartmentBhk,
    sensorSize: sensorSize,
    series: series,
    sensorOd: sensorOd,
    pipeSize: pipeSize,
    pipeType: pipeType,
    qty: qty,
    sensorType: sensorType,
    rework: rework,
    reworkDetails: reworkDetails,
    linearDistanceClearance10x: linearDistanceClearance10x,
    reverseFlow: reverseFlow,
    ohtHns: ohtHns,
    distanceFromMotorPump: distanceFromMotorPump,
    maxAndContinuousPressureBar: maxAndContinuousPressureBar,
    strainerScreenFilter: strainerScreenFilter,
    flowDirection: flowDirection,
    accessMode: accessMode,
    cableRunLength: cableRunLength,
    conduitClamping: conduitClamping,
    civilWorkNeeded: civilWorkNeeded,
    civilWorkDetails: civilWorkDetails,
  );
}
