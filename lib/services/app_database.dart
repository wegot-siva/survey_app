import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens (and on first run, creates) the local SQLite database.
///
/// Phase 1: local persistence only. Schema covers sites, their blocks, and the
/// single per-site client inputs form. No Supabase / sync yet.
const String _dbFileName = 'survey_app.db';
const int _dbVersion = 3;

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
    },
    onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE sites (
          id   TEXT PRIMARY KEY,
          name TEXT NOT NULL
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
