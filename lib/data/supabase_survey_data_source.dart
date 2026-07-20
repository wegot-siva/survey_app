import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bom_manual_edit_snapshot.dart';
import '../models/bom_manual_edit_snapshot_line.dart';
import '../models/bom_manual_entry.dart';
import '../models/bom_revision.dart';
import '../models/bom_revision_line.dart';
import '../models/bom_snapshot.dart';
import '../models/bom_snapshot_line.dart';
import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_audit_entry.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';

/// Remote (Supabase) reads/writes for survey data.
///
/// Push-only tables (bom_snapshots/bom_revisions and their line tables,
/// engineers, survey_assignment_audit): reachable only from the device that
/// authored them, deliberately deferred — see [SyncService] for why. Every
/// other table also has a pull (`fetchX`) — sites, client_inputs, footers,
/// source_points, inlet_points, duct_loras, gateways, bom_manual_entries,
/// plus Material Master (global reference data, pulled since the earliest
/// slice). A pulled row reaches every device, not just the one that entered
/// it, and a row deleted directly in Supabase is reconciled away locally too
/// — see [SqfliteSurveyRepository]'s pull-reconcile helper.
///
/// Upserts are idempotent — keyed by the same UUIDs used locally — so repeating
/// a sync converges to the same rows instead of duplicating them.
class SupabaseSurveyDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// Pushes one site's row and its blocks. Order matters: the site row must
  /// exist before blocks (which reference it via FK). Client inputs are
  /// pushed separately (see [pushClientInputs]) — they're dirty-tracked
  /// independently of the site row, so a site-only edit shouldn't force a
  /// redundant client_inputs push and vice versa.
  Future<void> pushSite(Site site) async {
    await _client.from('sites').upsert({
      'id': site.id,
      'name': site.name,
      // Reserved assignment columns — currently always null.
      'status': site.status,
      'assigned_to': site.assignedTo,
      'bom_locked': site.bomLocked,
    });

    // Blocks carry no stable id in the domain model, so replace the whole set
    // for this site: delete existing rows, then insert the current ordered list.
    await _client.from('blocks').delete().eq('site_id', site.id);
    if (site.blocks.isNotEmpty) {
      await _client.from('blocks').insert([
        for (var i = 0; i < site.blocks.length; i++)
          {'site_id': site.id, 'position': i, 'label': site.blocks[i]},
      ]);
    }
  }

  /// Upserts the Client inputs form for [siteId] (idempotent). The parent
  /// site must already have been pushed (FK).
  Future<void> pushClientInputs(String siteId, ClientInputs inputs) async {
    await _client
        .from('client_inputs')
        .upsert(_inputsToRemoteRow(siteId, inputs));
  }

  /// Upserts a source point by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushSourcePoint(SourcePoint sp) async {
    await _client.from('source_points').upsert(_sourcePointToRemoteRow(sp));
  }

  /// Deletes a source point by id (idempotent — a no-op if it was never
  /// pushed, or already deleted remotely).
  Future<void> deleteSourcePoint(String id) async {
    await _client.from('source_points').delete().eq('id', id);
  }

  /// Upserts an inlet point by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushInletPoint(InletPoint ip) async {
    await _client.from('inlet_points').upsert(_inletPointToRemoteRow(ip));
  }

  /// Deletes an inlet point by id (idempotent — a no-op if it was never
  /// pushed, or already deleted remotely).
  Future<void> deleteInletPoint(String id) async {
    await _client.from('inlet_points').delete().eq('id', id);
  }

  /// Upserts a Duct LoRa unit by its id (idempotent). Parent site must exist.
  Future<void> pushDuctLora(DuctLora d) async {
    await _client.from('duct_loras').upsert(_ductLoraToRemoteRow(d));
  }

  /// Deletes a Duct LoRa unit by id (idempotent — a no-op if it was never
  /// pushed, or already deleted remotely).
  Future<void> deleteDuctLora(String id) async {
    await _client.from('duct_loras').delete().eq('id', id);
  }

  /// Upserts a gateway by its id (idempotent). Parent site must exist.
  Future<void> pushGateway(Gateway g) async {
    await _client.from('gateways').upsert(_gatewayToRemoteRow(g));
  }

  /// Deletes a gateway by id (idempotent — a no-op if it was never pushed, or
  /// already deleted remotely).
  Future<void> deleteGateway(String id) async {
    await _client.from('gateways').delete().eq('id', id);
  }

  /// Upserts the per-site footer (idempotent, keyed by site_id). Parent site
  /// must exist.
  Future<void> pushFooter(String siteId, Footer f) async {
    await _client.from('footers').upsert(_footerToRemoteRow(siteId, f));
  }

  /// Upserts a Material Master row by its id (idempotent). Not site-scoped —
  /// no parent to push first.
  Future<void> pushMaterialMasterItem(MaterialMasterItem item) async {
    await _client
        .from('material_master_items')
        .upsert(_materialMasterItemToRemoteRow(item));
  }

  /// Deletes a Material Master row by id (idempotent — a no-op if it was
  /// never pushed, or already deleted remotely). Only called once
  /// [SurveyRepository.getPendingDeleteMaterialMasterItemIds] confirms the
  /// row is tombstoned locally.
  Future<void> deleteMaterialMasterItem(String id) async {
    await _client.from('material_master_items').delete().eq('id', id);
  }

  /// Fetches every Material Master row from Supabase — the pull half of
  /// Material Master's sync (see the class doc comment for why this table
  /// alone needs one). The caller merges these into local storage (including
  /// reconciling deletes — a row missing from this result is treated as
  /// deleted remotely), so this MUST return the complete table, never a
  /// partial page.
  ///
  /// Paginates explicitly via `.range()` rather than trusting a single
  /// `.select()` to return everything — PostgREST caps an unbounded request
  /// at a server-configured max-rows (commonly 1000), and the plumbing
  /// catalog import alone is expected to add ~1000 rows on top of what's
  /// already here. Advances by the actual row count received each page
  /// (not the nominal page size), so this stays correct even if the server
  /// enforces a smaller cap than requested; stops only on a genuinely empty
  /// page, so it can never mistake a capped page for the end of the table.
  Future<List<MaterialMasterItem>> fetchMaterialMasterItems() async {
    return (await _fetchAllRows(
      'material_master_items',
    )).map((r) => _materialMasterItemFromRemoteRow(r)).toList();
  }

  /// Fetches every row of [table], paginated the same way
  /// [fetchMaterialMasterItems] always has — see that method's doc for why
  /// pagination is explicit rather than trusted to a single `.select()`, and
  /// why the caller (here, [SurveyRepository]'s `upsertXFromRemote` methods)
  /// must always receive the complete table, never a partial page, before
  /// reconciling local deletes against it. Shared by every "Phase 1" pull —
  /// sites, client_inputs, footers, source_points, inlet_points, duct_loras,
  /// gateways, bom_manual_entries — returning raw rows rather than a typed
  /// model, since [SqfliteSurveyRepository]'s pull-reconcile helper only ever
  /// needs to write these columns straight into the matching local table
  /// (see its own doc for the one real conversion needed: Postgres booleans
  /// -> local SQLite 0/1).
  Future<List<Map<String, dynamic>>> _fetchAllRows(String table) async {
    const pageSize = 500;
    final all = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _client.from(table).select().range(offset, offset + pageSize - 1);
      if (page.isEmpty) break;
      all.addAll(page.map((r) => Map<String, dynamic>.from(r)));
      offset += page.length;
    }
    return all;
  }

  /// Every site row (id/name/status/assigned_to/bom_locked only — blocks and
  /// client_inputs are separate tables/pulls; archived/address/client_name/
  /// client_contact are Sales-only fields never pushed to Supabase in the
  /// first place, so they're simply absent from every remote row — see
  /// [SqfliteSurveyRepository]'s pull-reconcile helper for why that's safe).
  Future<List<Map<String, dynamic>>> fetchSites() => _fetchAllRows('sites');

  /// Every Client inputs row, keyed by site_id (not its own id).
  Future<List<Map<String, dynamic>>> fetchClientInputs() =>
      _fetchAllRows('client_inputs');

  /// Every Footer row, keyed by site_id (not its own id).
  Future<List<Map<String, dynamic>>> fetchFooters() => _fetchAllRows('footers');

  Future<List<Map<String, dynamic>>> fetchSourcePoints() =>
      _fetchAllRows('source_points');

  Future<List<Map<String, dynamic>>> fetchInletPoints() =>
      _fetchAllRows('inlet_points');

  Future<List<Map<String, dynamic>>> fetchDuctLoras() =>
      _fetchAllRows('duct_loras');

  Future<List<Map<String, dynamic>>> fetchGateways() => _fetchAllRows('gateways');

  Future<List<Map<String, dynamic>>> fetchBomManualEntries() =>
      _fetchAllRows('bom_manual_entries');

  /// Upserts a Material Master change-log entry by its id (idempotent). Not
  /// site-scoped, and not FK'd to the material row either (a delete's own
  /// audit entry must survive the row's removal).
  Future<void> pushMaterialMasterAuditEntry(
    MaterialMasterAuditEntry entry,
  ) async {
    await _client
        .from('material_master_audit')
        .upsert(_materialMasterAuditEntryToRemoteRow(entry));
  }

  /// Name of the Storage bucket holding survey photos. Must exist (see
  /// supabase/schema.sql) before uploads succeed.
  static const String photoBucket = 'survey-photos';

  /// Uploads a local photo file to Storage under [objectKey] (idempotent —
  /// re-uploading the same key overwrites). The key's naming convention is
  /// always `.jpg` (set by the caller) regardless of the file's real format —
  /// only the Content-Type header (derived here from the local file's actual
  /// extension) needs to match the bytes, e.g. for markup output (PNG).
  /// Returns the object key on success.
  Future<String> uploadPhoto(String localPath, String objectKey) async {
    await _client.storage
        .from(photoBucket)
        .upload(
          objectKey,
          File(localPath),
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeFor(localPath),
          ),
        );
    return objectKey;
  }

  /// Upserts a photo metadata row by its id (idempotent). The device-local
  /// file path is never pushed — only the Storage object key.
  Future<void> pushPhoto(SurveyPhoto photo) async {
    await _client.from('photos').upsert(_photoToRemoteRow(photo));
  }

  /// Upserts a BoM manual entry by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushBomManualEntry(BomManualEntry entry) async {
    await _client
        .from('bom_manual_entries')
        .upsert(_bomManualEntryToRemoteRow(entry));
  }

  /// Deletes a BoM manual entry by id (idempotent — a no-op if it was never
  /// pushed, or already deleted remotely).
  Future<void> deleteBomManualEntry(String id) async {
    await _client.from('bom_manual_entries').delete().eq('id', id);
  }

  /// Upserts a BoM snapshot by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushBomSnapshot(BomSnapshot snapshot) async {
    await _client.from('bom_snapshots').upsert(_bomSnapshotToRemoteRow(snapshot));
  }

  /// Upserts a BoM snapshot line by its id (idempotent). The parent snapshot
  /// must already have been pushed (FK).
  Future<void> pushBomSnapshotLine(BomSnapshotLine line) async {
    await _client
        .from('bom_snapshot_lines')
        .upsert(_bomSnapshotLineToRemoteRow(line));
  }

  /// Upserts a BoM revision by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushBomRevision(BomRevision revision) async {
    await _client.from('bom_revisions').upsert(_bomRevisionToRemoteRow(revision));
  }

  /// Upserts a BoM revision line by its id (idempotent). The parent revision
  /// must already have been pushed (FK).
  Future<void> pushBomRevisionLine(BomRevisionLine line) async {
    await _client
        .from('bom_revision_lines')
        .upsert(_bomRevisionLineToRemoteRow(line));
  }

  /// Upserts a BoM manual-edit snapshot by its id (idempotent). The parent
  /// site must already have been pushed (FK).
  Future<void> pushBomManualEditSnapshot(BomManualEditSnapshot s) async {
    await _client
        .from('bom_manual_edit_snapshots')
        .upsert(_bomManualEditSnapshotToRemoteRow(s));
  }

  /// Upserts a BoM manual-edit snapshot line by its id (idempotent). The
  /// parent snapshot must already have been pushed (FK).
  Future<void> pushBomManualEditSnapshotLine(
    BomManualEditSnapshotLine line,
  ) async {
    await _client
        .from('bom_manual_edit_snapshot_lines')
        .upsert(_bomManualEditSnapshotLineToRemoteRow(line));
  }
}

/// Maps client inputs to a Supabase row. Unlike SQLite, Postgres has a native
/// boolean type, so yes/no fields are sent as real booleans (null = unanswered).
Map<String, Object?> _inputsToRemoteRow(String siteId, ClientInputs i) {
  return {
    'site_id': siteId,
    'site_name': i.siteName,
    'information_source': i.informationSource?.name,
    'client_poc_name': i.clientPocName,
    'client_poc_contact': i.clientPocContact,
    'goal_of_installation': i.goalOfInstallation,
    'water_sources': i.waterSources.map((w) => w.name).join(','),
    'oht_hns': i.ohtHns?.name,
    'finalised_plumbing_drawings': i.finalisedPlumbingDrawings,
    'points_identified': i.pointsIdentified,
    'max_and_continuous_pressure': i.maxAndContinuousPressure,
    'pressure_boosters': i.pressureBoosters,
    'materials_and_brand_guidelines': i.materialsAndBrandGuidelines,
    'rework_required': i.reworkRequired,
    'rework_details': i.reworkDetails,
    'age_of_plumbing_lines': i.ageOfPlumbingLines,
    'aesthetic_guidelines': i.aestheticGuidelines,
    'aesthetic_details': i.aestheticDetails,
  };
}

Map<String, Object?> _sourcePointToRemoteRow(SourcePoint s) {
  return {
    'id': s.id,
    'site_id': s.siteId,
    'block': s.block,
    'apartment': s.apartment,
    'inlet_description': s.inletDescription,
    'material_id': s.materialId,
    'sensor_size': s.sensorSize?.name,
    'sensor_od': s.sensorOd?.name,
    'pipe_size': s.pipeSize?.name,
    'pipe_type': s.pipeType?.name,
    'qty': s.qty,
    'sensor_type': s.sensorType?.name,
    'rework': s.rework,
    'rework_details': s.reworkDetails,
    'flow_direction': s.flowDirection?.name,
    'clearance_10x': s.clearance10x,
    'pipe_full': s.pipeFull,
    'valve_downstream': s.valveDownstream,
    'reducer_spec': s.reducerSpec,
    'reducer_spec_details': s.reducerSpecDetails,
    'downstream_outlet_above_pipe_fig1': s.downstreamOutletAbovePipeFig1,
    'air_vent_needed_fig2': s.airVentNeededFig2,
    'reverse_flow': s.reverseFlow,
    'distance_from_motor_pump_fig3': s.distanceFromMotorPumpFig3,
    'no_flexible_pipe_within_20x': s.noFlexiblePipeWithin20x,
    'max_and_continuous_pressure_bar': s.maxAndContinuousPressureBar,
    'strainer_screen_filter': s.strainerScreenFilter,
    'chamber_installation': s.chamberInstallation,
    'antenna_required': s.antennaRequired,
    'transmitting_part_open_to_air': s.transmittingPartOpenToAir,
    'nrv_feasibility': s.nrvFeasibility,
  };
}

Map<String, Object?> _inletPointToRemoteRow(InletPoint i) {
  return {
    'id': i.id,
    'site_id': i.siteId,
    'block': i.block,
    'apartment_bhk': i.apartmentBhk,
    'material_id': i.materialId,
    'sensor_size': i.sensorSize?.name,
    'series': i.series,
    'sensor_od': i.sensorOd?.name,
    'pipe_size': i.pipeSize?.name,
    'pipe_type': i.pipeType?.name,
    'qty': i.qty,
    'sensor_type': i.sensorType?.name,
    'rework': i.rework,
    'rework_details': i.reworkDetails,
    'linear_distance_clearance_10x': i.linearDistanceClearance10x,
    'reverse_flow': i.reverseFlow,
    'oht_hns': i.ohtHns?.name,
    'distance_from_motor_pump': i.distanceFromMotorPump,
    'max_and_continuous_pressure_bar': i.maxAndContinuousPressureBar,
    'strainer_screen_filter': i.strainerScreenFilter,
    'flow_direction': i.flowDirection?.name,
    'access_mode': i.accessMode?.name,
    'cable_run_length': i.cableRunLength?.name,
    'conduit_clamping': i.conduitClamping,
    'civil_work_needed': i.civilWorkNeeded,
    'civil_work_details': i.civilWorkDetails,
  };
}

Map<String, Object?> _ductLoraToRemoteRow(DuctLora d) {
  return {
    'id': d.id,
    'site_id': d.siteId,
    'block': d.block,
    // Comma-separated set, mirroring the local store and client_inputs.
    'series_served': d.seriesServed.join(','),
    'accessible_for_service': d.accessibleForService,
    'rssi_if_tcl': d.rssiIfTcl,
    'power_point_available_shielded': d.powerPointAvailableShielded,
    'separate_mcb_for_series': d.separateMcbForSeries,
    'ups_power_supply': d.upsPowerSupply,
    'cable_length': d.cableLength,
  };
}

Map<String, Object?> _gatewayToRemoteRow(Gateway g) {
  return {
    'id': g.id,
    'site_id': g.siteId,
    'placement': g.placement?.name,
    'location_description': g.locationDescription,
    'blocks_covered': g.blocksCovered.join(','),
    'quantity': g.quantity,
    'uplink_type': g.uplinkType?.name,
    'wifi_interference_check': g.wifiInterferenceCheck,
    'wifi_interference_details': g.wifiInterferenceDetails,
    'sim_coverage': g.simCoverage?.name,
    'uninterrupted_power_source': g.uninterruptedPowerSource,
    'mounting_hardware_needed': g.mountingHardwareNeeded,
  };
}

Map<String, Object?> _footerToRemoteRow(String siteId, Footer f) {
  return {
    'site_id': siteId,
    'tds_ppm': f.tdsPpm,
    'tss_ppm': f.tssPpm,
    'tcl_service': f.tclService,
    'tcl_service_details': f.tclServiceDetails,
    'general_remarks': f.generalRemarks,
    'survey_date': f.surveyDate?.toIso8601String(),
    'surveyor_name': f.surveyorName,
  };
}

Map<String, Object?> _photoToRemoteRow(SurveyPhoto p) {
  return {
    'id': p.id,
    'owner_type': p.ownerType,
    'owner_id': p.ownerId,
    'slot': p.slot,
    'position': p.position,
    // Local path is device-specific and never pushed.
    'remote_path': p.remotePath,
  };
}

/// Content-Type for an upload, derived from the local file's real extension.
/// Camera captures are `.jpg`; markup output is `.png` — defaults to JPEG for
/// anything else.
String _contentTypeFor(String localPath) {
  switch (p.extension(localPath).toLowerCase()) {
    case '.png':
      return 'image/png';
    default:
      return 'image/jpeg';
  }
}

Map<String, Object?> _materialMasterItemToRemoteRow(MaterialMasterItem m) {
  return {
    'id': m.id,
    'group_code': m.group.name,
    'material_name': m.materialName,
    'sku': m.sku,
    'item_label': m.itemLabel,
    'unit': m.unit,
    'behavior_type': m.behaviorType.name,
    'sensor_size': m.sensorSize?.name,
    'sensor_type': m.sensorType?.name,
    'quantity_per_sensor': m.quantityPerSensor,
    'derived_formula': m.derivedFormula?.name,
    'formula_divisor': m.formulaDivisor,
    'variable_source': m.variableSource?.name,
    'notes': m.notes,
    'material_type': m.materialType,
    'category': m.category,
    'variant': m.variant,
    'size_mm': m.sizeMm,
    'size_display': m.sizeDisplay,
  };
}

MaterialMasterItem _materialMasterItemFromRemoteRow(Map<String, dynamic> r) {
  return MaterialMasterItem(
    id: r['id'] as String,
    group: _materialGroupFromRemoteCode(r['group_code'] as String?),
    materialName: (r['material_name'] as String?) ?? '',
    sku: (r['sku'] as String?) ?? '',
    itemLabel: (r['item_label'] as String?) ?? '',
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
    materialType: r['material_type'] as String?,
    category: r['category'] as String?,
    variant: r['variant'] as String?,
    sizeMm: (r['size_mm'] as num?)?.toDouble(),
    sizeDisplay: r['size_display'] as String?,
  );
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Resolves a Supabase material_master_items.group_code value to its
/// [MaterialGroup]. This table's own convention (every row this app itself
/// writes) is the lowercase enum identifier, e.g. 'c' — but a bulk SQL
/// import (the plumbing catalog) instead used the uppercase display letter,
/// e.g. 'C', for every row. `_enumByName`'s exact, case-sensitive match
/// against `.name` silently missed all of those and fell back to A, so
/// this accepts either form, matched case-insensitively, before falling
/// back. Falls back to A only when truly unrecognized — same default
/// [_enumByName] already used here.
MaterialGroup _materialGroupFromRemoteCode(String? code) {
  if (code == null) return MaterialGroup.a;
  final normalized = code.toLowerCase();
  for (final group in MaterialGroup.values) {
    if (group.name == normalized || group.code.toLowerCase() == normalized) {
      return group;
    }
  }
  return MaterialGroup.a;
}

Map<String, Object?> _materialMasterAuditEntryToRemoteRow(
  MaterialMasterAuditEntry e,
) {
  return {
    'id': e.id,
    'material_row_id': e.materialRowId,
    'field_changed': e.fieldChanged,
    'old_value': e.oldValue,
    'new_value': e.newValue,
    'changed_by_role': e.changedByRole,
    'changed_at': e.changedAt.toIso8601String(),
  };
}

Map<String, Object?> _bomManualEntryToRemoteRow(BomManualEntry e) {
  return {
    'id': e.id,
    'survey_id': e.surveyId,
    'material_name': e.materialName,
    'sku': e.sku,
    'item_label': e.itemLabel,
    'sensor_size': e.sensorSize?.name,
    'sensor_type': e.sensorType?.name,
    'unit': e.unit,
    'qty': e.qty,
    // Literal 'D' / 'E' / 'G' — see the matching comment in
    // sqflite_survey_repository.dart's _bomManualEntryToRow.
    'group_code': e.group.code,
    'added_by': e.addedBy,
    'added_at': e.addedAt.toIso8601String(),
  };
}

Map<String, Object?> _bomSnapshotToRemoteRow(BomSnapshot s) {
  return {
    'id': s.id,
    'survey_id': s.surveyId,
    'version': s.version,
    'status': s.status,
    'finalized_by': s.finalizedBy,
    'finalized_at': s.finalizedAt.toIso8601String(),
  };
}

Map<String, Object?> _bomSnapshotLineToRemoteRow(BomSnapshotLine l) {
  return {
    'id': l.id,
    'snapshot_id': l.snapshotId,
    'sku': l.sku,
    'item': l.item,
    'material_name': l.materialName,
    'item_label': l.itemLabel,
    'sensor_size': l.sensorSize?.name,
    'sensor_type': l.sensorType?.name,
    'unit': l.unit,
    'qty': l.qty,
    // Literal 'A'..'G' — see the matching comment in
    // sqflite_survey_repository.dart's _bomSnapshotLineToRow.
    'group_code': l.group.code,
    'source': l.source.name, // literal 'auto' | 'manual'
  };
}

Map<String, Object?> _bomRevisionToRemoteRow(BomRevision v) {
  return {
    'id': v.id,
    'survey_id': v.surveyId,
    'version': v.version,
    'reason': v.reason,
    'created_by': v.createdBy,
    'created_at': v.createdAt.toIso8601String(),
  };
}

Map<String, Object?> _bomRevisionLineToRemoteRow(BomRevisionLine l) {
  return {
    'id': l.id,
    'revision_id': l.revisionId,
    'sku': l.sku,
    'item': l.item,
    'material_name': l.materialName,
    'item_label': l.itemLabel,
    'sensor_size': l.sensorSize?.name,
    'sensor_type': l.sensorType?.name,
    'unit': l.unit,
    'qty_delta': l.qtyDelta,
    // Literal 'A'..'G' — see the matching comment in
    // sqflite_survey_repository.dart's _bomRevisionLineToRow.
    'group_code': l.group.code,
  };
}

Map<String, Object?> _bomManualEditSnapshotToRemoteRow(
  BomManualEditSnapshot s,
) {
  return {
    'id': s.id,
    'survey_id': s.surveyId,
    'version': s.version,
    'based_on_version': s.basedOnVersion,
    'edited_by': s.editedBy,
    'edited_at': s.editedAt.toIso8601String(),
    'reason': s.reason,
  };
}

Map<String, Object?> _bomManualEditSnapshotLineToRemoteRow(
  BomManualEditSnapshotLine l,
) {
  return {
    'id': l.id,
    'snapshot_id': l.snapshotId,
    'sku': l.sku,
    'item_name': l.itemName,
    'description': l.description,
    'unit': l.unit,
    'qty': l.qty,
    'group_code': l.group.code,
  };
}
