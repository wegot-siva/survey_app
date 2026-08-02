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
    for (final t in _childTables) {
      await db.execute('''
        CREATE TABLE $t (
          id TEXT PRIMARY KEY, site_id TEXT NOT NULL,
          dirty INTEGER NOT NULL DEFAULT 1,
          pending_delete INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (site_id) REFERENCES sites (id) ON DELETE CASCADE
        )
      ''');
    }
    await db.execute('''
      CREATE TABLE bom_manual_entries (
        id TEXT PRIMARY KEY, survey_id TEXT NOT NULL,
        material_name TEXT NOT NULL, unit TEXT NOT NULL, qty REAL NOT NULL,
        group_code TEXT NOT NULL, added_by TEXT NOT NULL, added_at TEXT NOT NULL,
        dirty INTEGER NOT NULL DEFAULT 1,
        pending_delete INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (survey_id) REFERENCES sites (id) ON DELETE CASCADE
      )
    ''');
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
  Future<void> pullWithout(String goneSiteId, {required String keepSiteId}) =>
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
}
