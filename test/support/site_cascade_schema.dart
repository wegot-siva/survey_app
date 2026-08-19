// Minimal local schema for the tables that hang off a site.
//
// Shared because SqfliteSurveyRepository's reassignment guard
// (_hasUnsyncedWorkForSite) queries EVERY table that cascades from `sites`
// before it will let the pull delete one, and it deliberately does not
// tolerate a missing table: silently skipping a table it cannot read would
// mean silently failing to protect the data in it, which is the exact
// failure this guard exists to prevent. A typo in the guard's table list
// should fail loudly in tests, not quietly lose a day of field work in the
// field.
//
// The consequence is that any test whose repository reaches
// upsertSitesFromRemote needs all of these tables present, even if the test
// itself only cares about two of them. Duplicating fifteen CREATE TABLEs per
// test file is how those files drift apart, so they live here once.
//
// Deliberately minimal: only the columns the guard reads (the linking column
// plus dirty / pending_delete) and the foreign keys that make the cascade
// real. Tests needing fuller tables declare their own.

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates every table [_hasUnsyncedWorkForSite] inspects, except `sites`
/// itself and any table in [skip] (for callers that declare a fuller version
/// of one themselves).
///
/// Requires `sites` to exist already, and `PRAGMA foreign_keys = ON` to have
/// been set if the caller wants the cascade to actually fire.
Future<void> createSiteCascadeTables(
  Database db, {
  Set<String> skip = const {},
}) async {
  Future<void> run(String table, String sql) async {
    if (skip.contains(table)) return;
    await db.execute(sql);
  }

  for (final t in ['source_points', 'inlet_points', 'duct_loras', 'gateways']) {
    await run(t, '''
      CREATE TABLE $t (
        id TEXT PRIMARY KEY, site_id TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
  }
  await run('blocks', '''
    CREATE TABLE blocks (
      id TEXT PRIMARY KEY, site_id TEXT NOT NULL, position INTEGER NOT NULL,
      label TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1,
      pending_delete INTEGER NOT NULL DEFAULT 0,
      sync_blocked INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
  for (final t in ['client_inputs', 'footers']) {
    await run(t, '''
      CREATE TABLE $t (
        site_id TEXT PRIMARY KEY, dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
  }
  // No foreign key, mirroring the real schema: photos are orphaned rather
  // than cascaded, which is why the guard counts them explicitly.
  await run('photos', '''
    CREATE TABLE photos (
      id TEXT PRIMARY KEY, owner_type TEXT NOT NULL, owner_id TEXT NOT NULL,
      slot TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0,
      local_path TEXT, remote_path TEXT, site_id TEXT,
      dirty INTEGER NOT NULL DEFAULT 1,
      pending_delete INTEGER NOT NULL DEFAULT 0
    )
  ''');
  await run('bom_manual_entries', '''
    CREATE TABLE bom_manual_entries (
      id TEXT PRIMARY KEY, survey_id TEXT NOT NULL,
      material_name TEXT NOT NULL, unit TEXT NOT NULL, qty REAL NOT NULL,
      group_code TEXT NOT NULL, added_by TEXT NOT NULL, added_at TEXT NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 1,
      pending_delete INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
    )
  ''');
  for (final t in [
    'bom_snapshots',
    'bom_revisions',
    'bom_manual_edit_snapshots',
  ]) {
    await run(t, '''
      CREATE TABLE $t (
        id TEXT PRIMARY KEY, survey_id TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
  }
  for (final pair in [
    ['bom_snapshot_lines', 'bom_snapshots', 'snapshot_id'],
    ['bom_revision_lines', 'bom_revisions', 'revision_id'],
    ['bom_manual_edit_snapshot_lines', 'bom_manual_edit_snapshots',
      'snapshot_id'],
  ]) {
    await run(pair[0], '''
      CREATE TABLE ${pair[0]} (
        id TEXT PRIMARY KEY, ${pair[2]} TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (${pair[2]}) REFERENCES ${pair[1]} (id) ON DELETE CASCADE
      )
    ''');
  }
}
