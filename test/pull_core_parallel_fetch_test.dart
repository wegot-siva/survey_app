// pullCoreSurveyData fetches the core tables concurrently but must still
// APPLY them in foreign-key order.
//
// That split is the whole point of the change these tests guard, and it is
// exactly the kind of thing that looks fine in a passing sync and corrupts
// data later: local sqlite runs with `PRAGMA foreign_keys = ON`, so writing
// blocks before sites, or bom_snapshot_lines before bom_snapshots, fails the
// insert — but only for a device that happens to receive those responses in
// an unlucky order. Sequential code could never expose it; concurrent code
// exposes it intermittently, on someone else's phone.
//
// So the tests below deliberately make the network finish in the WORST
// possible order — the last table in the plan returns first, the first table
// returns last — and assert the applies still run first-to-last. If someone
// later "simplifies" this by applying each table as its response lands, these
// fail immediately.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';
import 'package:survey_app/models/survey_photo.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/supabase_service.dart';
import 'package:survey_app/services/sync_service.dart';

/// The FK-ordered sequence pullCoreSurveyData must apply in. Parents before
/// children, sites before everything, photos last.
const _expectedApplyOrder = <String>[
  'sites',
  'blocks',
  'client_inputs',
  'footers',
  'source_points',
  'inlet_points',
  'duct_loras',
  'gateways',
  'bom_manual_entries',
  'bom_snapshots',
  'bom_snapshot_lines',
  'bom_revisions',
  'bom_revision_lines',
  'bom_manual_edit_snapshots',
  'bom_manual_edit_snapshot_lines',
  'photos',
];

class _FakeSupabase extends SupabaseService {
  @override
  bool get isConfigured => true;
  @override
  bool get isInitialized => true;
  @override
  Future<void> initIfConfigured() async {}
}

/// Returns each table after a per-table delay, and records how many fetches
/// were in flight at once so the tests can prove concurrency actually
/// happened (and stayed within its cap).
class _RecordingDataSource extends SupabaseSurveyDataSource {
  _RecordingDataSource({this.delays = const {}, this.failOn = const {}});

  final Map<String, Duration> delays;
  final Set<String> failOn;

  final List<String> fetchStarts = [];
  int inFlight = 0;
  int peakInFlight = 0;

  Future<List<Map<String, dynamic>>> _fetch(String label) async {
    fetchStarts.add(label);
    inFlight++;
    peakInFlight = inFlight > peakInFlight ? inFlight : peakInFlight;
    try {
      await Future<void>.delayed(delays[label] ?? Duration.zero);
      if (failOn.contains(label)) {
        throw StateError('fetch failed: $label');
      }
      return [
        {'id': '$label-row'},
      ];
    } finally {
      inFlight--;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchSites() => _fetch('sites');
  @override
  Future<List<Map<String, dynamic>>> fetchBlocks() => _fetch('blocks');
  @override
  Future<List<Map<String, dynamic>>> fetchClientInputs() =>
      _fetch('client_inputs');
  @override
  Future<List<Map<String, dynamic>>> fetchFooters() => _fetch('footers');
  @override
  Future<List<Map<String, dynamic>>> fetchSourcePoints() =>
      _fetch('source_points');
  @override
  Future<List<Map<String, dynamic>>> fetchInletPoints() =>
      _fetch('inlet_points');
  @override
  Future<List<Map<String, dynamic>>> fetchDuctLoras() => _fetch('duct_loras');
  @override
  Future<List<Map<String, dynamic>>> fetchGateways() => _fetch('gateways');
  @override
  Future<List<Map<String, dynamic>>> fetchBomManualEntries() =>
      _fetch('bom_manual_entries');
  @override
  Future<List<Map<String, dynamic>>> fetchBomSnapshots() =>
      _fetch('bom_snapshots');
  @override
  Future<List<Map<String, dynamic>>> fetchBomSnapshotLines() =>
      _fetch('bom_snapshot_lines');
  @override
  Future<List<Map<String, dynamic>>> fetchBomRevisions() =>
      _fetch('bom_revisions');
  @override
  Future<List<Map<String, dynamic>>> fetchBomRevisionLines() =>
      _fetch('bom_revision_lines');
  @override
  Future<List<Map<String, dynamic>>> fetchBomManualEditSnapshots() =>
      _fetch('bom_manual_edit_snapshots');
  @override
  Future<List<Map<String, dynamic>>> fetchBomManualEditSnapshotLines() =>
      _fetch('bom_manual_edit_snapshot_lines');
  @override
  Future<List<Map<String, dynamic>>> fetchPhotos() => _fetch('photos');
}

/// Records the order applies ran in. Every override is a no-op beyond that —
/// these tests are about ordering, not merge semantics, which the per-table
/// repository suites already cover.
class _RecordingRepository extends InMemorySurveyRepository {
  _RecordingRepository() : super(IdService());

  final List<String> applies = [];

  Future<void> _record(String label) async {
    applies.add(label);
    // Yield, so an implementation that fired applies concurrently would
    // interleave here and be caught by the order assertions.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<List<String>> upsertSitesFromRemote(
    List<Map<String, dynamic>> rows,
  ) async {
    await _record('sites');
    // Nothing preserved: these tests are about ordering, not the
    // reassignment-cascade guard (see reassignment_cascade_test.dart).
    return const [];
  }
  @override
  Future<void> upsertBlocksFromRemote(List<Map<String, dynamic>> rows) =>
      _record('blocks');
  @override
  Future<void> upsertClientInputsFromRemote(List<Map<String, dynamic>> rows) =>
      _record('client_inputs');
  @override
  Future<void> upsertFootersFromRemote(List<Map<String, dynamic>> rows) =>
      _record('footers');
  @override
  Future<void> upsertSourcePointsFromRemote(List<Map<String, dynamic>> rows) =>
      _record('source_points');
  @override
  Future<void> upsertInletPointsFromRemote(List<Map<String, dynamic>> rows) =>
      _record('inlet_points');
  @override
  Future<void> upsertDuctLorasFromRemote(List<Map<String, dynamic>> rows) =>
      _record('duct_loras');
  @override
  Future<void> upsertGatewaysFromRemote(List<Map<String, dynamic>> rows) =>
      _record('gateways');
  @override
  Future<void> upsertBomManualEntriesFromRemote(
          List<Map<String, dynamic>> rows) =>
      _record('bom_manual_entries');
  @override
  Future<void> upsertBomSnapshotsFromRemote(List<Map<String, dynamic>> rows) =>
      _record('bom_snapshots');
  @override
  Future<void> upsertBomSnapshotLinesFromRemote(
          List<Map<String, dynamic>> rows) =>
      _record('bom_snapshot_lines');
  @override
  Future<void> upsertBomRevisionsFromRemote(List<Map<String, dynamic>> rows) =>
      _record('bom_revisions');
  @override
  Future<void> upsertBomRevisionLinesFromRemote(
          List<Map<String, dynamic>> rows) =>
      _record('bom_revision_lines');
  @override
  Future<void> upsertBomManualEditSnapshotsFromRemote(
          List<Map<String, dynamic>> rows) =>
      _record('bom_manual_edit_snapshots');
  @override
  Future<void> upsertBomManualEditSnapshotLinesFromRemote(
          List<Map<String, dynamic>> rows) =>
      _record('bom_manual_edit_snapshot_lines');
  @override
  Future<List<String>> upsertPhotosFromRemote(
      List<Map<String, dynamic>> rows) async {
    await _record('photos');
    return const [];
  }

  @override
  Future<List<SurveyPhoto>> getPhotosMissingLocalFile() async => const [];
}

void main() {
  test(
    'applies in foreign-key order even when the network answers in reverse',
    () async {
      // Worst case for a fetch-order-driven implementation: the LAST table in
      // the plan comes back first, the FIRST comes back last.
      final delays = <String, Duration>{
        for (var i = 0; i < _expectedApplyOrder.length; i++)
          _expectedApplyOrder[i]: Duration(milliseconds: (i + 1) * 10),
      };
      final remote = _RecordingDataSource(delays: delays);
      final repo = _RecordingRepository();
      final service = SyncService(repo, _FakeSupabase(), remote);

      final result = await service.pullCoreSurveyData();

      expect(result.success, isTrue);
      expect(repo.applies, _expectedApplyOrder,
          reason: 'applies must follow the FK plan, not response arrival');
    },
  );

  test('fetches actually overlap — this is the point of the change', () async {
    final remote = _RecordingDataSource(
      delays: {
        for (final t in _expectedApplyOrder) t: const Duration(milliseconds: 30),
      },
    );
    final service = SyncService(_RecordingRepository(), _FakeSupabase(), remote);

    await service.pullCoreSurveyData();

    expect(remote.peakInFlight, greaterThan(1),
        reason: 'sequential fetching would never exceed 1 in flight');
  });

  test('concurrency stays within its cap — a phone should not open 16 '
      'connections at once', () async {
    final remote = _RecordingDataSource(
      delays: {
        for (final t in _expectedApplyOrder) t: const Duration(milliseconds: 30),
      },
    );
    final service = SyncService(_RecordingRepository(), _FakeSupabase(), remote);

    await service.pullCoreSurveyData();

    expect(remote.peakInFlight, lessThanOrEqualTo(6));
    expect(remote.fetchStarts.length, _expectedApplyOrder.length,
        reason: 'every table must still be fetched exactly once');
  });

  test(
    'a failed fetch fails the pull, and a second failure does not escape as '
    'an unhandled async error',
    () async {
      final remote = _RecordingDataSource(
        delays: {
          for (final t in _expectedApplyOrder) t: const Duration(milliseconds: 5),
        },
        // Two failures: Future.wait must have a listener attached to both, or
        // the loser surfaces later as an unhandled error and (in production)
        // a zone-level crash report for a sync that already reported failure.
        failOn: {'source_points', 'gateways'},
      );
      final repo = _RecordingRepository();
      final service = SyncService(repo, _FakeSupabase(), remote);

      final errors = <Object>[];
      final result = await runZonedGuarded<Future<SyncResult>>(
            () => service.pullCoreSurveyData(),
            (e, s) => errors.add(e),
          ) ??
          const SyncResult(success: false);

      expect(result.success, isFalse,
          reason: 'a failed table pull must fail the whole pull');
      expect(repo.applies, isEmpty,
          reason: 'nothing should be applied when a fetch failed');
      // Let any stray unhandled error land before asserting none did.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(errors, isEmpty,
          reason: 'the second failure must already be handled by Future.wait');
    },
  );
}
