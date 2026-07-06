import 'package:sqflite/sqflite.dart';

import 'material_master_seed_data.dart';

/// DEV-ONLY: seeds `material_master_items` with a fixed, disposable dataset.
/// Called exactly once, from [AppDatabase]'s `onCreate` (fresh installs
/// only) — never from `onUpgrade`, so an existing local database is never
/// touched by this. Each row is also individually guarded with
/// [ConflictAlgorithm.ignore], keyed by its (fixed) id, so calling this a
/// second time by mistake can never create duplicates.
///
/// Row encoding intentionally duplicates (rather than imports)
/// `sqflite_survey_repository.dart`'s row mapping, so this seed stays fully
/// self-contained — deleting this file, `material_master_seed_data.dart`,
/// and the one call site in `app_database.dart` removes it completely with
/// no other code to touch.
///
/// DELETE all three once real production Material Master data replaces this
/// placeholder set — see `material_master_seed_data.dart` for the full
/// data-quality notes on what's seeded and why.
Future<void> seedMaterialMasterItems(Database db) async {
  await db.transaction((txn) async {
    for (final item in kMaterialMasterSeedData) {
      await txn.insert(
        'material_master_items',
        {
          'id': item.id,
          'group_code': item.group.name,
          'material_name': item.materialName,
          'sku': item.sku,
          'unit': item.unit,
          'behavior_type': item.behaviorType.name,
          'sensor_size': item.sensorSize?.name,
          'sensor_type': item.sensorType?.name,
          'quantity_per_sensor': item.quantityPerSensor,
          'derived_formula': item.derivedFormula?.name,
          'formula_divisor': item.formulaDivisor,
          'variable_source': item.variableSource?.name,
          'notes': item.notes,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  });
}
