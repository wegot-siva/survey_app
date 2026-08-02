// Real-SQLite tests (via sqflite_common_ffi) for Full sync Group 4 — the
// photos pull, its tombstone path, and the local-file bookkeeping that goes
// with it.
//
// Two things make photos different from every other table pulled so far:
//
//   * `local_path` names a file on one specific device and is meaningless
//     anywhere else, so it is never in a remote row. A pull must therefore
//     leave an existing row's path alone and start a new row's as null.
//   * Removing a photo row isn't enough — the image file has to go too, or
//     every device accumulates the bytes of deleted photos forever. The pull
//     reports the paths it orphaned so the caller can delete them.
//
// Schema is the minimum this path touches, copied from app_database.dart's
// _createPhotosTable (whose helpers are private, so a test can't call them).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:survey_app/data/sqflite_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/photo_file_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SqfliteSurveyRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
    repo = SqfliteSurveyRepository(db, IdService());
  });

  tearDown(() => db.close());

  Map<String, dynamic> remoteRow(
    String id, {
    String? deletedAt,
    String? remotePath = 'photos/x.jpg',
    int position = 0,
  }) => {
    'id': id,
    'owner_type': 'source_point',
    'owner_id': 'sp-1',
    'slot': 'power_source',
    'position': position,
    'remote_path': remotePath,
    'site_id': 'site-1',
    'deleted_at': deletedAt,
  };

  Future<void> insertLocal(
    String id, {
    String? localPath,
    String? remotePath = 'photos/x.jpg',
    int dirty = 0,
    int position = 0,
  }) => db.insert('photos', {
    'id': id,
    'owner_type': 'source_point',
    'owner_id': 'sp-1',
    'slot': 'power_source',
    'position': position,
    'local_path': localPath,
    'remote_path': remotePath,
    'site_id': 'site-1',
    'dirty': dirty,
  });

  group('photos pull', () {
    test('a new remote photo is inserted clean, with no local file yet', () async {
      final orphaned = await repo.upsertPhotosFromRemote([remoteRow('p1')]);

      final row = (await db.query('photos')).single;
      expect(row['id'], 'p1');
      expect(row['dirty'], 0);
      expect(row['local_path'], isNull, reason: 'file is downloaded separately');
      expect(row['remote_path'], 'photos/x.jpg');
      expect(orphaned, isEmpty);
    });

    test(
      "an existing row's local_path survives a pull — the remote row has no "
      'such column, and losing it would strand the downloaded file',
      () async {
        await insertLocal('p1', localPath: '/data/photos/p1.jpg', position: 0);

        await repo.upsertPhotosFromRemote([remoteRow('p1', position: 7)]);

        final row = (await db.query('photos')).single;
        expect(row['local_path'], '/data/photos/p1.jpg');
        expect(row['position'], 7, reason: 'remote fields still applied');
      },
    );

    test(
      'a tombstoned photo is hard-deleted and its local file path reported '
      'for cleanup',
      () async {
        await insertLocal('p1', localPath: '/data/photos/p1.jpg');

        final orphaned = await repo.upsertPhotosFromRemote([
          remoteRow('p1', deletedAt: '2026-01-01T00:00:00Z'),
        ]);

        expect(await db.query('photos'), isEmpty);
        expect(orphaned, ['/data/photos/p1.jpg']);
      },
    );

    test(
      'a tombstoned photo this device never downloaded reports no file, but '
      'is still removed',
      () async {
        await insertLocal('p1', localPath: null);

        final orphaned = await repo.upsertPhotosFromRemote([
          remoteRow('p1', deletedAt: '2026-01-01T00:00:00Z'),
        ]);

        expect(await db.query('photos'), isEmpty);
        expect(orphaned, isEmpty);
      },
    );

    test(
      'a tombstoned photo this device never had is skipped, not inserted '
      'then deleted',
      () async {
        final orphaned = await repo.upsertPhotosFromRemote([
          remoteRow('never-seen', deletedAt: '2026-01-01T00:00:00Z'),
        ]);

        expect(await db.query('photos'), isEmpty);
        expect(orphaned, isEmpty);
      },
    );

    test(
      'a tombstone is NOT applied over an unsynced local photo — and its '
      'file is not deleted either',
      () async {
        await insertLocal('p1', localPath: '/data/photos/p1.jpg', dirty: 1);

        final orphaned = await repo.upsertPhotosFromRemote([
          remoteRow('p1', deletedAt: '2026-01-01T00:00:00Z'),
        ]);

        final row = (await db.query('photos')).single;
        expect(row['dirty'], 1);
        expect(row['local_path'], '/data/photos/p1.jpg');
        expect(orphaned, isEmpty, reason: 'file must survive with the row');
      },
    );

    test('absence alone removes nothing — tombstones are the only signal', () async {
      await insertLocal('p1', localPath: '/data/photos/p1.jpg');

      final orphaned = await repo.upsertPhotosFromRemote([remoteRow('other')]);

      expect(
        await db.query('photos', where: 'id = ?', whereArgs: ['p1']),
        hasLength(1),
      );
      expect(orphaned, isEmpty);
    });

    test('deleted_at is never written into local storage', () async {
      await repo.upsertPhotosFromRemote([remoteRow('p1')]);

      final columns = (await db.rawQuery('PRAGMA table_info(photos)'))
          .map((r) => r['name'])
          .toSet();
      expect(columns, isNot(contains('deleted_at')));
    });
  });

  group('getPhotosMissingLocalFile', () {
    test('returns only pulled photos whose bytes this device lacks', () async {
      // Needs downloading: uploaded remotely, no local copy.
      await insertLocal('needs-download', localPath: null);
      // Already has both — nothing to do.
      await insertLocal('complete', localPath: '/data/photos/complete.jpg');
      // Captured here, not yet uploaded — the opposite direction.
      await insertLocal('awaiting-upload',
          localPath: '/data/photos/new.jpg', remotePath: null, dirty: 1);
      // Empty strings are treated the same as null on both columns.
      await insertLocal('blank-paths', localPath: '', remotePath: '');

      final missing = await repo.getPhotosMissingLocalFile();

      expect(missing.map((p) => p.id), ['needs-download']);
    });

    test('is empty once every photo has its file', () async {
      await insertLocal('p1', localPath: '/data/photos/p1.jpg');
      expect(await repo.getPhotosMissingLocalFile(), isEmpty);
    });
  });

  group('setPhotoLocalPath', () {
    test(
      'records the downloaded file without re-dirtying the row — otherwise '
      'every pulled photo would queue itself for a pointless re-push',
      () async {
        await insertLocal('p1', localPath: null); // pulled, clean

        await repo.setPhotoLocalPath('p1', '/data/photos/p1.jpg');

        final row = (await db.query('photos')).single;
        expect(row['local_path'], '/data/photos/p1.jpg');
        expect(row['dirty'], 0, reason: 'must stay clean');
        expect(await repo.getPhotosMissingLocalFile(), isEmpty);
      },
    );

    test('leaves a genuinely dirty photo dirty', () async {
      await insertLocal('p1', localPath: null, dirty: 1);

      await repo.setPhotoLocalPath('p1', '/data/photos/p1.jpg');

      expect((await db.query('photos')).single['dirty'], 1);
    });
  });

  group('PhotoFileStore.deleteLocalFile', () {
    test('deletes the file behind a tombstoned photo', () async {
      final dir = await Directory.systemTemp.createTemp('photo_cleanup_test');
      final file = File('${dir.path}/p1.jpg');
      await file.writeAsBytes([1, 2, 3]);

      await PhotoFileStore().deleteLocalFile(file.path);

      expect(await file.exists(), isFalse);
      await dir.delete(recursive: true);
    });

    test('a already-missing file is not an error', () async {
      final dir = await Directory.systemTemp.createTemp('photo_cleanup_test');
      final path = '${dir.path}/never-existed.jpg';

      await expectLater(PhotoFileStore().deleteLocalFile(path), completes);

      await dir.delete(recursive: true);
    });
  });
}
