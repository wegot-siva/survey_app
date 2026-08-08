// Photo image files must be fetched AFTER a sync run, never inside it.
//
// Measured on device: downloading 12 photos inline added 20.0 s to a 5.6 s
// pull (~1 MB and ~1.7 s each), so the run reported "syncing" for 25.6 s
// even though every row of metadata had been safe locally within the first
// six. That cost is bandwidth-bound rather than round-trip-bound, so no
// amount of batching inside the pull would have touched it — the only fix is
// not to hold the run open for it.
//
// The single-flight guard is not incidental. Syncs overlap in normal use (a
// manual tap during the 30 s cooldown, an auto-sync on reconnect, a run
// starting while a slow download is still going) and nothing marks a photo
// as "being downloaded" — getPhotosMissingLocalFile keys off local_path,
// which is only set once the file has actually landed. Two concurrent passes
// would therefore both see the same rows and download every image twice.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';
import 'package:survey_app/models/survey_photo.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/photo_file_store.dart';
import 'package:survey_app/services/supabase_service.dart';
import 'package:survey_app/services/sync_service.dart';

class _FakeSupabase extends SupabaseService {
  @override
  bool get isConfigured => true;
  @override
  bool get isInitialized => true;
  @override
  Future<void> initIfConfigured() async {}
}

class _FakeRemote extends SupabaseSurveyDataSource {
  final List<String> downloaded = [];

  @override
  Future<Uint8List> downloadPhoto(String objectKey) async {
    downloaded.add(objectKey);
    // Slow enough that a second concurrent pass would overlap it if the
    // single-flight guard were missing.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSites() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBlocks() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchClientInputs() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchFooters() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchSourcePoints() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchInletPoints() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchDuctLoras() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchGateways() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomManualEntries() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomSnapshots() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomSnapshotLines() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomRevisions() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomRevisionLines() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomManualEditSnapshots() async => [];
  @override
  Future<List<Map<String, dynamic>>> fetchBomManualEditSnapshotLines() async =>
      [];
  @override
  Future<List<Map<String, dynamic>>> fetchPhotos() async => [];
}

/// Avoids path_provider, which has no plugin implementation under `flutter
/// test` — the real store would throw MissingPluginException on the first
/// getApplicationDocumentsDirectory call.
class _FakeFileStore extends PhotoFileStore {
  @override
  Future<String> saveDownload(String photoId, Uint8List bytes) async =>
      '/fake/$photoId.jpg';
  @override
  Future<void> deleteLocalFile(String path) async {}
}

/// Serves photos awaiting download; records when each one's path is set.
class _PhotoRepo extends InMemorySurveyRepository {
  _PhotoRepo(this.pending) : super(IdService());

  final List<SurveyPhoto> pending;
  final Map<String, String> pathsSet = {};

  @override
  Future<List<SurveyPhoto>> getPhotosMissingLocalFile() async =>
      pending.where((p) => !pathsSet.containsKey(p.id)).toList();

  @override
  Future<void> setPhotoLocalPath(String id, String localPath) async {
    pathsSet[id] = localPath;
  }
}

SurveyPhoto _photo(String id) => SurveyPhoto(
      id: id,
      ownerType: 'source_point',
      ownerId: 'owner-1',
      slot: 'slot-1',
      position: 0,
      localPath: null,
      remotePath: 'photos/$id.jpg',
      siteId: 'site-1',
    );

void main() {
  test('the pull does not download image files — it must not block on them',
      () async {
    final remote = _FakeRemote();
    final repo = _PhotoRepo([_photo('a'), _photo('b')]);
    final service = SyncService(repo, _FakeSupabase(), remote,
        photoFiles: _FakeFileStore());

    final result = await service.pullCoreSurveyData();

    expect(result.success, isTrue);
    expect(remote.downloaded, isEmpty,
        reason: 'downloading inside the pull is exactly what this removed');
  });

  test('the background pass downloads what the pull deliberately skipped',
      () async {
    final remote = _FakeRemote();
    final repo = _PhotoRepo([_photo('a'), _photo('b')]);
    final service = SyncService(repo, _FakeSupabase(), remote,
        photoFiles: _FakeFileStore());

    await service.pullCoreSurveyData();
    await service.downloadMissingPhotoFilesInBackground();

    expect(remote.downloaded, ['photos/a.jpg', 'photos/b.jpg']);
    expect(repo.pathsSet.keys, containsAll(<String>['a', 'b']));
  });

  test('single-flight: overlapping runs download each photo exactly once',
      () async {
    final remote = _FakeRemote();
    final repo = _PhotoRepo([_photo('a'), _photo('b'), _photo('c')]);
    final service = SyncService(repo, _FakeSupabase(), remote,
        photoFiles: _FakeFileStore());

    // Three overlapping triggers, as a manual tap landing on top of an
    // auto-sync would produce.
    await Future.wait([
      service.downloadMissingPhotoFilesInBackground(),
      service.downloadMissingPhotoFilesInBackground(),
      service.downloadMissingPhotoFilesInBackground(),
    ]);

    expect(remote.downloaded.length, 3,
        reason: 'three photos, three downloads — not nine');
    expect(remote.downloaded.toSet().length, 3);
  });

  test('a later run still picks up photos added since the last pass',
      () async {
    final remote = _FakeRemote();
    final repo = _PhotoRepo([_photo('a')]);
    final service = SyncService(repo, _FakeSupabase(), remote,
        photoFiles: _FakeFileStore());

    await service.downloadMissingPhotoFilesInBackground();
    expect(remote.downloaded, ['photos/a.jpg']);

    // The guard must clear when the pass finishes, or no photo pulled after
    // the first sync of a session would ever download.
    repo.pending.add(_photo('d'));
    await service.downloadMissingPhotoFilesInBackground();

    expect(remote.downloaded, ['photos/a.jpg', 'photos/d.jpg']);
  });

  test('a failing download never escapes as an unhandled error, and the next '
      'pass retries it', () async {
    final remote = _ThrowingRemote();
    final repo = _PhotoRepo([_photo('a')]);
    final service = SyncService(repo, _FakeSupabase(), remote,
        photoFiles: _FakeFileStore());

    // Must complete normally rather than throwing: the sync run that starts
    // this has already reported success, and a photo that didn't arrive is
    // not a reason to fail it.
    await service.downloadMissingPhotoFilesInBackground();

    expect(repo.pathsSet, isEmpty,
        reason: 'nothing landed, so the row stays eligible for a retry');

    remote.fail = false;
    await service.downloadMissingPhotoFilesInBackground();
    expect(repo.pathsSet.keys, contains('a'));
  });
}

class _ThrowingRemote extends _FakeRemote {
  bool fail = true;

  @override
  Future<Uint8List> downloadPhoto(String objectKey) async {
    if (fail) throw StateError('storage unavailable');
    return super.downloadPhoto(objectKey);
  }
}
