import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Opens (and on first run, creates) the local SQLite database.
///
/// Phase 1: local persistence only. Schema covers sites, their blocks, and the
/// single per-site client inputs form. No Supabase / sync yet.
const String _dbFileName = 'survey_app.db';
const int _dbVersion = 1;

Future<Database> openAppDatabase() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(docsDir.path, _dbFileName);

  return openDatabase(
    dbPath,
    version: _dbVersion,
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
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
    },
  );
}
