import 'package:sqflite/sqflite.dart';

import '../models/client_inputs.dart';
import '../models/site.dart';
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
