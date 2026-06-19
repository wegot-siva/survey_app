import 'package:sqflite/sqflite.dart';

import '../models/client_inputs.dart';
import '../models/inlet_point.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';
import '../services/id_service.dart';
import 'survey_repository.dart';

/// SQLite-backed [SurveyRepository]. Data survives app restarts.
///
/// Sits behind the same interface as the in-memory stub, so no UI code changes.
/// Blocks are stored as ordered rows; client inputs as one row per site.
class SqfliteSurveyRepository implements SurveyRepository {
  SqfliteSurveyRepository(this._db, this._idService);

  final Database _db;
  final IdService _idService;

  @override
  Future<List<Site>> getSites() async {
    final rows = await _db.query('sites', orderBy: 'name COLLATE NOCASE');
    final sites = <Site>[];
    for (final row in rows) {
      sites.add(await _hydrate(row));
    }
    return sites;
  }

  @override
  Future<Site?> getSiteById(String id) async {
    final rows = await _db.query(
      'sites',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _hydrate(rows.first);
  }

  @override
  Future<Site> createSite({
    required String name,
    List<String> blocks = const [],
  }) async {
    final id = _idService.newId();
    await _db.transaction((txn) async {
      await txn.insert('sites', {'id': id, 'name': name});
      await _writeBlocks(txn, id, blocks);
    });
    return Site(id: id, name: name, blocks: List.unmodifiable(blocks));
  }

  @override
  Future<void> updateSite(Site site) async {
    await _db.transaction((txn) async {
      await txn.update(
        'sites',
        {'name': site.name},
        where: 'id = ?',
        whereArgs: [site.id],
      );
      await txn.delete('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      await _writeBlocks(txn, site.id, site.blocks);

      final inputs = site.clientInputs;
      if (inputs == null) {
        await txn.delete(
          'client_inputs',
          where: 'site_id = ?',
          whereArgs: [site.id],
        );
      } else {
        await txn.insert(
          'client_inputs',
          _inputsToRow(site.id, inputs),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> updateSiteBlocks(String siteId, List<String> blocks) async {
    await _db.transaction((txn) async {
      await txn.delete('blocks', where: 'site_id = ?', whereArgs: [siteId]);
      await _writeBlocks(txn, siteId, blocks);
    });
  }

  @override
  Future<void> saveClientInputs(String siteId, ClientInputs inputs) async {
    // Relies on the FK constraint to reject inputs for a non-existent site.
    await _db.insert(
      'client_inputs',
      _inputsToRow(siteId, inputs),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- Helpers --------------------------------------------------------------

  Future<void> _writeBlocks(
    DatabaseExecutor txn,
    String siteId,
    List<String> blocks,
  ) async {
    for (var i = 0; i < blocks.length; i++) {
      await txn.insert('blocks', {
        'site_id': siteId,
        'position': i,
        'label': blocks[i],
      });
    }
  }

  Future<Site> _hydrate(Map<String, Object?> siteRow) async {
    final id = siteRow['id']! as String;

    final blockRows = await _db.query(
      'blocks',
      columns: ['label'],
      where: 'site_id = ?',
      whereArgs: [id],
      orderBy: 'position',
    );
    final blocks = blockRows
        .map((r) => r['label']! as String)
        .toList(growable: false);

    final inputRows = await _db.query(
      'client_inputs',
      where: 'site_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final clientInputs = inputRows.isEmpty
        ? null
        : _inputsFromRow(inputRows.first);

    return Site(
      id: id,
      name: siteRow['name']! as String,
      blocks: blocks,
      clientInputs: clientInputs,
    );
  }

  // ---- Source points --------------------------------------------------------

  @override
  Future<List<SourcePoint>> getSourcePoints(String siteId) async {
    final rows = await _db.query(
      'source_points',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_sourcePointFromRow).toList(growable: false);
  }

  @override
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint) async {
    final stored = sourcePoint.copyWithId(_idService.newId());
    await _db.insert('source_points', _sourcePointToRow(stored));
    return stored;
  }

  @override
  Future<void> updateSourcePoint(SourcePoint sourcePoint) async {
    await _db.update(
      'source_points',
      _sourcePointToRow(sourcePoint),
      where: 'id = ?',
      whereArgs: [sourcePoint.id],
    );
  }

  @override
  Future<void> deleteSourcePoint(String id) async {
    await _db.delete('source_points', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Inlet points ---------------------------------------------------------

  @override
  Future<List<InletPoint>> getInletPoints(String siteId) async {
    final rows = await _db.query(
      'inlet_points',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_inletPointFromRow).toList(growable: false);
  }

  @override
  Future<InletPoint> addInletPoint(InletPoint inletPoint) async {
    final stored = inletPoint.copyWithId(_idService.newId());
    await _db.insert('inlet_points', _inletPointToRow(stored));
    return stored;
  }

  @override
  Future<void> updateInletPoint(InletPoint inletPoint) async {
    await _db.update(
      'inlet_points',
      _inletPointToRow(inletPoint),
      where: 'id = ?',
      whereArgs: [inletPoint.id],
    );
  }

  @override
  Future<void> deleteInletPoint(String id) async {
    await _db.delete('inlet_points', where: 'id = ?', whereArgs: [id]);
  }
}

// ---- Row <-> model mapping (hand-written, no codegen) -----------------------

Map<String, Object?> _inputsToRow(String siteId, ClientInputs i) {
  return {
    'site_id': siteId,
    'site_name': i.siteName,
    'information_source': i.informationSource?.name,
    'client_poc_name': i.clientPocName,
    'client_poc_contact': i.clientPocContact,
    'goal_of_installation': i.goalOfInstallation,
    'water_sources': i.waterSources.map((w) => w.name).join(','),
    'oht_hns': i.ohtHns?.name,
    'finalised_plumbing_drawings': _boolToInt(i.finalisedPlumbingDrawings),
    'points_identified': i.pointsIdentified,
    'max_and_continuous_pressure': i.maxAndContinuousPressure,
    'pressure_boosters': _boolToInt(i.pressureBoosters),
    'materials_and_brand_guidelines': i.materialsAndBrandGuidelines,
    'rework_required': _boolToInt(i.reworkRequired),
    'rework_details': i.reworkDetails,
    'age_of_plumbing_lines': i.ageOfPlumbingLines,
    'aesthetic_guidelines': _boolToInt(i.aestheticGuidelines),
    'aesthetic_details': i.aestheticDetails,
  };
}

ClientInputs _inputsFromRow(Map<String, Object?> r) {
  return ClientInputs(
    siteName: (r['site_name'] as String?) ?? '',
    informationSource: _enumByName(
      InformationSource.values,
      r['information_source'] as String?,
    ),
    clientPocName: (r['client_poc_name'] as String?) ?? '',
    clientPocContact: (r['client_poc_contact'] as String?) ?? '',
    goalOfInstallation: (r['goal_of_installation'] as String?) ?? '',
    waterSources: _parseWaterSources(r['water_sources'] as String?),
    ohtHns: _enumByName(OhtHns.values, r['oht_hns'] as String?),
    finalisedPlumbingDrawings: _intToBool(
      r['finalised_plumbing_drawings'] as int?,
    ),
    pointsIdentified: r['points_identified'] as int?,
    maxAndContinuousPressure: (r['max_and_continuous_pressure'] as String?) ?? '',
    pressureBoosters: _intToBool(r['pressure_boosters'] as int?),
    materialsAndBrandGuidelines:
        (r['materials_and_brand_guidelines'] as String?) ?? '',
    reworkRequired: _intToBool(r['rework_required'] as int?),
    reworkDetails: (r['rework_details'] as String?) ?? '',
    ageOfPlumbingLines: (r['age_of_plumbing_lines'] as String?) ?? '',
    aestheticGuidelines: _intToBool(r['aesthetic_guidelines'] as int?),
    aestheticDetails: (r['aesthetic_details'] as String?) ?? '',
  );
}

Set<WaterSource> _parseWaterSources(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final result = <WaterSource>{};
  for (final name in raw.split(',')) {
    final value = _enumByName(WaterSource.values, name);
    if (value != null) result.add(value);
  }
  return result;
}

int? _boolToInt(bool? v) => v == null ? null : (v ? 1 : 0);

bool? _intToBool(int? v) => v == null ? null : v != 0;

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Map<String, Object?> _sourcePointToRow(SourcePoint s) {
  return {
    'id': s.id,
    'site_id': s.siteId,
    'block': s.block,
    'apartment': s.apartment,
    'inlet_description': s.inletDescription,
    'sensor_size': s.sensorSize?.name,
    'sensor_od': s.sensorOd?.name,
    'pipe_size': s.pipeSize?.name,
    'pipe_type': s.pipeType?.name,
    'qty': s.qty,
    'sensor_type': s.sensorType?.name,
    'rework': _boolToInt(s.rework),
    'rework_details': s.reworkDetails,
    'flow_direction': s.flowDirection?.name,
    'clearance_10x': _boolToInt(s.clearance10x),
    'pipe_full': _boolToInt(s.pipeFull),
    'valve_downstream': _boolToInt(s.valveDownstream),
    'reducer_spec': _boolToInt(s.reducerSpec),
    'reducer_spec_details': s.reducerSpecDetails,
    'downstream_outlet_above_pipe_fig1': _boolToInt(
      s.downstreamOutletAbovePipeFig1,
    ),
    'air_vent_needed_fig2': _boolToInt(s.airVentNeededFig2),
    'reverse_flow': _boolToInt(s.reverseFlow),
    'distance_from_motor_pump_fig3': _boolToInt(s.distanceFromMotorPumpFig3),
    'no_flexible_pipe_within_20x': _boolToInt(s.noFlexiblePipeWithin20x),
    'max_and_continuous_pressure_bar': s.maxAndContinuousPressureBar,
    'strainer_screen_filter': _boolToInt(s.strainerScreenFilter),
    'chamber_installation': _boolToInt(s.chamberInstallation),
    'antenna_required': _boolToInt(s.antennaRequired),
    'transmitting_part_open_to_air': _boolToInt(s.transmittingPartOpenToAir),
    'nrv_feasibility': _boolToInt(s.nrvFeasibility),
  };
}

SourcePoint _sourcePointFromRow(Map<String, Object?> r) {
  return SourcePoint(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    block: r['block'] as String?,
    apartment: (r['apartment'] as String?) ?? '',
    inletDescription: (r['inlet_description'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorOd: _enumByName(SensorOd.values, r['sensor_od'] as String?),
    pipeSize: _enumByName(PipeSize.values, r['pipe_size'] as String?),
    pipeType: _enumByName(PipeType.values, r['pipe_type'] as String?),
    qty: r['qty'] as int?,
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    rework: _intToBool(r['rework'] as int?),
    reworkDetails: (r['rework_details'] as String?) ?? '',
    flowDirection: _enumByName(
      FlowDirection.values,
      r['flow_direction'] as String?,
    ),
    clearance10x: _intToBool(r['clearance_10x'] as int?),
    pipeFull: _intToBool(r['pipe_full'] as int?),
    valveDownstream: _intToBool(r['valve_downstream'] as int?),
    reducerSpec: _intToBool(r['reducer_spec'] as int?),
    reducerSpecDetails: (r['reducer_spec_details'] as String?) ?? '',
    downstreamOutletAbovePipeFig1: _intToBool(
      r['downstream_outlet_above_pipe_fig1'] as int?,
    ),
    airVentNeededFig2: _intToBool(r['air_vent_needed_fig2'] as int?),
    reverseFlow: _intToBool(r['reverse_flow'] as int?),
    distanceFromMotorPumpFig3: _intToBool(
      r['distance_from_motor_pump_fig3'] as int?,
    ),
    noFlexiblePipeWithin20x: _intToBool(
      r['no_flexible_pipe_within_20x'] as int?,
    ),
    maxAndContinuousPressureBar:
        (r['max_and_continuous_pressure_bar'] as num?)?.toDouble(),
    strainerScreenFilter: _intToBool(r['strainer_screen_filter'] as int?),
    chamberInstallation: _intToBool(r['chamber_installation'] as int?),
    antennaRequired: _intToBool(r['antenna_required'] as int?),
    transmittingPartOpenToAir: _intToBool(
      r['transmitting_part_open_to_air'] as int?,
    ),
    nrvFeasibility: _intToBool(r['nrv_feasibility'] as int?),
  );
}

Map<String, Object?> _inletPointToRow(InletPoint i) {
  return {
    'id': i.id,
    'site_id': i.siteId,
    'block': i.block,
    'apartment_bhk': i.apartmentBhk,
    'sensor_size': i.sensorSize?.name,
    'series': i.series,
    'sensor_od': i.sensorOd?.name,
    'pipe_size': i.pipeSize?.name,
    'pipe_type': i.pipeType?.name,
    'qty': i.qty,
    'sensor_type': i.sensorType?.name,
    'rework': _boolToInt(i.rework),
    'rework_details': i.reworkDetails,
    'linear_distance_clearance_10x': _boolToInt(i.linearDistanceClearance10x),
    'reverse_flow': _boolToInt(i.reverseFlow),
    'oht_hns': i.ohtHns?.name,
    'distance_from_motor_pump': _boolToInt(i.distanceFromMotorPump),
    'max_and_continuous_pressure_bar': i.maxAndContinuousPressureBar,
    'strainer_screen_filter': _boolToInt(i.strainerScreenFilter),
    'flow_direction': i.flowDirection?.name,
    'access_mode': i.accessMode?.name,
    'cable_run_length': i.cableRunLength?.name,
    'conduit_clamping': _boolToInt(i.conduitClamping),
    'civil_work_needed': _boolToInt(i.civilWorkNeeded),
    'civil_work_details': i.civilWorkDetails,
  };
}

InletPoint _inletPointFromRow(Map<String, Object?> r) {
  return InletPoint(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    block: r['block'] as String?,
    apartmentBhk: (r['apartment_bhk'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    series: (r['series'] as String?) ?? '',
    sensorOd: _enumByName(SensorOd.values, r['sensor_od'] as String?),
    pipeSize: _enumByName(PipeSize.values, r['pipe_size'] as String?),
    pipeType: _enumByName(PipeType.values, r['pipe_type'] as String?),
    qty: r['qty'] as int?,
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    rework: _intToBool(r['rework'] as int?),
    reworkDetails: (r['rework_details'] as String?) ?? '',
    linearDistanceClearance10x: _intToBool(
      r['linear_distance_clearance_10x'] as int?,
    ),
    reverseFlow: _intToBool(r['reverse_flow'] as int?),
    ohtHns: _enumByName(OhtHns.values, r['oht_hns'] as String?),
    distanceFromMotorPump: _intToBool(r['distance_from_motor_pump'] as int?),
    maxAndContinuousPressureBar:
        (r['max_and_continuous_pressure_bar'] as num?)?.toDouble(),
    strainerScreenFilter: _intToBool(r['strainer_screen_filter'] as int?),
    flowDirection: _enumByName(
      FlowDirection.values,
      r['flow_direction'] as String?,
    ),
    accessMode: _enumByName(AccessMode.values, r['access_mode'] as String?),
    cableRunLength: _enumByName(
      CableRunLength.values,
      r['cable_run_length'] as String?,
    ),
    conduitClamping: _intToBool(r['conduit_clamping'] as int?),
    civilWorkNeeded: _intToBool(r['civil_work_needed'] as int?),
    civilWorkDetails: (r['civil_work_details'] as String?) ?? '',
  );
}
