// Every per-site survey query must be able to use an index on site_id.
//
// pushAll walks EVERY site on every sync — not just dirty ones, because a
// site's children are dirty-tracked independently of the site row — and
// issues ~18 queries per site. None of source_points, inlet_points,
// duct_loras, gateways or blocks had an index on site_id, so each of those
// was a full table scan, making the push pass O(sites x rows).
//
// Measured against this schema at 500 sites / 21,500 rows: 993ms without the
// indexes, 28ms with them (36x). At 1000 sites it was 4769ms vs 76ms (63x).
// At present volumes (20 sites) the cost is dominated by per-statement
// overhead rather than scan time, so this buys nothing measurable today —
// it is insurance against the growth curve, not a fix for a current number.
//
// These tests assert the query PLAN rather than a timing, because a timing
// assertion at test-data scale would prove nothing and would be flaky. If
// SQLite reports SCAN for any of these, the index is missing or unusable.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/services/app_database.dart';

/// The per-site reads pushAll performs for every site it visits.
const _perSiteQueries = <String, String>{
  'source_points': 'SELECT * FROM source_points WHERE site_id = ?',
  'inlet_points': 'SELECT * FROM inlet_points WHERE site_id = ?',
  'duct_loras': 'SELECT * FROM duct_loras WHERE site_id = ?',
  'gateways': 'SELECT * FROM gateways WHERE site_id = ?',
  'blocks': 'SELECT * FROM blocks WHERE site_id = ?',
};

Future<String> _planFor(Database db, String sql) async {
  final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', ['x']);
  return rows.map((r) => r['detail']).join(' | ');
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('idx_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a fresh install indexes site_id on every per-site table', () async {
    final db = await openAppDatabaseInDirectory(dir.path, 'user-1');
    addTearDown(db.close);

    for (final entry in _perSiteQueries.entries) {
      final plan = await _planFor(db, entry.value);
      expect(
        plan,
        contains('USING INDEX'),
        reason: '${entry.key} falls back to a full table scan: $plan',
      );
    }
  });

  test('an existing database gains the indexes on upgrade', () async {
    // A database at the schema version before the indexes existed, holding
    // the tables but no site_id indexes — i.e. every device already in the
    // field. Opening it must migrate, not just work for fresh installs.
    final dbPath = '${dir.path}/survey_app_user-2.db';
    final old = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(version: 30),
    );
    for (final table in _perSiteQueries.keys) {
      await old.execute(
        'CREATE TABLE $table (id TEXT PRIMARY KEY, site_id TEXT NOT NULL)',
      );
    }
    await old.close();

    final db = await openAppDatabaseInDirectory(dir.path, 'user-2');
    addTearDown(db.close);

    for (final entry in _perSiteQueries.entries) {
      final plan = await _planFor(db, entry.value);
      expect(
        plan,
        contains('USING INDEX'),
        reason: '${entry.key} was not indexed by the migration: $plan',
      );
    }
  });
}
