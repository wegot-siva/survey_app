import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_inputs.dart';
import '../models/inlet_point.dart';
import '../models/site.dart';
import '../models/source_point.dart';

/// Remote (Supabase) writes for survey data. Push-only for now.
///
/// Upserts are idempotent — keyed by the same UUIDs used locally — so repeating
/// a sync converges to the same rows instead of duplicating them.
class SupabaseSurveyDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// Pushes one site and its children. Order matters: the site row must exist
  /// before blocks / client_inputs (which reference it via FK).
  Future<void> pushSite(Site site) async {
    await _client.from('sites').upsert({'id': site.id, 'name': site.name});

    // Blocks carry no stable id in the domain model, so replace the whole set
    // for this site: delete existing rows, then insert the current ordered list.
    await _client.from('blocks').delete().eq('site_id', site.id);
    if (site.blocks.isNotEmpty) {
      await _client.from('blocks').insert([
        for (var i = 0; i < site.blocks.length; i++)
          {'site_id': site.id, 'position': i, 'label': site.blocks[i]},
      ]);
    }

    final inputs = site.clientInputs;
    if (inputs != null) {
      await _client
          .from('client_inputs')
          .upsert(_inputsToRemoteRow(site.id, inputs));
    }
  }

  /// Upserts a source point by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushSourcePoint(SourcePoint sp) async {
    await _client.from('source_points').upsert(_sourcePointToRemoteRow(sp));
  }

  /// Upserts an inlet point by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushInletPoint(InletPoint ip) async {
    await _client.from('inlet_points').upsert(_inletPointToRemoteRow(ip));
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
