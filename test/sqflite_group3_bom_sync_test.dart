// Real-SQLite tests (via sqflite_common_ffi) for Full sync Group 3:
//
//   * bom_manual_entries' delete tombstone — the same explicit deleted_at
//     mechanism Group 2 built, on the one BoM table with a delete path.
//   * pull-sync for the six immutable BoM tables, which were push-only
//     until this slice (a finalized BoM and its whole revision history
//     existed only on the device that made it). These are plain upserts:
//     no tombstone, and crucially no absence-based reconcile.
//
// Schema is the minimum these paths touch, copied from app_database.dart's
// create helpers (which are private, so a test can't call them) — with
// foreign keys ON, so the parent-before-lines pull ordering is genuinely
// enforced here rather than assumed.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

  const siteId = 'site-1';
  const snapshotId = 'snap-1';
  const revisionId = 'rev-1';
  const editSnapshotId = 'edit-1';

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE sites (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, status TEXT,
        assigned_to TEXT, assigned_to_user_id TEXT,
        bom_locked INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        address TEXT, client_name TEXT, client_contact TEXT,
        dirty INTEGER NOT NULL DEFAULT 1,
        sync_blocked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_manual_entries (
        id TEXT PRIMARY KEY, survey_id TEXT NOT NULL,
        material_name TEXT NOT NULL, sku TEXT, item_label TEXT,
        sensor_size TEXT, sensor_type TEXT, unit TEXT NOT NULL,
        qty REAL NOT NULL, group_code TEXT NOT NULL,
        added_by TEXT NOT NULL, added_by_user_id TEXT, added_at TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_snapshots (
        id TEXT PRIMARY KEY, survey_id TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1, status TEXT NOT NULL,
        finalized_by TEXT NOT NULL, finalized_by_user_id TEXT,
        finalized_at TEXT NOT NULL, dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_snapshot_lines (
        id TEXT PRIMARY KEY, snapshot_id TEXT NOT NULL, sku TEXT,
        item TEXT NOT NULL, material_name TEXT, item_label TEXT,
        sensor_size TEXT, sensor_type TEXT, unit TEXT NOT NULL,
        qty REAL NOT NULL, group_code TEXT NOT NULL, source TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (snapshot_id) REFERENCES bom_snapshots (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_revisions (
        id TEXT PRIMARY KEY, survey_id TEXT NOT NULL, version INTEGER NOT NULL,
        reason TEXT NOT NULL, created_by TEXT NOT NULL,
        created_by_user_id TEXT, created_at TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_revision_lines (
        id TEXT PRIMARY KEY, revision_id TEXT NOT NULL, sku TEXT,
        item TEXT NOT NULL, material_name TEXT, item_label TEXT,
        sensor_size TEXT, sensor_type TEXT, unit TEXT NOT NULL,
        qty_delta REAL NOT NULL, group_code TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (revision_id) REFERENCES bom_revisions (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_manual_edit_snapshots (
        id TEXT PRIMARY KEY, survey_id TEXT NOT NULL, version INTEGER NOT NULL,
        based_on_version INTEGER NOT NULL, edited_by TEXT NOT NULL,
        edited_at TEXT NOT NULL, reason TEXT,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE bom_manual_edit_snapshot_lines (
        id TEXT PRIMARY KEY, snapshot_id TEXT NOT NULL, sku TEXT,
        item_name TEXT NOT NULL, description TEXT, unit TEXT NOT NULL,
        qty REAL NOT NULL, group_code TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (snapshot_id) REFERENCES bom_manual_edit_snapshots (id) ON DELETE CASCADE
      )
    ''');
    await db.insert('sites', {'id': siteId, 'name': 'Test Site', 'dirty': 0});
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  Map<String, dynamic> manualEntryRow(String id, {String? deletedAt}) => {
    'id': id,
    'survey_id': siteId,
    'material_name': 'Pipe',
    'sku': 'SKU-1',
    'item_label': 'P',
    'sensor_size': null,
    'sensor_type': null,
    'unit': 'm',
    'qty': 3.0,
    'group_code': 'D',
    'added_by': 'Engineer',
    'added_by_user_id': null,
    'added_at': '2026-01-01T00:00:00Z',
    'deleted_at': deletedAt,
  };

  // ---- bom_manual_entries tombstone --------------------------------------

  group('bom_manual_entries tombstone', () {
    test(
      'a remote row with deleted_at set hard-deletes the matching local '
      '(clean) row',
      () async {
        await db.insert('bom_manual_entries', {
          ...manualEntryRow('e1')..remove('deleted_at'),
          'dirty': 0,
          'pending_delete': 0,
        });

        await repo.upsertBomManualEntriesFromRemote([
          manualEntryRow('e1', deletedAt: '2026-02-01T00:00:00Z'),
        ]);

        expect(
          await db.query('bom_manual_entries', where: 'id = ?', whereArgs: ['e1']),
          isEmpty,
        );
      },
    );

    test(
      'a tombstoned entry this device never had is skipped, not inserted '
      'then deleted',
      () async {
        await repo.upsertBomManualEntriesFromRemote([
          manualEntryRow('never-seen', deletedAt: '2026-02-01T00:00:00Z'),
        ]);

        expect(await db.query('bom_manual_entries'), isEmpty);
      },
    );

    test('a tombstone is NOT applied over an unsynced local edit', () async {
      await db.insert('bom_manual_entries', {
        ...manualEntryRow('e1')..remove('deleted_at'),
        'dirty': 1,
        'pending_delete': 0,
      });

      await repo.upsertBomManualEntriesFromRemote([
        manualEntryRow('e1', deletedAt: '2026-02-01T00:00:00Z'),
      ]);

      final rows = await db.query(
        'bom_manual_entries',
        where: 'id = ?',
        whereArgs: ['e1'],
      );
      expect(rows, hasLength(1));
      expect(rows.single['dirty'], 1);
    });

    test(
      'a normal remote entry still upserts and clears dirty, and deleted_at '
      'is never written locally',
      () async {
        await repo.upsertBomManualEntriesFromRemote([manualEntryRow('e1')]);

        final rows = await db.query(
          'bom_manual_entries',
          where: 'id = ?',
          whereArgs: ['e1'],
        );
        expect(rows, hasLength(1));
        expect(rows.single['dirty'], 0);
        expect(rows.single['material_name'], 'Pipe');
        final columns = (await db.rawQuery('PRAGMA table_info(bom_manual_entries)'))
            .map((r) => r['name'])
            .toSet();
        expect(columns, isNot(contains('deleted_at')));
      },
    );

    test(
      'absence alone removes nothing — tombstones are the only delete signal',
      () async {
        await db.insert('bom_manual_entries', {
          ...manualEntryRow('e1')..remove('deleted_at'),
          'dirty': 0,
          'pending_delete': 0,
        });

        await repo.upsertBomManualEntriesFromRemote([manualEntryRow('other')]);

        expect(
          await db.query('bom_manual_entries', where: 'id = ?', whereArgs: ['e1']),
          hasLength(1),
        );
      },
    );
  });

  // ---- the six immutable BoM tables --------------------------------------

  group('immutable BoM pulls', () {
    // Parent rows first, mirroring SyncService.pullCoreSurveyData's order —
    // with foreign_keys ON, a lines-first pull would throw here.
    Future<void> pullFullHistory() async {
      await repo.upsertBomSnapshotsFromRemote([
        {
          'id': snapshotId,
          'survey_id': siteId,
          'version': 1,
          'status': 'final',
          'finalized_by': 'Engineer',
          'finalized_by_user_id': null,
          'finalized_at': '2026-01-01T00:00:00Z',
        },
      ]);
      await repo.upsertBomSnapshotLinesFromRemote([
        {
          'id': 'sl-1',
          'snapshot_id': snapshotId,
          'sku': 'SKU-1',
          'item': 'Pipe',
          'material_name': 'PVC',
          'item_label': 'P',
          'sensor_size': null,
          'sensor_type': null,
          'unit': 'm',
          'qty': 10.0,
          'group_code': 'A',
          'source': 'auto',
        },
      ]);
      await repo.upsertBomRevisionsFromRemote([
        {
          'id': revisionId,
          'survey_id': siteId,
          'version': 2,
          'reason': 'site change',
          'created_by': 'Engineer',
          'created_by_user_id': null,
          'created_at': '2026-01-02T00:00:00Z',
        },
      ]);
      await repo.upsertBomRevisionLinesFromRemote([
        {
          'id': 'rl-1',
          'revision_id': revisionId,
          'sku': 'SKU-1',
          'item': 'Pipe',
          'material_name': 'PVC',
          'item_label': 'P',
          'sensor_size': null,
          'sensor_type': null,
          'unit': 'm',
          'qty_delta': -2.0,
          'group_code': 'A',
        },
      ]);
      await repo.upsertBomManualEditSnapshotsFromRemote([
        {
          'id': editSnapshotId,
          'survey_id': siteId,
          'version': 3,
          'based_on_version': 2,
          'edited_by': 'Admin',
          'edited_at': '2026-01-03T00:00:00Z',
          'reason': 'correction',
        },
      ]);
      await repo.upsertBomManualEditSnapshotLinesFromRemote([
        {
          'id': 'el-1',
          'snapshot_id': editSnapshotId,
          'sku': 'SKU-1',
          'item_name': 'Pipe',
          'description': 'hand-corrected',
          'unit': 'm',
          'qty': 7.0,
          'group_code': 'A',
        },
      ]);
    }

    test(
      'a full BoM history pulls onto a device that had none — the core '
      'proof that BoM data is no longer device-trapped',
      () async {
        await pullFullHistory();

        expect(await db.query('bom_snapshots'), hasLength(1));
        expect(await db.query('bom_snapshot_lines'), hasLength(1));
        expect(await db.query('bom_revisions'), hasLength(1));
        expect(await db.query('bom_revision_lines'), hasLength(1));
        expect(await db.query('bom_manual_edit_snapshots'), hasLength(1));
        expect(await db.query('bom_manual_edit_snapshot_lines'), hasLength(1));
      },
    );

    test('pulled rows land clean (dirty=0), so nothing re-pushes', () async {
      await pullFullHistory();

      for (final table in const [
        'bom_snapshots',
        'bom_snapshot_lines',
        'bom_revisions',
        'bom_revision_lines',
        'bom_manual_edit_snapshots',
        'bom_manual_edit_snapshot_lines',
      ]) {
        final rows = await db.query(table);
        expect(rows.single['dirty'], 0, reason: '$table pulled row was dirty');
      }
    });

    test('values survive the round trip intact, including the delta', () async {
      await pullFullHistory();

      final line = (await db.query('bom_snapshot_lines')).single;
      expect(line['qty'], 10.0);
      expect(line['group_code'], 'A');
      expect(line['source'], 'auto');
      expect((await db.query('bom_revision_lines')).single['qty_delta'], -2.0);
      expect(
        (await db.query('bom_manual_edit_snapshot_lines')).single['description'],
        'hand-corrected',
      );
      expect((await db.query('bom_revisions')).single['version'], 2);
    });

    test('re-pulling the same history is idempotent — no duplicate rows', () async {
      await pullFullHistory();
      await pullFullHistory();

      expect(await db.query('bom_snapshots'), hasLength(1));
      expect(await db.query('bom_snapshot_lines'), hasLength(1));
      expect(await db.query('bom_revision_lines'), hasLength(1));
      expect(await db.query('bom_manual_edit_snapshot_lines'), hasLength(1));
    });

    test(
      'these tables are immutable: absence from a later pull removes nothing '
      '— no reconcile, no tombstone',
      () async {
        await pullFullHistory();

        // A complete, successful, non-empty fetch that no longer mentions
        // any of the rows above (e.g. a different survey's history).
        await repo.upsertBomSnapshotsFromRemote([
          {
            'id': 'snap-other',
            'survey_id': siteId,
            'version': 1,
            'status': 'final',
            'finalized_by': 'Engineer',
            'finalized_by_user_id': null,
            'finalized_at': '2026-01-09T00:00:00Z',
          },
        ]);
        await repo.upsertBomRevisionsFromRemote([
          {
            'id': 'rev-other',
            'survey_id': siteId,
            'version': 9,
            'reason': 'x',
            'created_by': 'Engineer',
            'created_by_user_id': null,
            'created_at': '2026-01-09T00:00:00Z',
          },
        ]);

        expect(
          await db.query('bom_snapshots', where: 'id = ?', whereArgs: [snapshotId]),
          hasLength(1),
        );
        expect(
          await db.query('bom_revisions', where: 'id = ?', whereArgs: [revisionId]),
          hasLength(1),
        );
        expect(await db.query('bom_snapshot_lines'), hasLength(1));
      },
    );

    test('an unsynced local BoM row is not clobbered by a pull', () async {
      await db.insert('bom_snapshots', {
        'id': snapshotId,
        'survey_id': siteId,
        'version': 1,
        'status': 'final',
        'finalized_by': 'LOCAL — not yet pushed',
        'finalized_at': '2026-01-01T00:00:00Z',
        'dirty': 1,
      });

      await repo.upsertBomSnapshotsFromRemote([
        {
          'id': snapshotId,
          'survey_id': siteId,
          'version': 1,
          'status': 'final',
          'finalized_by': 'REMOTE',
          'finalized_by_user_id': null,
          'finalized_at': '2026-01-01T00:00:00Z',
        },
      ]);

      final row = (await db.query('bom_snapshots')).single;
      expect(row['finalized_by'], 'LOCAL — not yet pushed');
      expect(row['dirty'], 1);
    });

    test(
      'lines are rejected by the FK if their parent has not been pulled '
      '— proves the parent-before-lines pull order is load-bearing',
      () async {
        expect(
          () => repo.upsertBomSnapshotLinesFromRemote([
            {
              'id': 'orphan',
              'snapshot_id': 'no-such-snapshot',
              'sku': null,
              'item': 'Pipe',
              'material_name': null,
              'item_label': null,
              'sensor_size': null,
              'sensor_type': null,
              'unit': 'm',
              'qty': 1.0,
              'group_code': 'A',
              'source': 'auto',
            },
          ]),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });
}
