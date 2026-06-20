import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens (and on first run, creates) the local SQLite database.
///
/// Phase 1: local persistence only. Schema covers sites, their blocks, and the
/// single per-site client inputs form. No Supabase / sync yet.
const String _dbFileName = 'survey_app.db';
const int _dbVersion = 5;

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
    },
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE sites (
          id          TEXT PRIMARY KEY,
          name        TEXT NOT NULL,
          status      TEXT,
          assigned_to TEXT
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

/// Material Master table (v5). Admin-editable reference data — NOT site-scoped
/// (no FK to sites). The BoM engine reads every quantity from this table at
/// generation time; it starts empty and is populated via the admin screen.
Future<void> _createMaterialMasterItemsTable(Database db) async {
  await db.execute('''
    CREATE TABLE material_master_items (
      id                   TEXT PRIMARY KEY,
      group_code           TEXT NOT NULL,
      material_name        TEXT NOT NULL,
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
