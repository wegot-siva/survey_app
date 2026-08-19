// An unrecognised material group_code must never become Group A.
//
// Group A is the only automatically-calculated group: the BoM engine builds
// its candidate set from every Group A material and resolves each survey
// point's materialId against it, so a row landing in A can put real
// quantities on a customer-facing BoM. Every other group is manual, where an
// unrecognised row shows up as a visible line instead of a wrong number and
// any point referencing it is reported unresolved — the loud signal wanted.
//
// The old parsers returned MaterialGroup.a for anything they could not
// resolve, on both the remote pull and the local read, with nothing logged.
// A typo, or a group code added to the catalog that this app build predates,
// would silently join the automatic quantities.
//
// The row is deliberately KEPT rather than skipped. Dropping it during the
// pull would remove it from the list handed to
// upsertMaterialMasterItemsFromRemote, whose reconcile treats absence from a
// complete fetch as "deleted remotely" and hard-deletes the local row —
// firing source_points.material_id's ON DELETE SET NULL and wiping the
// sensor selection off every point referencing it. That is exactly the Group
// A data-loss bug of commit 1e648ca, so skipping would reintroduce it.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/models/survey_options.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE material_master_items (
        id TEXT PRIMARY KEY, group_code TEXT NOT NULL, material_name TEXT NOT NULL,
        sku TEXT, item_label TEXT, unit TEXT NOT NULL, behavior_type TEXT NOT NULL,
        sensor_size TEXT, sensor_type TEXT, quantity_per_sensor REAL,
        derived_formula TEXT, formula_divisor REAL, variable_source TEXT,
        notes TEXT, material_type TEXT, category TEXT, variant TEXT,
        size_mm TEXT, size_display TEXT, deleted_at TEXT,
        pending_delete INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE material_master_audit (
        id TEXT PRIMARY KEY, material_row_id TEXT NOT NULL,
        field_changed TEXT NOT NULL, old_value TEXT, new_value TEXT,
        changed_by_role TEXT NOT NULL, changed_by_user_id TEXT,
        changed_at TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1
      )
    ''');
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  Future<MaterialMasterItem> readBackWithGroupCode(String? code) async {
    await db.insert('material_master_items', {
      'id': 'mat-1',
      'group_code': code,
      'material_name': 'Mystery Widget',
      'unit': 'pcs',
      'behavior_type': 'MANUAL',
      'quantity_per_sensor': 1.0,
      'dirty': 0,
    });
    final items = await repo.getMaterialMasterItems();
    return items.single;
  }

  test('an unrecognised group code does NOT resolve to Group A', () async {
    final item = await readBackWithGroupCode('H');

    expect(item.group, isNot(MaterialGroup.a),
        reason: 'Group A is the auto-calculated group — an unknown code '
            'landing there can put wrong quantities on a real BoM');
    expect(item.group, kUnknownMaterialGroupFallback);
  });

  test('a lowercase typo does not resolve to Group A either', () async {
    final item = await readBackWithGroupCode('zz');
    expect(item.group, isNot(MaterialGroup.a));
  });

  test('the row is KEPT, not dropped — dropping it would let the catalog '
      'reconcile hard-delete it and null every referencing point', () async {
    final item = await readBackWithGroupCode('H');

    expect(item.id, 'mat-1');
    expect(item.materialName, 'Mystery Widget',
        reason: 'every other field must survive an unknown group code');
    expect(await db.query('material_master_items'), hasLength(1));
  });

  group('no regression for codes the live catalog actually uses', () {
    // The 230 live rows carry uppercase display letters (A,B,C,E,F); rows
    // this app writes itself carry the lowercase enum name. Both forms must
    // keep resolving exactly as before.
    for (final entry in {
      'A': MaterialGroup.a,
      'B': MaterialGroup.b,
      'C': MaterialGroup.c,
      'D': MaterialGroup.d,
      'E': MaterialGroup.e,
      'F': MaterialGroup.f,
      'G': MaterialGroup.g,
      'a': MaterialGroup.a,
      'c': MaterialGroup.c,
      'g': MaterialGroup.g,
    }.entries) {
      test('"${entry.key}" still resolves to ${entry.value.name}', () async {
        final item = await readBackWithGroupCode(entry.key);
        expect(item.group, entry.value);
      });
    }
  });

  test('Group A rows still resolve to A — the auto path is untouched',
      () async {
    final item = await readBackWithGroupCode('A');

    expect(item.group, MaterialGroup.a);
    expect(item.quantityPerSensor, 1.0);
    // behavior_type 'MANUAL' matches no enum member and still falls back to
    // fixed. Deliberately unchanged: all 230 live rows carry it, Group A is
    // computed by materialId match rather than behaviour, and Group A rows
    // carry quantity_per_sensor = 1 while the rest carry 0 — so the fallback
    // is accidentally correct and "fixing" it would change live BoM output.
    expect(item.behaviorType, MaterialBehaviorType.fixed);
  });

  test('an unknown group code leaves sensor fields alone', () async {
    await db.insert('material_master_items', {
      'id': 'mat-2',
      'group_code': 'H',
      'material_name': 'Mystery Sensor',
      'unit': 'pcs',
      'behavior_type': 'MANUAL',
      'quantity_per_sensor': 0.0,
      'sensor_size': SensorSize.dn32.name,
      'sensor_type': SensorType.wired.name,
      'dirty': 0,
    });
    final item = (await repo.getMaterialMasterItems())
        .firstWhere((i) => i.id == 'mat-2');

    expect(item.sensorSize, SensorSize.dn32);
    expect(item.sensorType, SensorType.wired);
  });
}
