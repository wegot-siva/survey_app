import 'package:sqflite/sqflite.dart';

import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
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
        {'name': site.name, 'status': site.status, 'assigned_to': site.assignedTo},
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
      status: siteRow['status'] as String?,
      assignedTo: siteRow['assigned_to'] as String?,
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

  // ---- Duct LoRa units ------------------------------------------------------

  @override
  Future<List<DuctLora>> getDuctLoras(String siteId) async {
    final rows = await _db.query(
      'duct_loras',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_ductLoraFromRow).toList(growable: false);
  }

  @override
  Future<DuctLora> addDuctLora(DuctLora ductLora) async {
    final stored = ductLora.copyWithId(_idService.newId());
    await _db.insert('duct_loras', _ductLoraToRow(stored));
    return stored;
  }

  @override
  Future<void> updateDuctLora(DuctLora ductLora) async {
    await _db.update(
      'duct_loras',
      _ductLoraToRow(ductLora),
      where: 'id = ?',
      whereArgs: [ductLora.id],
    );
  }

  @override
  Future<void> deleteDuctLora(String id) async {
    await _db.delete('duct_loras', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Gateways -------------------------------------------------------------

  @override
  Future<List<Gateway>> getGateways(String siteId) async {
    final rows = await _db.query(
      'gateways',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_gatewayFromRow).toList(growable: false);
  }

  @override
  Future<Gateway> addGateway(Gateway gateway) async {
    final stored = gateway.copyWithId(_idService.newId());
    await _db.insert('gateways', _gatewayToRow(stored));
    return stored;
  }

  @override
  Future<void> updateGateway(Gateway gateway) async {
    await _db.update(
      'gateways',
      _gatewayToRow(gateway),
      where: 'id = ?',
      whereArgs: [gateway.id],
    );
  }

  @override
  Future<void> deleteGateway(String id) async {
    await _db.delete('gateways', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Footer (one per site) ------------------------------------------------

  @override
  Future<Footer?> getFooter(String siteId) async {
    final rows = await _db.query(
      'footers',
      where: 'site_id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _footerFromRow(rows.first);
  }

  @override
  Future<void> saveFooter(String siteId, Footer footer) async {
    // Relies on the FK constraint to reject a footer for a non-existent site.
    await _db.insert(
      'footers',
      _footerToRow(siteId, footer),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- Material Master --------------------------------------------------

  @override
  Future<List<MaterialMasterItem>> getMaterialMasterItems() async {
    final rows = await _db.query('material_master_items', orderBy: 'rowid');
    return rows.map(_materialMasterItemFromRow).toList(growable: false);
  }

  @override
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item,
  ) async {
    final stored = item.copyWithId(_idService.newId());
    await _db.insert('material_master_items', _materialMasterItemToRow(stored));
    return stored;
  }

  @override
  Future<void> updateMaterialMasterItem(MaterialMasterItem item) async {
    await _db.update(
      'material_master_items',
      _materialMasterItemToRow(item),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  @override
  Future<void> deleteMaterialMasterItem(String id) async {
    await _db.delete('material_master_items', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Photos (polymorphic, slot-based) -------------------------------------

  @override
  Future<List<SurveyPhoto>> getPhotos(String ownerType, String ownerId) async {
    final rows = await _db.query(
      'photos',
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'slot, position, rowid',
    );
    return rows.map(_photoFromRow).toList(growable: false);
  }

  @override
  Future<void> setPhotos(
    String ownerType,
    String ownerId,
    List<SurveyPhoto> photos,
  ) async {
    await _db.transaction((txn) async {
      final keepIds = photos
          .where((p) => p.id.isNotEmpty)
          .map((p) => p.id)
          .toList();
      // Delete any existing rows for this owner that aren't in the kept set.
      final placeholders = List.filled(keepIds.length, '?').join(', ');
      await txn.delete(
        'photos',
        where: keepIds.isEmpty
            ? 'owner_type = ? AND owner_id = ?'
            : 'owner_type = ? AND owner_id = ? AND id NOT IN ($placeholders)',
        whereArgs: [ownerType, ownerId, ...keepIds],
      );
      for (final photo in photos) {
        if (photo.id.isEmpty) {
          await txn.insert(
            'photos',
            _photoToRow(photo.copyWithId(_idService.newId())),
          );
        } else {
          await txn.update(
            'photos',
            _photoToRow(photo),
            where: 'id = ?',
            whereArgs: [photo.id],
          );
        }
      }
    });
  }

  @override
  Future<List<SurveyPhoto>> getAllPhotos() async {
    final rows = await _db.query('photos', orderBy: 'rowid');
    return rows.map(_photoFromRow).toList(growable: false);
  }

  @override
  Future<void> updatePhoto(SurveyPhoto photo) async {
    await _db.update(
      'photos',
      _photoToRow(photo),
      where: 'id = ?',
      whereArgs: [photo.id],
    );
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

/// Free-text string sets are stored comma-separated (mirrors water_sources).
/// Assumes the member labels (block names, series tokens) contain no commas.
String _joinStrings(Set<String> values) => values.join(',');

Set<String> _splitStrings(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  return raw.split(',').where((s) => s.isNotEmpty).toSet();
}

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

Map<String, Object?> _ductLoraToRow(DuctLora d) {
  return {
    'id': d.id,
    'site_id': d.siteId,
    'block': d.block,
    'series_served': _joinStrings(d.seriesServed),
    'accessible_for_service': _boolToInt(d.accessibleForService),
    'rssi_if_tcl': d.rssiIfTcl,
    'power_point_available_shielded': _boolToInt(d.powerPointAvailableShielded),
    'separate_mcb_for_series': _boolToInt(d.separateMcbForSeries),
    'ups_power_supply': _boolToInt(d.upsPowerSupply),
    'cable_length': d.cableLength,
    'placement_photo_local_path': d.placementPhotoLocalPath,
    'placement_photo_remote_path': d.placementPhotoRemotePath,
  };
}

DuctLora _ductLoraFromRow(Map<String, Object?> r) {
  return DuctLora(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    block: r['block'] as String?,
    seriesServed: _splitStrings(r['series_served'] as String?),
    accessibleForService: _intToBool(r['accessible_for_service'] as int?),
    rssiIfTcl: (r['rssi_if_tcl'] as num?)?.toDouble(),
    powerPointAvailableShielded: _intToBool(
      r['power_point_available_shielded'] as int?,
    ),
    separateMcbForSeries: _intToBool(r['separate_mcb_for_series'] as int?),
    upsPowerSupply: _intToBool(r['ups_power_supply'] as int?),
    cableLength: (r['cable_length'] as num?)?.toDouble(),
    placementPhotoLocalPath: r['placement_photo_local_path'] as String?,
    placementPhotoRemotePath: r['placement_photo_remote_path'] as String?,
  );
}

Map<String, Object?> _gatewayToRow(Gateway g) {
  return {
    'id': g.id,
    'site_id': g.siteId,
    'placement': g.placement?.name,
    'location_description': g.locationDescription,
    'blocks_covered': _joinStrings(g.blocksCovered),
    'quantity': g.quantity,
    'uplink_type': g.uplinkType?.name,
    'wifi_interference_check': _boolToInt(g.wifiInterferenceCheck),
    'wifi_interference_details': g.wifiInterferenceDetails,
    'sim_coverage': g.simCoverage?.name,
    'uninterrupted_power_source': _boolToInt(g.uninterruptedPowerSource),
    'mounting_hardware_needed': g.mountingHardwareNeeded,
  };
}

Gateway _gatewayFromRow(Map<String, Object?> r) {
  return Gateway(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    placement: _enumByName(GatewayPlacement.values, r['placement'] as String?),
    locationDescription: (r['location_description'] as String?) ?? '',
    blocksCovered: _splitStrings(r['blocks_covered'] as String?),
    quantity: r['quantity'] as int?,
    uplinkType: _enumByName(UplinkType.values, r['uplink_type'] as String?),
    wifiInterferenceCheck: _intToBool(r['wifi_interference_check'] as int?),
    wifiInterferenceDetails: (r['wifi_interference_details'] as String?) ?? '',
    simCoverage: _enumByName(SimCoverage.values, r['sim_coverage'] as String?),
    uninterruptedPowerSource: _intToBool(
      r['uninterrupted_power_source'] as int?,
    ),
    mountingHardwareNeeded: (r['mounting_hardware_needed'] as String?) ?? '',
  );
}

Map<String, Object?> _footerToRow(String siteId, Footer f) {
  return {
    'site_id': siteId,
    'tds_ppm': f.tdsPpm,
    'tss_ppm': f.tssPpm,
    'tcl_service': _boolToInt(f.tclService),
    'tcl_service_details': f.tclServiceDetails,
    'general_remarks': f.generalRemarks,
    'survey_date': f.surveyDate?.toIso8601String(),
    'surveyor_name': f.surveyorName,
  };
}

Footer _footerFromRow(Map<String, Object?> r) {
  return Footer(
    tdsPpm: (r['tds_ppm'] as num?)?.toDouble(),
    tssPpm: (r['tss_ppm'] as num?)?.toDouble(),
    tclService: _intToBool(r['tcl_service'] as int?),
    tclServiceDetails: (r['tcl_service_details'] as String?) ?? '',
    generalRemarks: (r['general_remarks'] as String?) ?? '',
    surveyDate: DateTime.tryParse((r['survey_date'] as String?) ?? ''),
    surveyorName: (r['surveyor_name'] as String?) ?? '',
  );
}

Map<String, Object?> _materialMasterItemToRow(MaterialMasterItem m) {
  return {
    'id': m.id,
    'group_code': m.group.name,
    'material_name': m.materialName,
    'unit': m.unit,
    'behavior_type': m.behaviorType.name,
    'sensor_size': m.sensorSize?.name,
    'sensor_type': m.sensorType?.name,
    'quantity_per_sensor': m.quantityPerSensor,
    'derived_formula': m.derivedFormula?.name,
    'formula_divisor': m.formulaDivisor,
    'variable_source': m.variableSource?.name,
    'notes': m.notes,
  };
}

MaterialMasterItem _materialMasterItemFromRow(Map<String, Object?> r) {
  return MaterialMasterItem(
    id: r['id']! as String,
    group:
        _enumByName(MaterialGroup.values, r['group_code'] as String?) ??
        MaterialGroup.a,
    materialName: (r['material_name'] as String?) ?? '',
    unit: (r['unit'] as String?) ?? '',
    behaviorType:
        _enumByName(MaterialBehaviorType.values, r['behavior_type'] as String?) ??
        MaterialBehaviorType.fixed,
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    quantityPerSensor: (r['quantity_per_sensor'] as num?)?.toDouble() ?? 0,
    derivedFormula: _enumByName(
      DerivedFormula.values,
      r['derived_formula'] as String?,
    ),
    formulaDivisor: (r['formula_divisor'] as num?)?.toDouble(),
    variableSource: _enumByName(
      VariableSource.values,
      r['variable_source'] as String?,
    ),
    notes: (r['notes'] as String?) ?? '',
  );
}

Map<String, Object?> _photoToRow(SurveyPhoto p) {
  return {
    'id': p.id,
    'owner_type': p.ownerType,
    'owner_id': p.ownerId,
    'slot': p.slot,
    'position': p.position,
    'local_path': p.localPath,
    'remote_path': p.remotePath,
  };
}

SurveyPhoto _photoFromRow(Map<String, Object?> r) {
  return SurveyPhoto(
    id: r['id']! as String,
    ownerType: r['owner_type']! as String,
    ownerId: r['owner_id']! as String,
    slot: r['slot']! as String,
    position: (r['position'] as int?) ?? 0,
    localPath: r['local_path'] as String?,
    remotePath: r['remote_path'] as String?,
  );
}
