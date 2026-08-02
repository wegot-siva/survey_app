// Real-SQLite tests (via sqflite_common_ffi) for Full sync Group 2's delete
// tombstones on source_points, inlet_points, duct_loras and gateways —
// exercising SqfliteSurveyRepository's pull path directly and asserting
// actual row-level state, per the debugging protocol's requirement for
// local SQLite-query evidence before any device test.
//
// Schema here is the minimum these code paths touch, copied from
// app_database.dart's onCreate the same way sqflite_blocks_repository_test
// does (its create helpers are private, so a test can't call them). The
// pull path only ever writes the columns a remote row actually carries, and
// these tests assert against raw db.query rather than the typed getters, so
// the omitted columns are genuinely unreachable from here.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';

/// The four tables this slice tombstones, each with the repository method
/// that pulls it and a minimal remote row builder. Keeps every case below
/// table-driven — the whole point of the slice is that all four behave
/// identically, so testing one and assuming the rest would miss exactly the
/// wiring mistake most likely to happen (a missed deletedAtColumn on one).
final _tables = <String, _TombstonedTable>{
  'source_points': _TombstonedTable(
    pull: (repo, rows) => repo.upsertSourcePointsFromRemote(rows),
  ),
  'inlet_points': _TombstonedTable(
    pull: (repo, rows) => repo.upsertInletPointsFromRemote(rows),
  ),
  'duct_loras': _TombstonedTable(
    pull: (repo, rows) => repo.upsertDuctLorasFromRemote(rows),
  ),
  'gateways': _TombstonedTable(
    pull: (repo, rows) => repo.upsertGatewaysFromRemote(rows),
  ),
};

class _TombstonedTable {
  const _TombstonedTable({required this.pull});

  final Future<void> Function(
    SqfliteSurveyRepository repo,
    List<Map<String, dynamic>> rows,
  ) pull;
}

Map<String, dynamic> _remoteRow(
  String id, {
  required String siteId,
  String? deletedAt,
}) => {
  'id': id,
  'site_id': siteId,
  'deleted_at': deletedAt,
};

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

  const siteId = 'site-1';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE sites (
        id                  TEXT PRIMARY KEY,
        name                TEXT NOT NULL,
        status              TEXT,
        assigned_to         TEXT,
        assigned_to_user_id TEXT,
        bom_locked          INTEGER NOT NULL DEFAULT 0,
        archived            INTEGER NOT NULL DEFAULT 0,
        address             TEXT,
        client_name         TEXT,
        client_contact      TEXT,
        dirty               INTEGER NOT NULL DEFAULT 1,
        sync_blocked        INTEGER NOT NULL DEFAULT 0
      )
    ''');
    for (final table in _tables.keys) {
      await db.execute('''
        CREATE TABLE $table (
          id             TEXT PRIMARY KEY,
          site_id        TEXT NOT NULL,
          dirty          INTEGER NOT NULL DEFAULT 1,
          pending_delete INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    await db.execute('''
      CREATE TABLE photos (
        id          TEXT PRIMARY KEY,
        owner_type  TEXT NOT NULL,
        owner_id    TEXT NOT NULL,
        slot        TEXT NOT NULL,
        position    INTEGER NOT NULL DEFAULT 0,
        local_path  TEXT,
        remote_path TEXT,
        site_id     TEXT,
        dirty       INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.insert('sites', {'id': siteId, 'name': 'Test Site', 'dirty': 0});
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  /// Inserts a already-synced (clean) local row directly — the state a row
  /// is in after a normal pull, and the only state a tombstone may act on.
  Future<void> insertClean(String table, String id) => db.insert(table, {
    'id': id,
    'site_id': siteId,
    'dirty': 0,
    'pending_delete': 0,
  });

  Future<List<Map<String, Object?>>> rowsOf(String table, String id) =>
      db.query(table, where: 'id = ?', whereArgs: [id]);

  for (final entry in _tables.entries) {
    final table = entry.key;
    final spec = entry.value;

    group(table, () {
      test(
        'a remote row with deleted_at set hard-deletes the matching local '
        '(clean) row — explicit, not inferred from absence',
        () async {
          await insertClean(table, 'row-1');

          await spec.pull(repo, [
            _remoteRow('row-1', siteId: siteId, deletedAt: '2026-01-01T00:00:00Z'),
          ]);

          expect(await rowsOf(table, 'row-1'), isEmpty);
        },
      );

      test(
        'a tombstoned remote row for an id this device never had is skipped, '
        'not inserted then deleted',
        () async {
          await spec.pull(repo, [
            _remoteRow('never-seen', siteId: siteId, deletedAt: '2026-01-01T00:00:00Z'),
          ]);

          expect(await rowsOf(table, 'never-seen'), isEmpty);
          expect(await db.query(table), isEmpty);
        },
      );

      test(
        'a tombstoned remote row is NOT applied when the local row has an '
        'unsynced edit — protected exactly like every other pull',
        () async {
          await db.insert(table, {
            'id': 'row-1',
            'site_id': siteId,
            'dirty': 1, // local edit not yet pushed
            'pending_delete': 0,
          });

          await spec.pull(repo, [
            _remoteRow('row-1', siteId: siteId, deletedAt: '2026-01-01T00:00:00Z'),
          ]);

          final rows = await rowsOf(table, 'row-1');
          expect(rows, hasLength(1));
          expect(rows.single['dirty'], 1);
        },
      );

      test(
        'a tombstoned remote row is NOT applied when the local row is itself '
        'pending its own delete — that push still has to happen first',
        () async {
          await db.insert(table, {
            'id': 'row-1',
            'site_id': siteId,
            'dirty': 1,
            'pending_delete': 1,
          });

          await spec.pull(repo, [
            _remoteRow('row-1', siteId: siteId, deletedAt: '2026-01-01T00:00:00Z'),
          ]);

          final rows = await rowsOf(table, 'row-1');
          expect(rows, hasLength(1));
          expect(rows.single['pending_delete'], 1);
        },
      );

      test(
        'a normal (non-tombstoned) remote row still upserts and clears dirty '
        '— tombstone support does not break ordinary pull',
        () async {
          await spec.pull(repo, [_remoteRow('row-1', siteId: siteId)]);

          final rows = await rowsOf(table, 'row-1');
          expect(rows, hasLength(1));
          expect(rows.single['dirty'], 0);
        },
      );

      test(
        'deleted_at is never written to local storage — the column exists '
        'only remotely, as the durable marker',
        () async {
          await spec.pull(repo, [_remoteRow('row-1', siteId: siteId)]);

          // Would throw DatabaseException (no such column) if the pull had
          // tried to persist it.
          final columns = (await db.rawQuery('PRAGMA table_info($table)'))
              .map((r) => r['name'])
              .toSet();
          expect(columns, isNot(contains('deleted_at')));
        },
      );

      test(
        'one tombstone in a mixed pull removes only its own row, leaving the '
        'live rows in the same response untouched',
        () async {
          await insertClean(table, 'row-1');
          await insertClean(table, 'row-2');

          await spec.pull(repo, [
            _remoteRow('row-1', siteId: siteId, deletedAt: '2026-01-01T00:00:00Z'),
            _remoteRow('row-2', siteId: siteId),
          ]);

          expect(await rowsOf(table, 'row-1'), isEmpty);
          expect(await rowsOf(table, 'row-2'), hasLength(1));
        },
      );
    });
  }

  test(
    'absence alone still removes nothing on these tables — reconcileDeletes '
    'stays off, tombstones are the only delete signal',
    () async {
      for (final table in _tables.keys) {
        await insertClean(table, 'row-1');
      }

      // A complete, successful, non-empty fetch that simply no longer
      // mentions row-1. Unlike sites/blocks (which opted into
      // reconcileDeletes), these four must leave it alone.
      for (final entry in _tables.entries) {
        await entry.value.pull(repo, [_remoteRow('other', siteId: siteId)]);
      }

      for (final table in _tables.keys) {
        expect(
          await rowsOf(table, 'row-1'),
          hasLength(1),
          reason: '$table removed a row on absence alone',
        );
      }
    },
  );
}
