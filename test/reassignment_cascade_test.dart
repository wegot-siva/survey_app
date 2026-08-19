// Why source_points / inlet_points / duct_loras / gateways /
// bom_manual_entries deliberately keep reconcileDeletes = false, even though
// sites and blocks turned it on.
//
// The worry these tests answer: when a site is reassigned away, it leaves the
// old assignee's RLS scope, so every one of its child rows leaves too. Sites
// handles its own row via reconcileDeletes (see upsertSitesFromRemote). The
// question was whether the children then linger locally as stale orphans,
// needing reconcileDeletes of their own.
//
// They don't. Local storage runs with `PRAGMA foreign_keys = ON` (see
// app_database.dart's onConfigure) and every one of these tables declares
// `FOREIGN KEY (...) REFERENCES sites (id) ON DELETE CASCADE`, so deleting
// the site row takes its children with it in the same transaction.
//
// That matters because turning reconcileDeletes on for the child tables would
// be strictly worse than a no-op: it can't fix anything the cascade hasn't
// already handled, and it would re-introduce absence-based deletion on tables
// where an explicit deleted_at tombstone (Full sync Groups 2 and 3) is
// already the correct and safe signal for a real delete. These tests exist so
// that reasoning is checkable rather than a comment someone has to trust.
//
// The structural guarantee underneath: a child's RLS predicate is purely
// can_access_site(site_id) — derived entirely from its parent — so a child
// can only ever leave RLS scope by its parent leaving first. There is no case
// where a child needs reconciling while its site remains visible; a genuine
// per-row delete is a tombstone, which is checked explicitly.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';

import 'support/site_cascade_schema.dart';

const _childTables = ['source_points', 'inlet_points', 'duct_loras', 'gateways'];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    // The whole point of these tests — matches app_database.dart's
    // onConfigure, without which the cascade below silently wouldn't fire.
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('''
      CREATE TABLE sites (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, status TEXT,
        assigned_to TEXT, assigned_to_user_id TEXT,
        bom_locked INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        address TEXT, client_name TEXT, client_contact TEXT,
        dirty INTEGER NOT NULL DEFAULT 1, sync_blocked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // Every table the unsynced-work guard inspects. Shared, because that
    // guard refuses to skip a table it cannot read — see the helper's doc.
    await createSiteCascadeTables(db);
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  Future<void> seedSiteWithChildren(String siteId, {required int dirty}) async {
    await db.insert('sites', {'id': siteId, 'name': siteId, 'dirty': dirty});
    for (final t in _childTables) {
      await db.insert(t, {
        'id': '$siteId-$t',
        'site_id': siteId,
        'dirty': 0,
        'pending_delete': 0,
      });
    }
    await db.insert('bom_manual_entries', {
      'id': '$siteId-bme',
      'survey_id': siteId,
      'material_name': 'X',
      'unit': 'm',
      'qty': 1.0,
      'group_code': 'D',
      'added_by': 'engineer',
      'added_at': '2026-01-01T00:00:00Z',
      'dirty': 0,
      'pending_delete': 0,
    });
  }

  /// A complete, successful pull as the OLD assignee: the reassigned-away
  /// site is simply no longer among the rows RLS returns.
  /// Returns the names of any sites the pull deliberately preserved.
  Future<List<String>> pullWithout(
    String goneSiteId, {
    required String keepSiteId,
  }) =>
      repo.upsertSitesFromRemote([
        {
          'id': keepSiteId,
          'name': keepSiteId,
          'status': null,
          'assigned_to': null,
          'assigned_to_user_id': null,
          'bom_locked': false,
          'archived': false,
        },
      ]);

  test(
    'a reassigned-away site takes every child table with it — no stale '
    'orphans, so the child tables need no reconcileDeletes of their own',
    () async {
      await seedSiteWithChildren('gone', dirty: 0);
      await seedSiteWithChildren('keep', dirty: 0);

      await pullWithout('gone', keepSiteId: 'keep');

      expect(await db.query('sites', where: 'id = ?', whereArgs: ['gone']), isEmpty);
      for (final t in [..._childTables, 'bom_manual_entries']) {
        final left = await db.query(t);
        expect(
          left.map((r) => r['id']),
          ['keep-${t == 'bom_manual_entries' ? 'bme' : t}'],
          reason: '$t should keep only the surviving site\'s child',
        );
      }
    },
  );

  test(
    'children survive when their site does — the cascade only fires on a '
    'site the reconcile actually removed',
    () async {
      await seedSiteWithChildren('keep', dirty: 0);

      await pullWithout('nothing-was-removed', keepSiteId: 'keep');

      for (final t in [..._childTables, 'bom_manual_entries']) {
        expect(await db.query(t), hasLength(1), reason: '$t lost a live child');
      }
    },
  );

  test(
    'a site with its own unsynced edit is protected, and so are its children '
    '— an in-flight local change is never destroyed by a reassignment pull',
    () async {
      await seedSiteWithChildren('gone', dirty: 1); // unpushed local edit
      await seedSiteWithChildren('keep', dirty: 0);

      await pullWithout('gone', keepSiteId: 'keep');

      expect(
        await db.query('sites', where: 'id = ?', whereArgs: ['gone']),
        hasLength(1),
      );
      for (final t in [..._childTables, 'bom_manual_entries']) {
        expect(await db.query(t), hasLength(2), reason: '$t lost a protected child');
      }
    },
  );

  test(
    'an empty pull removes nothing, so no cascade fires either — the '
    'partial/failed-fetch guard still protects every child table',
    () async {
      await seedSiteWithChildren('gone', dirty: 0);

      await repo.upsertSitesFromRemote([]);

      expect(await db.query('sites'), hasLength(1));
      for (final t in [..._childTables, 'bom_manual_entries']) {
        expect(await db.query(t), hasLength(1), reason: '$t was wrongly cascaded');
      }
    },
  );

  // ---------------------------------------------------------------------
  // The gap that let BLOCKER 2 ship: every case above varies only the
  // SITE's dirty flag, and seedSiteWithChildren always seeds children
  // clean. But editing a source point marks the POINT dirty and leaves the
  // site clean — so the one shape that actually loses field work was the
  // one shape never tested.
  // ---------------------------------------------------------------------

  test(
    'a CLEAN site whose CHILD is dirty is preserved — that unsynced '
    'work must not be cascaded away',
    () async {
      await seedSiteWithChildren('gone', dirty: 0); // site itself is clean
      await seedSiteWithChildren('keep', dirty: 0);
      // A day in the field: the point was edited, the site row was not.
      await db.update('source_points', {'dirty': 1},
          where: 'id = ?', whereArgs: ['gone-source_points']);

      final preserved = await pullWithout('gone', keepSiteId: 'keep');

      expect(
        await db.query('sites', where: 'id = ?', whereArgs: ['gone']),
        hasLength(1),
        reason: 'the site must be kept, or the cascade destroys the work',
      );
      expect(
        await db.query('source_points', where: 'dirty = 1'),
        hasLength(1),
        reason: 'the unsynced point is the whole point of the guard',
      );
      expect(preserved, ['gone'],
          reason: 'the user must be told WHICH site, by name');
    },
  );

  test('a dirty child in ANY cascading table preserves its site', () async {
    // One table at a time, so a guard that checks only the obvious ones
    // (source_points) fails here rather than in the field.
    final cases = <String, Map<String, Object?>>{
      'inlet_points': {'id': 'x', 'site_id': 'gone', 'dirty': 1},
      'duct_loras': {'id': 'x', 'site_id': 'gone', 'dirty': 1},
      'gateways': {'id': 'x', 'site_id': 'gone', 'dirty': 1},
      'blocks': {
        'id': 'x', 'site_id': 'gone', 'position': 0, 'label': 'A', 'dirty': 1,
      },
      'client_inputs': {'site_id': 'gone', 'dirty': 1},
      'footers': {'site_id': 'gone', 'dirty': 1},
      'photos': {
        'id': 'x', 'owner_type': 'source_point', 'owner_id': 'o',
        'slot': 's', 'site_id': 'gone', 'dirty': 1,
      },
      'bom_snapshots': {'id': 'x', 'survey_id': 'gone', 'dirty': 1},
      'bom_revisions': {'id': 'x', 'survey_id': 'gone', 'dirty': 1},
      'bom_manual_edit_snapshots': {'id': 'x', 'survey_id': 'gone', 'dirty': 1},
    };
    for (final entry in cases.entries) {
      await db.delete('sites');
      await seedSiteWithChildren('gone', dirty: 0);
      await seedSiteWithChildren('keep', dirty: 0);
      await db.insert(entry.key, entry.value);

      final preserved = await pullWithout('gone', keepSiteId: 'keep');

      expect(
        await db.query('sites', where: 'id = ?', whereArgs: ['gone']),
        hasLength(1),
        reason: 'a dirty row in ${entry.key} did not protect its site',
      );
      expect(preserved, ['gone'], reason: 'unreported for ${entry.key}');
    }
  });

  test('a dirty BoM LINE preserves its site — lines are tracked separately '
      'from the snapshot row and can be the only thing left unpushed',
      () async {
    await seedSiteWithChildren('gone', dirty: 0);
    await seedSiteWithChildren('keep', dirty: 0);
    // Snapshot row itself already pushed; only its lines are outstanding.
    await db.insert('bom_snapshots',
        {'id': 'snap-1', 'survey_id': 'gone', 'dirty': 0});
    await db.insert('bom_snapshot_lines',
        {'id': 'line-1', 'snapshot_id': 'snap-1', 'dirty': 1});

    final preserved = await pullWithout('gone', keepSiteId: 'keep');

    expect(
      await db.query('sites', where: 'id = ?', whereArgs: ['gone']),
      hasLength(1),
    );
    expect(preserved, ['gone']);
  });

  test(
    'a pending_delete child also counts as unsynced work — the delete has '
    'not reached the server yet either',
    () async {
      await seedSiteWithChildren('gone', dirty: 0);
      await seedSiteWithChildren('keep', dirty: 0);
      await db.update('source_points', {'dirty': 0, 'pending_delete': 1},
          where: 'id = ?', whereArgs: ['gone-source_points']);

      final preserved = await pullWithout('gone', keepSiteId: 'keep');

      expect(
        await db.query('sites', where: 'id = ?', whereArgs: ['gone']),
        hasLength(1),
      );
      expect(preserved, ['gone']);
    },
  );

  test(
    'a fully clean site still cascades away exactly as before — the guard '
    'must not turn reconcile into a no-op',
    () async {
      await seedSiteWithChildren('gone', dirty: 0);
      await seedSiteWithChildren('keep', dirty: 0);

      final preserved = await pullWithout('gone', keepSiteId: 'keep');

      expect(await db.query('sites'), hasLength(1));
      for (final t in [..._childTables, 'bom_manual_entries']) {
        expect(await db.query(t), hasLength(1),
            reason: '$t should have cascaded away with its clean site');
      }
      expect(preserved, isEmpty,
          reason: 'nothing was preserved, so nothing to warn about');
    },
  );
}
