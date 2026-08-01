// Real-SQLite tests (via sqflite_common_ffi, not the in-memory repository
// stub) for Full sync Group 1's blocks-push fix — exercises
// SqfliteSurveyRepository directly and queries actual row-level state, per
// the debugging protocol's requirement for local SQLite-query evidence
// before any device test. Schema here is copied from app_database.dart's
// onCreate (sites/blocks/client_inputs only — the minimum this repository
// code path touches).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

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
    await db.execute('''
      CREATE TABLE blocks (
        id             TEXT PRIMARY KEY,
        site_id        TEXT NOT NULL,
        position       INTEGER NOT NULL,
        label          TEXT NOT NULL,
        dirty          INTEGER NOT NULL DEFAULT 1,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        sync_blocked   INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE client_inputs (
        site_id TEXT PRIMARY KEY,
        dirty   INTEGER NOT NULL DEFAULT 1
      )
    ''');
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  test(
    'createSite with initial blocks: each block row gets a stable uuid-shaped '
    'id and dirty=1',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A', 'B']);

      final rows = await db.query(
        'blocks',
        where: 'site_id = ?',
        whereArgs: [site.id],
        orderBy: 'position',
      );
      expect(rows, hasLength(2));
      for (final row in rows) {
        final id = row['id'] as String;
        // uuid v4: 36 chars, hyphenated, not a small sequential integer.
        expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
        expect(row['dirty'], 1);
        expect(row['pending_delete'], 0);
      }
      expect(rows[0]['label'], 'A');
      expect(rows[1]['label'], 'B');
    },
  );

  test(
    'updateSiteBlocks adding a new block: only the new block is a fresh '
    'dirty row, the untouched one keeps its id and is NOT re-dirtied',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A']);
      final before = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      final originalId = before.single['id'] as String;
      await repo.markBlockSynced(originalId); // simulate: already pushed once

      await repo.updateSiteBlocks(site.id, ['A', 'B']);

      final rows = await db.query(
        'blocks',
        where: 'site_id = ?',
        whereArgs: [site.id],
        orderBy: 'position',
      );
      expect(rows, hasLength(2));
      // Position 0 ('A') is the same row, same id, and — critically — still
      // dirty=0: an edit elsewhere in the list must never re-dirty a block
      // nobody touched (this is exactly what caused the ghost-resurrection
      // bug under the old delete-all-and-reinsert approach).
      expect(rows[0]['id'], originalId);
      expect(rows[0]['label'], 'A');
      expect(rows[0]['dirty'], 0);
      // Position 1 ('B') is new: fresh id, dirty=1.
      expect(rows[1]['label'], 'B');
      expect(rows[1]['dirty'], 1);
      expect(rows[1]['id'], isNot(originalId));
    },
  );

  test(
    'updateSiteBlocks removing a block: tombstoned (pending_delete=1, '
    'dirty=1), row still physically present until hardDeleteBlock',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A', 'B']);
      final beforeRows = await db.query(
        'blocks',
        where: 'site_id = ?',
        whereArgs: [site.id],
        orderBy: 'position',
      );
      for (final row in beforeRows) {
        await repo.markBlockSynced(row['id'] as String);
      }
      final bId = beforeRows[1]['id'] as String;

      await repo.updateSiteBlocks(site.id, ['A']);

      final rows = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      expect(rows, hasLength(2)); // still physically present
      final tombstoned = rows.singleWhere((r) => r['id'] == bId);
      expect(tombstoned['pending_delete'], 1);
      expect(tombstoned['dirty'], 1);

      // getBlocks (the read path every normal caller uses) must not show it.
      final active = await repo.getBlocks(site.id);
      expect(active.map((b) => b.label), ['A']);

      // getPendingDeleteBlockIds (what the sync push loop reads) must see it.
      expect(await repo.getPendingDeleteBlockIds(site.id), [bId]);
    },
  );

  test(
    'getBlocks(dirtyOnly: true) returns exactly the rows a push would '
    'pick up — confirms the generated push set matches what changed',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A', 'B']);
      final rows = await db.query(
        'blocks',
        where: 'site_id = ?',
        whereArgs: [site.id],
        orderBy: 'position',
      );
      await repo.markBlockSynced(rows[0]['id'] as String); // A synced
      // B stays dirty (never marked synced).

      await repo.updateSiteBlocks(site.id, ['A', 'B-edited']);

      final dirty = await repo.getBlocks(site.id, dirtyOnly: true);
      expect(dirty, hasLength(1));
      expect(dirty.single.label, 'B-edited');
      expect(dirty.single.id, rows[1]['id']);
    },
  );

  test(
    'hardDeleteBlock removes the tombstoned row for real — simulates the '
    'push loop after a confirmed remote delete',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A', 'B']);
      final rows = await db.query(
        'blocks',
        where: 'site_id = ?',
        whereArgs: [site.id],
        orderBy: 'position',
      );
      for (final row in rows) {
        await repo.markBlockSynced(row['id'] as String);
      }
      final bId = rows[1]['id'] as String;
      await repo.updateSiteBlocks(site.id, ['A']);

      await repo.hardDeleteBlock(bId);

      final remaining = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      expect(remaining, hasLength(1));
      expect(remaining.single['id'], isNot(bId));
    },
  );

  test(
    'unrelated site edit (updateSite) does not spuriously re-dirty '
    'already-synced blocks — this is the actual fix for the resurrection bug',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A', 'B']);
      final rows = await db.query(
        'blocks',
        where: 'site_id = ?',
        whereArgs: [site.id],
        orderBy: 'position',
      );
      for (final row in rows) {
        await repo.markBlockSynced(row['id'] as String);
      }

      // Edit only the site's name — blocks list passed back unchanged.
      await repo.updateSite(site.copyWith(name: 'Renamed Site'));

      final afterRows = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      for (final row in afterRows) {
        expect(
          row['dirty'],
          0,
          reason: 'block ${row['id']} was re-dirtied by an unrelated site edit',
        );
      }
    },
  );

  // ---- deleted_at explicit tombstone (Issue 2: delete propagation) -------

  test(
    'upsertBlocksFromRemote: a remote row with deleted_at set hard-deletes '
    'the matching local (non-dirty) row — explicit, not inferred from absence',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A']);
      final rows = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      final blockId = rows.single['id'] as String;
      await repo.markBlockSynced(blockId); // not dirty — safe to reconcile

      await repo.upsertBlocksFromRemote([
        {
          'id': blockId,
          'site_id': site.id,
          'position': 0,
          'label': 'A',
          'deleted_at': '2026-01-01T00:00:00Z',
        },
      ]);

      final remaining = await db.query('blocks', where: 'id = ?', whereArgs: [blockId]);
      expect(remaining, isEmpty);
    },
  );

  test(
    'upsertBlocksFromRemote: a deleted_at row is NOT applied if the local '
    'row has an unsynced edit — protected exactly like every other pull',
    () async {
      final site = await repo.createSite(name: 'Test Site', blocks: ['A']);
      final rows = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      final blockId = rows.single['id'] as String;
      // Deliberately NOT marked synced — stays dirty=1, simulating a local
      // edit that hasn't reached Supabase yet when this pull happens.

      await repo.upsertBlocksFromRemote([
        {
          'id': blockId,
          'site_id': site.id,
          'position': 0,
          'label': 'A',
          'deleted_at': '2026-01-01T00:00:00Z',
        },
      ]);

      final stillThere = await db.query('blocks', where: 'id = ?', whereArgs: [blockId]);
      expect(stillThere, hasLength(1));
      expect(stillThere.single['dirty'], 1);
    },
  );

  test(
    'upsertBlocksFromRemote: a deleted_at row for a block this device never '
    'had locally is simply skipped, not inserted then deleted',
    () async {
      final site = await repo.createSite(name: 'Test Site');

      await repo.upsertBlocksFromRemote([
        {
          'id': 'never-seen-here',
          'site_id': site.id,
          'position': 0,
          'label': 'ghost',
          'deleted_at': '2026-01-01T00:00:00Z',
        },
      ]);

      final rows = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      expect(rows, isEmpty);
    },
  );

  test(
    'upsertBlocksFromRemote: a normal (non-tombstoned) remote row still '
    'upserts correctly — deleted_at support does not break ordinary pull',
    () async {
      final site = await repo.createSite(name: 'Test Site');

      await repo.upsertBlocksFromRemote([
        {
          'id': 'from-another-device',
          'site_id': site.id,
          'position': 0,
          'label': 'pulled block',
          'deleted_at': null,
        },
      ]);

      final active = await repo.getBlocks(site.id);
      expect(active, hasLength(1));
      expect(active.single.label, 'pulled block');
    },
  );

  // ---- sync_blocked: permanently-unpushable rows -------------------------
  //
  // Reproduces the exact backlog traced on-device: rows dirty forever
  // because RLS (42501) refuses them, retried and re-failing every sync.

  test(
    'a sync-blocked site leaves the push queue but keeps its local edit '
    'and stays visible in normal reads',
    () async {
      final site = await repo.createSite(name: 'Stuck Site');
      expect((await repo.getSites(dirtyOnly: true)).map((s) => s.id),
          contains(site.id));

      await repo.markSiteSyncBlocked(site.id);

      // Gone from the push queue — this is what stops the infinite retry.
      expect((await repo.getSites(dirtyOnly: true)).map((s) => s.id),
          isNot(contains(site.id)));
      // Still a normal, visible row with its local edit preserved.
      expect((await repo.getSites()).map((s) => s.id), contains(site.id));
      final raw = await db.query('sites', where: 'id = ?', whereArgs: [site.id]);
      expect(raw.single['dirty'], 1, reason: 'local edit must NOT be discarded');
      expect(raw.single['sync_blocked'], 1);
      expect(await repo.countSyncBlocked(), 1);
    },
  );

  test('a sync-blocked block leaves the push queue but keeps its local edit',
      () async {
    final site = await repo.createSite(name: 'S', blocks: ['A']);
    final blockId =
        (await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]))
            .single['id'] as String;

    await repo.markBlockSyncBlocked(blockId);

    expect(await repo.getBlocks(site.id, dirtyOnly: true), isEmpty);
    expect((await repo.getBlocks(site.id)).map((b) => b.id), contains(blockId));
    final raw = await db.query('blocks', where: 'id = ?', whereArgs: [blockId]);
    expect(raw.single['dirty'], 1);
    expect(await repo.countSyncBlocked(), 1);
  });

  test(
    'a blocked site self-heals when the authoritative remote version is '
    'pulled — remote wins, both flags clear, row rejoins normal sync',
    () async {
      final site = await repo.createSite(name: 'Locally Renamed');
      await repo.markSiteSyncBlocked(site.id);
      expect(await repo.countSyncBlocked(), 1);

      await repo.upsertSitesFromRemote([
        {
          'id': site.id,
          'name': 'Authoritative Remote Name',
          'status': 'assigned',
          'assigned_to': 'someone',
          'assigned_to_user_id': 'u-other',
          'bom_locked': false,
          'archived': false,
        },
      ]);

      final raw = await db.query('sites', where: 'id = ?', whereArgs: [site.id]);
      expect(raw.single['name'], 'Authoritative Remote Name');
      expect(raw.single['sync_blocked'], 0);
      expect(raw.single['dirty'], 0);
      expect(await repo.countSyncBlocked(), 0);
    },
  );

  test(
    'a blocked tombstoned block stops re-attempting its refused remote '
    'delete (getPendingDeleteBlockIds excludes it)',
    () async {
      final site = await repo.createSite(name: 'S', blocks: ['A', 'B']);
      final rows = await db.query('blocks',
          where: 'site_id = ?', whereArgs: [site.id], orderBy: 'position');
      for (final r in rows) {
        await repo.markBlockSynced(r['id'] as String);
      }
      final bId = rows[1]['id'] as String;
      await repo.updateSiteBlocks(site.id, ['A']); // tombstones B
      expect(await repo.getPendingDeleteBlockIds(site.id), [bId]);

      await repo.markBlockSyncBlocked(bId);

      expect(await repo.getPendingDeleteBlockIds(site.id), isEmpty);
      expect(await repo.countSyncBlocked(), 1);
    },
  );

  test('countSyncBlocked sums sites and blocks together', () async {
    final site = await repo.createSite(name: 'S', blocks: ['A']);
    final blockId =
        (await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]))
            .single['id'] as String;
    await repo.markSiteSyncBlocked(site.id);
    await repo.markBlockSyncBlocked(blockId);
    expect(await repo.countSyncBlocked(), 2);
  });

  // ---- reconcileDeletes: site/block reassignment propagation -------------
  //
  // Reproduces the exact stale-row-on-reassignment bug traced on-device: a
  // site reassigned away from this account (or genuinely deleted) used to
  // linger locally forever, because absence from a pull was never treated
  // as a delete signal for an RLS-scoped table. sites/blocks now opt in
  // (reconcileDeletes: true) since fetchSites/fetchBlocks (_fetchAllRows)
  // either return the complete account-scoped set or throw — a throw means
  // upsertSitesFromRemote/upsertBlocksFromRemote are never called at all,
  // so a non-empty successful result really is complete.

  test(
    'upsertSitesFromRemote: a clean local site absent from a complete '
    'remote fetch is removed — the reassigned-away case',
    () async {
      final stays = await repo.createSite(name: 'Stays');
      final reassignedAway = await repo.createSite(name: 'Reassigned Away');
      await repo.markSiteSynced(stays.id);
      await repo.markSiteSynced(reassignedAway.id);

      // Remote's authoritative set no longer includes reassignedAway.
      await repo.upsertSitesFromRemote([
        {
          'id': stays.id,
          'name': 'Stays',
          'status': null,
          'assigned_to': null,
          'assigned_to_user_id': null,
          'bom_locked': false,
          'archived': false,
        },
      ]);

      final remaining = await db.query('sites');
      expect(remaining.map((r) => r['id']), [stays.id]);
    },
  );

  test(
    'upsertSitesFromRemote: a sync-blocked site absent from a complete '
    'remote fetch is removed — the exact backlog confirmed stuck on-device',
    () async {
      final site = await repo.createSite(name: 'Blocked and reassigned away');
      await repo.markSiteSyncBlocked(site.id);

      // Non-empty fetch that simply no longer includes this site (the
      // empty case is a separate guard, tested below).
      await repo.upsertSitesFromRemote([
        {
          'id': 'some-other-site',
          'name': 'Unrelated',
          'status': null,
          'assigned_to': null,
          'assigned_to_user_id': null,
          'bom_locked': false,
          'archived': false,
        },
      ]);

      final remaining = await db.query('sites', where: 'id = ?', whereArgs: [site.id]);
      expect(remaining, isEmpty);
    },
  );

  test(
    'upsertSitesFromRemote: a site with a genuine unsynced local edit is '
    'NOT removed even when absent from remote — protected like every other pull',
    () async {
      final site = await repo.createSite(name: 'Unsynced local edit');
      // Deliberately not marked synced — stays dirty=1.

      await repo.upsertSitesFromRemote([
        {
          'id': 'some-other-site',
          'name': 'Unrelated',
          'status': null,
          'assigned_to': null,
          'assigned_to_user_id': null,
          'bom_locked': false,
          'archived': false,
        },
      ]);

      final remaining = await db.query('sites', where: 'id = ?', whereArgs: [site.id]);
      expect(remaining, hasLength(1));
      expect(remaining.single['dirty'], 1);
    },
  );

  test(
    'upsertSitesFromRemote: an empty remote result removes nothing — a '
    'partial/failed-looking pull must never wipe the local table',
    () async {
      final a = await repo.createSite(name: 'A');
      final b = await repo.createSite(name: 'B');
      await repo.markSiteSynced(a.id);
      await repo.markSiteSynced(b.id);

      await repo.upsertSitesFromRemote([]);

      final remaining = await db.query('sites');
      expect(remaining.map((r) => r['id']).toSet(), {a.id, b.id});
    },
  );

  test(
    'upsertBlocksFromRemote: a clean local block absent from a complete '
    'remote fetch is removed — its site was reassigned away',
    () async {
      final site = await repo.createSite(name: 'S', blocks: ['A']);
      final blockId =
          (await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]))
              .single['id'] as String;
      await repo.markBlockSynced(blockId);

      // Non-empty fetch that simply no longer includes this block (the
      // empty case is a separate guard, tested below).
      await repo.upsertBlocksFromRemote([
        {
          'id': 'from-another-site',
          'site_id': 'some-other-site',
          'position': 0,
          'label': 'unrelated',
          'deleted_at': null,
        },
      ]);

      final remaining = await db.query('blocks', where: 'id = ?', whereArgs: [blockId]);
      expect(remaining, isEmpty);
    },
  );

  test(
    'upsertBlocksFromRemote: a dirty block absent from remote is NOT '
    'removed — protected exactly like every other pull',
    () async {
      final site = await repo.createSite(name: 'S', blocks: ['A']);
      final blockId =
          (await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]))
              .single['id'] as String;
      // Deliberately not marked synced — stays dirty=1.

      await repo.upsertBlocksFromRemote([
        {
          'id': 'from-another-site',
          'site_id': 'some-other-site',
          'position': 0,
          'label': 'unrelated',
          'deleted_at': null,
        },
      ]);

      final remaining = await db.query('blocks', where: 'id = ?', whereArgs: [blockId]);
      expect(remaining, hasLength(1));
      expect(remaining.single['dirty'], 1);
    },
  );

  test(
    'upsertBlocksFromRemote: an empty remote result removes nothing — a '
    'partial/failed-looking pull must never wipe the local table',
    () async {
      final site = await repo.createSite(name: 'S', blocks: ['A', 'B']);
      final rows = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      for (final row in rows) {
        await repo.markBlockSynced(row['id'] as String);
      }

      await repo.upsertBlocksFromRemote([]);

      final remaining = await db.query('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      expect(remaining, hasLength(2));
    },
  );
}
