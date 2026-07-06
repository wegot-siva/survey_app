import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/engineer_directory.dart';
import 'material_master_seed.dart';

/// Opens (and on first run, creates) the local SQLite database.
///
/// Phase 1: local persistence only. Schema covers sites, their blocks, and the
/// single per-site client inputs form. No Supabase / sync yet.
const String _dbFileName = 'survey_app.db';
const int _dbVersion = 14;

Future<Database> openAppDatabase() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(docsDir.path, _dbFileName);

  return openDatabase(
    dbPath,
    version: _dbVersion,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    onUpgrade: (db, oldVersion, newVersion) async {
      // v1 -> v2: add source points.
      if (oldVersion < 2) {
        await _createSourcePointsTable(db);
      }
      // v2 -> v3: add inlet points.
      if (oldVersion < 3) {
        await _createInletPointsTable(db);
      }
      // v3 -> v4: add Duct LoRa, Gateway, Footer; reserve assignment columns
      // on sites (unused for now — future assignment workflow).
      if (oldVersion < 4) {
        await db.execute('ALTER TABLE sites ADD COLUMN status TEXT');
        await db.execute('ALTER TABLE sites ADD COLUMN assigned_to TEXT');
        await _createDuctLorasTable(db);
        await _createGatewaysTable(db);
        await _createFootersTable(db);
      }
      // v4 -> v5: add Material Master (admin-editable, not site-scoped — the
      // BoM engine reads its quantities from here at generation time).
      if (oldVersion < 5) {
        await _createMaterialMasterItemsTable(db);
      }
      // v5 -> v6: photo capture slice 1 — placement photo on Duct LoRa.
      // Local path is set on capture (offline-first); remote path on upload.
      if (oldVersion < 6) {
        await db.execute(
          'ALTER TABLE duct_loras ADD COLUMN placement_photo_local_path TEXT',
        );
        await db.execute(
          'ALTER TABLE duct_loras ADD COLUMN placement_photo_remote_path TEXT',
        );
      }
      // v6 -> v7: photo capture slice 2 — generic polymorphic photos table
      // serving source/inlet/gateway/footer photo fields.
      if (oldVersion < 7) {
        await _createPhotosTable(db);
      }
      // v7 -> v8: multi-photo rollout — Duct LoRa's placement photo moves off
      // its own two columns onto the shared photos table (so it can hold many,
      // like every other field). Backfill any already-captured photo first so
      // nothing is orphaned; the old columns are left in place, unused.
      if (oldVersion < 8) {
        await _migrateDuctLoraPlacementPhotoToPhotosTable(db);
      }
      // v8 -> v9: Admin role slice — SKU on Material Master + its change log.
      if (oldVersion < 9) {
        await db.execute(
          'ALTER TABLE material_master_items ADD COLUMN sku TEXT',
        );
        await _createMaterialMasterAuditTable(db);
      }
      // v9 -> v10: D/E/G "Add materials" picker — manual BoM entries per survey.
      if (oldVersion < 10) {
        await _createBomManualEntriesTable(db);
      }
      // v10 -> v11: Finalize — freezes the current BoM as an immutable
      // version-1 snapshot. bom_locked defaults to 0, so every existing
      // survey stays unlocked (still shows a live-recomputed BoM) until
      // someone explicitly finalizes it.
      if (oldVersion < 11) {
        await db.execute(
          'ALTER TABLE sites ADD COLUMN bom_locked INTEGER NOT NULL DEFAULT 0',
        );
        await _createBomSnapshotsTable(db);
        await _createBomSnapshotLinesTable(db);
      }
      // v11 -> v12: BoM revisions — additive delta layers (v2+) on top of a
      // locked v1 snapshot. Running total is computed on read only; no
      // per-version snapshot is stored, so nothing else changes.
      if (oldVersion < 12) {
        await _createBomRevisionsTable(db);
        await _createBomRevisionLinesTable(db);
      }
      // v12 -> v13: Lumax export format — needs Item (short label, distinct
      // from the full descriptive name) and the frozen sensor variant on
      // every line that can feed an export, so sheet-per-variant grouping
      // and the Item/Materials/Size columns don't need to guess at a string
      // split. All nullable/blank-default, so existing rows are unaffected.
      if (oldVersion < 13) {
        await db.execute(
          'ALTER TABLE material_master_items ADD COLUMN item_label TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_manual_entries ADD COLUMN item_label TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_manual_entries ADD COLUMN sensor_size TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_manual_entries ADD COLUMN sensor_type TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_revision_lines ADD COLUMN material_name TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_revision_lines ADD COLUMN item_label TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_revision_lines ADD COLUMN sensor_size TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_revision_lines ADD COLUMN sensor_type TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_snapshot_lines ADD COLUMN material_name TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_snapshot_lines ADD COLUMN item_label TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_snapshot_lines ADD COLUMN sensor_size TEXT',
        );
        await db.execute(
          'ALTER TABLE bom_snapshot_lines ADD COLUMN sensor_type TEXT',
        );
      }
      // v13 -> v14: lightweight engineer roster + survey reassignment audit
      // log. The roster is a plain list Sales assigns/reassigns against — not
      // a real per-user auth system (the shared Engineer login is unchanged)
      // — seeded from the same names AssignSurveyScreen has always offered
      // (kEngineerDirectory) so reassignment offers exactly the same choices
      // as initial assignment did.
      if (oldVersion < 14) {
        await _createEngineersTable(db);
        await _seedEngineers(db);
        await _createSurveyAssignmentAuditTable(db);
      }
    },
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE sites (
          id          TEXT PRIMARY KEY,
          name        TEXT NOT NULL,
          status      TEXT,
          assigned_to TEXT,
          bom_locked  INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE blocks (
          id       INTEGER PRIMARY KEY AUTOINCREMENT,
          site_id  TEXT NOT NULL,
          position INTEGER NOT NULL,
          label    TEXT NOT NULL,
          FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE client_inputs (
          site_id                       TEXT PRIMARY KEY,
          site_name                     TEXT,
          information_source            TEXT,
          client_poc_name               TEXT,
          client_poc_contact            TEXT,
          goal_of_installation          TEXT,
          water_sources                 TEXT,
          oht_hns                       TEXT,
          finalised_plumbing_drawings   INTEGER,
          points_identified             INTEGER,
          max_and_continuous_pressure   TEXT,
          pressure_boosters             INTEGER,
          materials_and_brand_guidelines TEXT,
          rework_required               INTEGER,
          rework_details                TEXT,
          age_of_plumbing_lines         TEXT,
          aesthetic_guidelines          INTEGER,
          aesthetic_details             TEXT,
          FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
        )
      ''');

      await _createSourcePointsTable(db);
      await _createInletPointsTable(db);
      await _createDuctLorasTable(db);
      await _createGatewaysTable(db);
      await _createFootersTable(db);
      await _createMaterialMasterItemsTable(db);
      // DEV-ONLY, fresh installs only — see material_master_seed.dart for
      // removal instructions once real production data replaces this.
      await seedMaterialMasterItems(db);
      await _createPhotosTable(db);
      await _createMaterialMasterAuditTable(db);
      await _createBomManualEntriesTable(db);
      await _createBomSnapshotsTable(db);
      await _createBomSnapshotLinesTable(db);
      await _createBomRevisionsTable(db);
      await _createBomRevisionLinesTable(db);
      await _createEngineersTable(db);
      await _seedEngineers(db);
      await _createSurveyAssignmentAuditTable(db);
    },
  );
}

/// Source points table (v2). A site has many; booleans stored as INTEGER 0/1,
/// enums as their `.name`, pressure as REAL.
Future<void> _createSourcePointsTable(Database db) async {
  await db.execute('''
    CREATE TABLE source_points (
      id                                TEXT PRIMARY KEY,
      site_id                           TEXT NOT NULL,
      block                             TEXT,
      apartment                         TEXT,
      inlet_description                 TEXT,
      sensor_size                       TEXT,
      sensor_od                         TEXT,
      pipe_size                         TEXT,
      pipe_type                         TEXT,
      qty                               INTEGER,
      sensor_type                       TEXT,
      rework                            INTEGER,
      rework_details                    TEXT,
      flow_direction                    TEXT,
      clearance_10x                     INTEGER,
      pipe_full                         INTEGER,
      valve_downstream                  INTEGER,
      reducer_spec                      INTEGER,
      reducer_spec_details              TEXT,
      downstream_outlet_above_pipe_fig1 INTEGER,
      air_vent_needed_fig2              INTEGER,
      reverse_flow                      INTEGER,
      distance_from_motor_pump_fig3     INTEGER,
      no_flexible_pipe_within_20x       INTEGER,
      max_and_continuous_pressure_bar   REAL,
      strainer_screen_filter            INTEGER,
      chamber_installation              INTEGER,
      antenna_required                  INTEGER,
      transmitting_part_open_to_air     INTEGER,
      nrv_feasibility                   INTEGER,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
}

/// Inlet points table (v3). A site has many. Distinct from source points:
/// no source-only checks (pipe full, valve, reducer, etc.); adds series,
/// access mode, cable run length and conduit/civil-work fields.
Future<void> _createInletPointsTable(Database db) async {
  await db.execute('''
    CREATE TABLE inlet_points (
      id                            TEXT PRIMARY KEY,
      site_id                       TEXT NOT NULL,
      block                         TEXT,
      apartment_bhk                 TEXT,
      sensor_size                   TEXT,
      series                        TEXT,
      sensor_od                     TEXT,
      pipe_size                     TEXT,
      pipe_type                     TEXT,
      qty                           INTEGER,
      sensor_type                   TEXT,
      rework                        INTEGER,
      rework_details                TEXT,
      linear_distance_clearance_10x INTEGER,
      reverse_flow                  INTEGER,
      oht_hns                       TEXT,
      distance_from_motor_pump      INTEGER,
      max_and_continuous_pressure_bar REAL,
      strainer_screen_filter        INTEGER,
      flow_direction                TEXT,
      access_mode                   TEXT,
      cable_run_length              TEXT,
      conduit_clamping              INTEGER,
      civil_work_needed             INTEGER,
      civil_work_details            TEXT,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
}

/// Duct LoRa units table (v4). A site has many. `series_served` is a
/// comma-separated set of series tokens (mirrors water_sources in client_inputs).
///
/// Fresh installs (v8+) never get the old `placement_photo_*` columns — that
/// photo now lives in the shared `photos` table like every other photo field.
/// Devices upgrading from an older version keep those two columns (added by
/// the v5->v6 step below); they're just unused going forward — see the v8
/// migration, which backfills any existing photo out of them.
Future<void> _createDuctLorasTable(Database db) async {
  await db.execute('''
    CREATE TABLE duct_loras (
      id                             TEXT PRIMARY KEY,
      site_id                        TEXT NOT NULL,
      block                          TEXT,
      series_served                  TEXT,
      accessible_for_service         INTEGER,
      rssi_if_tcl                    REAL,
      power_point_available_shielded INTEGER,
      separate_mcb_for_series        INTEGER,
      ups_power_supply               INTEGER,
      cable_length                   REAL,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
}

/// Gateways table (v4). A site has many. `blocks_covered` is a comma-separated
/// set of block labels.
Future<void> _createGatewaysTable(Database db) async {
  await db.execute('''
    CREATE TABLE gateways (
      id                         TEXT PRIMARY KEY,
      site_id                    TEXT NOT NULL,
      placement                  TEXT,
      location_description       TEXT,
      blocks_covered             TEXT,
      quantity                   INTEGER,
      uplink_type                TEXT,
      wifi_interference_check    INTEGER,
      wifi_interference_details  TEXT,
      sim_coverage               TEXT,
      uninterrupted_power_source INTEGER,
      mounting_hardware_needed   TEXT,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
}

/// Footer table (v4). One row per site (keyed by site_id), like client_inputs.
Future<void> _createFootersTable(Database db) async {
  await db.execute('''
    CREATE TABLE footers (
      site_id             TEXT PRIMARY KEY,
      tds_ppm             REAL,
      tss_ppm             REAL,
      tcl_service         INTEGER,
      tcl_service_details TEXT,
      general_remarks     TEXT,
      survey_date         TEXT,
      surveyor_name       TEXT,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
}

/// Photos table (v7). Polymorphic + slot-based, serving every photo field
/// across source/inlet/gateway/footer. Not FK-scoped (owner_type + owner_id is
/// a polymorphic link). Local path set on capture; remote path on upload.
Future<void> _createPhotosTable(Database db) async {
  await db.execute('''
    CREATE TABLE photos (
      id          TEXT PRIMARY KEY,
      owner_type  TEXT NOT NULL,
      owner_id    TEXT NOT NULL,
      slot        TEXT NOT NULL,
      position    INTEGER NOT NULL DEFAULT 0,
      local_path  TEXT,
      remote_path TEXT
    )
  ''');
  await db.execute(
    'CREATE INDEX photos_owner_idx ON photos (owner_type, owner_id)',
  );
}

/// One-time backfill (v8): copies any Duct LoRa unit's existing placement
/// photo — captured back when it lived on its own two columns — into a row in
/// the shared `photos` table, preserving both the local file reference and
/// (if already uploaded) the remote object key, so nothing is orphaned and
/// nothing gets needlessly re-uploaded. The source columns are left as-is.
Future<void> _migrateDuctLoraPlacementPhotoToPhotosTable(Database db) async {
  final rows = await db.query(
    'duct_loras',
    columns: ['id', 'placement_photo_local_path', 'placement_photo_remote_path'],
    where:
        'placement_photo_local_path IS NOT NULL '
        'OR placement_photo_remote_path IS NOT NULL',
  );
  const uuid = Uuid();
  for (final row in rows) {
    await db.insert('photos', {
      'id': uuid.v4(),
      'owner_type': 'duct_lora',
      'owner_id': row['id'],
      'slot': 'placement',
      'position': 0,
      'local_path': row['placement_photo_local_path'],
      'remote_path': row['placement_photo_remote_path'],
    });
  }
}

/// Material Master table (v5, +sku in v9, +item_label in v13). Admin-editable reference data —
/// NOT site-scoped (no FK to sites). The BoM engine reads every quantity from
/// this table at generation time; it starts empty and is populated via the
/// admin screen.
Future<void> _createMaterialMasterItemsTable(Database db) async {
  await db.execute('''
    CREATE TABLE material_master_items (
      id                   TEXT PRIMARY KEY,
      group_code           TEXT NOT NULL,
      material_name        TEXT NOT NULL,
      sku                  TEXT,
      item_label           TEXT,
      unit                 TEXT NOT NULL,
      behavior_type        TEXT NOT NULL,
      sensor_size          TEXT,
      sensor_type          TEXT,
      quantity_per_sensor  REAL NOT NULL DEFAULT 0,
      derived_formula      TEXT,
      formula_divisor      REAL,
      variable_source      TEXT,
      notes                TEXT
    )
  ''');
}

/// Material Master change log (v9). Not FK-scoped to material_master_items —
/// a deleted row's audit trail (including its own delete entry) must survive
/// the row's removal. One row per create/delete event, one row per changed
/// field on an edit — see MaterialMasterAuditBuilder.
Future<void> _createMaterialMasterAuditTable(Database db) async {
  await db.execute('''
    CREATE TABLE material_master_audit (
      id                TEXT PRIMARY KEY,
      material_row_id   TEXT NOT NULL,
      field_changed     TEXT NOT NULL,
      old_value         TEXT,
      new_value         TEXT,
      changed_by_role   TEXT NOT NULL,
      changed_at        TEXT NOT NULL
    )
  ''');
  await db.execute(
    'CREATE INDEX material_master_audit_row_idx '
    'ON material_master_audit (material_row_id)',
  );
}

/// BoM manual entries table (v10, +item_label/sensor_size/sensor_type in
/// v13). A
/// survey has many; FK'd to sites (cascade delete, like source/inlet points)
/// since these are genuinely survey-scoped, unlike Material Master. Not
/// linked to any material_master_items row by id — name/sku/unit are copied
/// at the moment the picker's dropdown selection is made, so an entry
/// survives that catalog row later changing or being deleted. `group_code`
/// avoids "group" (a reserved word in the remote Postgres schema) but,
/// unlike material_master_items.group_code (lowercase enum name), stores the
/// literal 'D' / 'E' / 'G' — the picker UI restricts it to just those three.
Future<void> _createBomManualEntriesTable(Database db) async {
  await db.execute('''
    CREATE TABLE bom_manual_entries (
      id            TEXT PRIMARY KEY,
      survey_id     TEXT NOT NULL,
      material_name TEXT NOT NULL,
      sku           TEXT,
      item_label    TEXT,
      sensor_size   TEXT,
      sensor_type   TEXT,
      unit          TEXT NOT NULL,
      qty           REAL NOT NULL,
      group_code    TEXT NOT NULL,
      added_by      TEXT NOT NULL,
      added_at      TEXT NOT NULL,
      FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX bom_manual_entries_survey_idx '
    'ON bom_manual_entries (survey_id)',
  );
}

/// BoM snapshots table (v11) — the Finalize action. One row per survey in
/// this slice (version always 1; no re-finalize flow), FK'd to sites
/// (cascade delete) since a snapshot is meaningless without its survey.
Future<void> _createBomSnapshotsTable(Database db) async {
  await db.execute('''
    CREATE TABLE bom_snapshots (
      id            TEXT PRIMARY KEY,
      survey_id     TEXT NOT NULL,
      version       INTEGER NOT NULL DEFAULT 1,
      status        TEXT NOT NULL,
      finalized_by  TEXT NOT NULL,
      finalized_at  TEXT NOT NULL,
      FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX bom_snapshots_survey_idx ON bom_snapshots (survey_id)',
  );
}

/// BoM snapshot lines table (v11, +material_name/item_label/sensor_size/
/// sensor_type in v13). The frozen values of one [BomSnapshot].
/// FK'd to bom_snapshots (cascade delete); NOT linked to material_master_items
/// or bom_manual_entries by id — sku/item/unit/qty/group are copied at
/// finalize time, so editing either later cannot alter an existing snapshot.
/// `group_code` stores the literal 'A'..'G' (see the matching comment on
/// bom_manual_entries above for why this differs from
/// material_master_items.group_code); `source` stores literal 'auto'|'manual'.
/// The v13 fields are separate from `item` (which stays exactly as before,
/// still what Sun_BOM's "Item" column reads) — they exist purely so the
/// Lumax format's Item/Materials/Size/sheet-grouping don't need to guess a
/// string split.
Future<void> _createBomSnapshotLinesTable(Database db) async {
  await db.execute('''
    CREATE TABLE bom_snapshot_lines (
      id            TEXT PRIMARY KEY,
      snapshot_id   TEXT NOT NULL,
      sku           TEXT,
      item          TEXT NOT NULL,
      material_name TEXT,
      item_label    TEXT,
      sensor_size   TEXT,
      sensor_type   TEXT,
      unit          TEXT NOT NULL,
      qty           REAL NOT NULL,
      group_code    TEXT NOT NULL,
      source        TEXT NOT NULL,
      FOREIGN KEY (snapshot_id) REFERENCES bom_snapshots (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX bom_snapshot_lines_snapshot_idx '
    'ON bom_snapshot_lines (snapshot_id)',
  );
}

/// BoM revisions table (v12) — additive delta layers (version 2+) on top of
/// a survey's locked v1 snapshot. FK'd to sites (cascade delete), like
/// bom_manual_entries. A revision's own row never changes after creation; a
/// later correction is a new revision, not an edit.
Future<void> _createBomRevisionsTable(Database db) async {
  await db.execute('''
    CREATE TABLE bom_revisions (
      id          TEXT PRIMARY KEY,
      survey_id   TEXT NOT NULL,
      version     INTEGER NOT NULL,
      reason      TEXT NOT NULL,
      created_by  TEXT NOT NULL,
      created_at  TEXT NOT NULL,
      FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX bom_revisions_survey_idx ON bom_revisions (survey_id)',
  );
}

/// BoM revision lines table (v12, +material_name/item_label/sensor_size/
/// sensor_type in v13) — the delta values of one [BomRevision].
/// FK'd to bom_revisions (cascade delete); NOT linked to material_master_items
/// by id — sku/item/unit are copied in at the moment the picker's dropdown
/// selection is made, same convention as bom_manual_entries and
/// bom_snapshot_lines. `qty_delta` may be negative. `group_code` stores the
/// literal 'A'..'G' (a revision line is not restricted to D/E/G). The v13
/// fields mirror bom_snapshot_lines' — `item` is untouched (Sun_BOM
/// compatibility), the new columns feed Lumax only.
Future<void> _createBomRevisionLinesTable(Database db) async {
  await db.execute('''
    CREATE TABLE bom_revision_lines (
      id            TEXT PRIMARY KEY,
      revision_id   TEXT NOT NULL,
      sku           TEXT,
      item          TEXT NOT NULL,
      material_name TEXT,
      item_label    TEXT,
      sensor_size   TEXT,
      sensor_type   TEXT,
      unit          TEXT NOT NULL,
      qty_delta     REAL NOT NULL,
      group_code    TEXT NOT NULL,
      FOREIGN KEY (revision_id) REFERENCES bom_revisions (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX bom_revision_lines_revision_idx '
    'ON bom_revision_lines (revision_id)',
  );
}

/// Engineer roster table (v14) — Sales assigns/reassigns surveys against this
/// list. A roster, not an auth system: the shared Engineer login (see
/// UserRole) is unchanged; `name` is the plain string written to
/// `sites.assigned_to`. Not site-scoped, so no FK — same shape as
/// material_master_items.
Future<void> _createEngineersTable(Database db) async {
  await db.execute('''
    CREATE TABLE engineers (
      id   TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE
    )
  ''');
}

/// Seeds the roster from the same names AssignSurveyScreen has always
/// offered (kEngineerDirectory), so reassignment offers exactly who could
/// already be picked at initial assignment. Guarded by the table's
/// UNIQUE(name) + ConflictAlgorithm.ignore, so calling this more than once is
/// harmless.
Future<void> _seedEngineers(Database db) async {
  const uuid = Uuid();
  await db.transaction((txn) async {
    for (final name in kEngineerDirectory) {
      await txn.insert(
        'engineers',
        {'id': uuid.v4(), 'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  });
}

/// Survey reassignment audit log (v14). Genuinely survey-scoped — FK'd to
/// sites (cascade delete), like bom_manual_entries/bom_revisions. One row per
/// reassignment (never per initial assignment — that's a plain `updateSite`
/// call from AssignSurveyScreen, not this path).
Future<void> _createSurveyAssignmentAuditTable(Database db) async {
  await db.execute('''
    CREATE TABLE survey_assignment_audit (
      id              TEXT PRIMARY KEY,
      site_id         TEXT NOT NULL,
      old_assignee    TEXT,
      new_assignee    TEXT NOT NULL,
      changed_by_role TEXT NOT NULL,
      changed_at      TEXT NOT NULL,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
  await db.execute(
    'CREATE INDEX survey_assignment_audit_site_idx '
    'ON survey_assignment_audit (site_id)',
  );
}
