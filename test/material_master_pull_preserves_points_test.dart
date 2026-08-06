// A Material Master pull must never disturb the survey data that references
// it.
//
// This is the regression guard for the "Group A material disappears after
// reopening" bug. upsertMaterialMasterItemsFromRemote used to write each
// catalog row with ConflictAlgorithm.replace. SQLite implements INSERT OR
// REPLACE as DELETE-then-INSERT, and with `PRAGMA foreign_keys = ON` that
// DELETE fired source_points.material_id's ON DELETE SET NULL — so every
// sync silently wiped the sensor selection off every point, which was then
// pushed back up as null and propagated to every other device.
//
// The symptom was badly misleading: the selection survived any number of
// reopens and showed correctly in the BoM, and only vanished once a sync
// ran. That is why these tests run the pull explicitly rather than testing
// save/reopen — reopen was never the broken part.
//
// Two details matter for this file to test anything at all:
//   * foreign_keys must be ON, matching app_database.dart's onConfigure —
//     without it no FK action fires and the bug is invisible.
//   * the catalog rows must be SYNCED (dirty = 0). A dirty row is skipped by
//     `if (isDirty) continue`, so the write under test never runs. An earlier
//     version of this test left them dirty and passed against the bug.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/models/inlet_point.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/models/source_point.dart';
import 'package:survey_app/models/survey_options.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    // Load-bearing: matches app_database.dart's onConfigure. Without it the
    // ON DELETE SET NULL below never fires and this suite proves nothing.
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE sites (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, status TEXT,
        assigned_to TEXT, assigned_to_user_id TEXT,
        bom_locked INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
        address TEXT, client_name TEXT, client_contact TEXT,
        dirty INTEGER NOT NULL DEFAULT 1, sync_blocked INTEGER NOT NULL DEFAULT 0
      )
    ''');
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
    await db.execute('''
      CREATE TABLE source_points (
        id TEXT PRIMARY KEY, site_id TEXT NOT NULL, block TEXT, apartment TEXT,
        inlet_description TEXT, material_id TEXT, sensor_size TEXT,
        sensor_od TEXT, pipe_size TEXT, pipe_type TEXT, qty INTEGER,
        sensor_type TEXT, rework INTEGER, rework_details TEXT,
        flow_direction TEXT, clearance_10x INTEGER, pipe_full INTEGER,
        valve_downstream INTEGER, reducer_spec INTEGER, reducer_spec_details TEXT,
        downstream_outlet_above_pipe_fig1 INTEGER, air_vent_needed_fig2 INTEGER,
        reverse_flow INTEGER, distance_from_motor_pump_fig3 INTEGER,
        no_flexible_pipe_within_20x INTEGER, max_and_continuous_pressure_bar REAL,
        strainer_screen_filter INTEGER, chamber_installation INTEGER,
        antenna_required INTEGER, transmitting_part_open_to_air INTEGER,
        nrv_feasibility INTEGER,
        dirty INTEGER NOT NULL DEFAULT 1, pending_delete INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE,
        FOREIGN KEY (material_id) REFERENCES material_master_items (id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE inlet_points (
        id TEXT PRIMARY KEY, site_id TEXT NOT NULL, block TEXT,
        apartment_bhk TEXT, material_id TEXT, sensor_size TEXT, series TEXT,
        sensor_od TEXT, pipe_size TEXT, pipe_type TEXT, qty INTEGER,
        sensor_type TEXT, rework INTEGER, rework_details TEXT,
        linear_distance_clearance_10x INTEGER, reverse_flow INTEGER,
        oht_hns TEXT, distance_from_motor_pump INTEGER,
        max_and_continuous_pressure_bar REAL, strainer_screen_filter INTEGER,
        flow_direction TEXT, access_mode TEXT, cable_run_length TEXT,
        conduit_clamping INTEGER, civil_work_needed INTEGER,
        civil_work_details TEXT,
        dirty INTEGER NOT NULL DEFAULT 1, pending_delete INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE,
        FOREIGN KEY (material_id) REFERENCES material_master_items (id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE blocks (
        id TEXT PRIMARY KEY, site_id TEXT NOT NULL, position INTEGER NOT NULL,
        label TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1,
        pending_delete INTEGER NOT NULL DEFAULT 0, sync_blocked INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE client_inputs (site_id TEXT PRIMARY KEY, dirty INTEGER NOT NULL DEFAULT 1)
    ''');
    await db.execute('''
      CREATE TABLE photos (
        id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL,
        slot TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0,
        local_path TEXT, remote_path TEXT, site_id TEXT,
        dirty INTEGER NOT NULL DEFAULT 1, pending_delete INTEGER NOT NULL DEFAULT 0
      )
    ''');
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  Future<MaterialMasterItem> seedSyncedMaterial(String name) async {
    final item = await repo.addMaterialMasterItem(
      MaterialMasterItem(
        id: '',
        group: MaterialGroup.a,
        materialName: name,
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.fixed,
        sensorSize: SensorSize.dn32,
        sensorType: SensorType.wired,
      ),
      changedByRole: 'Admin',
    );
    // Synced, or the pull skips it and nothing under test executes.
    await repo.markMaterialMasterItemSynced(item.id);
    return item;
  }

  Future<String?> materialIdOf(String table, String id) async =>
      (await db.query(table, columns: ['material_id'], where: 'id = ?', whereArgs: [id]))
          .single['material_id'] as String?;

  test(
    'a source point keeps its material across repeated Material Master pulls',
    () async {
      final material = await seedSyncedMaterial('Ultrasonic DN32');
      final site = await repo.createSite(name: 'S', blocks: const []);
      final point = await repo.addSourcePoint(
        SourcePoint(
          id: '',
          siteId: site.id,
          apartment: 'A-1',
          materialId: material.id,
        ),
      );

      // Every sync pulls the catalog. Several in a row must change nothing.
      for (var i = 0; i < 3; i++) {
        await repo.upsertMaterialMasterItemsFromRemote([material]);
        expect(
          await materialIdOf('source_points', point.id),
          material.id,
          reason: 'wiped by Material Master pull #${i + 1}',
        );
      }
    },
  );

  test(
    'an inlet point keeps its material too — same FK, same exposure',
    () async {
      final material = await seedSyncedMaterial('Ultrasonic DN50');
      final site = await repo.createSite(name: 'S', blocks: const []);
      final point = await repo.addInletPoint(
        InletPoint(
          id: '',
          siteId: site.id,
          apartmentBhk: 'A-1',
          materialId: material.id,
        ),
      );

      await repo.upsertMaterialMasterItemsFromRemote([material]);

      expect(await materialIdOf('inlet_points', point.id), material.id);
    },
  );

  test(
    'the pull still applies genuine catalog edits',
    () async {
      final material = await seedSyncedMaterial('Old name');
      final site = await repo.createSite(name: 'S', blocks: const []);
      final point = await repo.addSourcePoint(
        SourcePoint(id: '', siteId: site.id, apartment: 'A-1', materialId: material.id),
      );

      final renamed = MaterialMasterItem(
        id: material.id,
        group: MaterialGroup.a,
        materialName: 'New name',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.fixed,
      );
      await repo.upsertMaterialMasterItemsFromRemote([renamed]);

      final catalog = await repo.getMaterialMasterItems();
      expect(catalog.single.materialName, 'New name',
          reason: 'the update half must still work');
      expect(await materialIdOf('source_points', point.id), material.id);
    },
  );

  test(
    'a brand-new remote material is still inserted',
    () async {
      final existing = await seedSyncedMaterial('Existing');
      const fresh = MaterialMasterItem(
        id: 'brand-new-id',
        group: MaterialGroup.a,
        materialName: 'Fresh',
        unit: 'pcs',
        behaviorType: MaterialBehaviorType.fixed,
      );

      await repo.upsertMaterialMasterItemsFromRemote([existing, fresh]);

      final ids = (await repo.getMaterialMasterItems()).map((m) => m.id);
      expect(ids, containsAll(<String>[existing.id, 'brand-new-id']));
    },
  );
}
