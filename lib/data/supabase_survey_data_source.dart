import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client_inputs.dart';
import '../models/site.dart';

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
