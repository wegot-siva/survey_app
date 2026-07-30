// Real-SQLite tests for account-scoped local databases (the shared-device
// cross-account sync fix) — exercises openAppDatabaseInDirectory against a
// real temp directory, confirming file-level isolation and the one-time
// legacy-file claim migration.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/services/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('survey_app_db_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('two different user ids get two different, independent database files', () async {
    final dbA = await openAppDatabaseInDirectory(tempDir.path, 'user-a');
    final dbB = await openAppDatabaseInDirectory(tempDir.path, 'user-b');

    await dbA.insert('sites', {'id': 'site-a', 'name': "A's site", 'dirty': 1});
    await dbB.insert('sites', {'id': 'site-b', 'name': "B's site", 'dirty': 1});

    final sitesInA = await dbA.query('sites');
    final sitesInB = await dbB.query('sites');

    expect(sitesInA.map((r) => r['id']), ['site-a']);
    expect(sitesInB.map((r) => r['id']), ['site-b']);
    // Neither account's data is visible from the other's database.
    expect(sitesInA.map((r) => r['id']), isNot(contains('site-b')));
    expect(sitesInB.map((r) => r['id']), isNot(contains('site-a')));

    expect(
      File(p.join(tempDir.path, 'survey_app_user-a.db')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(tempDir.path, 'survey_app_user-b.db')).existsSync(),
      isTrue,
    );

    await dbA.close();
    await dbB.close();
  });

  test(
    'a stale dirty row from a previous account does not appear under a '
    "different account's freshly-opened database",
    () async {
      // Simulates the exact bug this fixes: account A creates a site and it
      // never syncs before the device switches to account B.
      final dbA = await openAppDatabaseInDirectory(tempDir.path, 'user-a');
      await dbA.insert('sites', {
        'id': 'unsynced-site',
        'name': 'Never synced',
        'dirty': 1,
      });
      await dbA.close();

      final dbB = await openAppDatabaseInDirectory(tempDir.path, 'user-b');
      final sitesInB = await dbB.query('sites');
      expect(sitesInB, isEmpty);
      await dbB.close();

      // Account A's data is still there, untouched, for when they return.
      final dbAAgain = await openAppDatabaseInDirectory(tempDir.path, 'user-a');
      final sitesInA = await dbAAgain.query('sites', where: 'id = ?', whereArgs: ['unsynced-site']);
      expect(sitesInA, hasLength(1));
      expect(sitesInA.single['dirty'], 1);
      await dbAAgain.close();
    },
  );

  test(
    'legacy pre-account-scoping database is claimed (renamed) by the first '
    'account to open a database after upgrading',
    () async {
      final legacyPath = await _createRealisticLegacyFile(tempDir.path);
      expect(File(legacyPath).existsSync(), isTrue);

      final claimed = await openAppDatabaseInDirectory(tempDir.path, 'first-user');
      final rows = await claimed.query('sites');
      expect(rows.map((r) => r['id']), ['legacy-site']);
      // The legacy path itself is gone — renamed, not copied.
      expect(File(legacyPath).existsSync(), isFalse);
      await claimed.close();
    },
  );

  test(
    'a second account logging in after the legacy file was already claimed '
    'gets a genuinely fresh, empty database',
    () async {
      await _createRealisticLegacyFile(tempDir.path);

      final first = await openAppDatabaseInDirectory(tempDir.path, 'first-user');
      await first.close();

      // Legacy path is already consumed — a second account must not see it.
      final second = await openAppDatabaseInDirectory(tempDir.path, 'second-user');
      final rows = await second.query('sites');
      expect(rows, isEmpty);
      await second.close();
    },
  );
}

/// Builds a database the real way (via [openAppDatabaseInDirectory], so it
/// ends up on the exact current schema version — a hand-rolled `CREATE
/// TABLE sites (...)` here would leave `PRAGMA user_version` at 0, which
/// `openAppDatabaseInDirectory` would then treat as "never initialized" and
/// run onCreate against on the next open, colliding with the table that's
/// already there), then renames the file to the legacy shared-db path to
/// simulate a real pre-account-scoping device. Returns the legacy path.
Future<String> _createRealisticLegacyFile(String docsDirPath) async {
  final db = await openAppDatabaseInDirectory(docsDirPath, '__legacy_source__');
  await db.insert('sites', {
    'id': 'legacy-site',
    'name': 'From before the upgrade',
    'dirty': 0,
  });
  await db.close();
  final legacyPath = p.join(docsDirPath, 'survey_app.db');
  await File(p.join(docsDirPath, 'survey_app___legacy_source__.db')).rename(legacyPath);
  return legacyPath;
}
