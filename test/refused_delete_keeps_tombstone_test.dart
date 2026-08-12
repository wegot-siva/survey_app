// The property the RLS-refused-delete fix depends on: when the remote delete
// does not apply, the LOCAL tombstone must survive.
//
// pushAll's delete step is two statements, and their order is the bug:
//
//     await _remote.deleteSourcePoint(id, siteId: site.id);
//     await _repository.hardDeleteSourcePoint(id);   // only if the first won
//
// The remote call is what decides. Before the fix it could not fail — an
// RLS-refused UPDATE comes back as HTTP 200 with zero rows — so the hard
// delete always ran, the tombstone was destroyed, and the still-live remote
// row was reinserted by the next pull.
//
// Making the remote call throw is only half the fix. The other half is that
// pushAll must keep the tombstone and report a retryable failure rather than
// aborting the run or losing the row, which is what these assert.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';
import 'package:survey_app/models/site.dart';
import 'package:survey_app/services/id_service.dart';
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

/// Stands in for Supabase refusing (or accepting) the delete.
class _DeleteRemote extends SupabaseSurveyDataSource {
  _DeleteRemote({required this.refuse});

  final bool refuse;
  final List<String> attempted = [];

  @override
  Future<void> deleteSourcePoint(String id, {required String siteId}) async {
    attempted.add(id);
    if (refuse) {
      throw DeleteRefusedException('source_points', id, siteId: siteId);
    }
  }

  @override
  Future<void> pushSite(site) async {}
}

/// One site holding one source point whose delete is pending. `getSites` is
/// overridden rather than seeded through createSite so the ids stay fixed and
/// readable; pushAll only needs the site row itself to walk its children.
class _TombstoneRepo extends InMemorySurveyRepository {
  _TombstoneRepo() : super(IdService());

  static const siteId = 'site-1';
  static const pointId = 'sp-1';

  bool hardDeleted = false;
  bool tombstonePresent = true;

  @override
  Future<List<Site>> getSites({
    bool includeArchived = false,
    bool dirtyOnly = false,
  }) async =>
      dirtyOnly ? const [] : const [Site(id: siteId, name: 'Site 1')];

  @override
  Future<List<String>> getPendingDeleteSourcePointIds(String s) async =>
      (s == siteId && tombstonePresent) ? const [pointId] : const [];

  @override
  Future<void> hardDeleteSourcePoint(String id) async {
    hardDeleted = true;
    tombstonePresent = false;
  }
}

Future<(_TombstoneRepo, SyncResult)> _run({required bool refuse}) async {
  final repo = _TombstoneRepo();
  final service = SyncService(repo, _FakeSupabase(), _DeleteRemote(refuse: refuse));
  return (repo, await service.pushAll());
}

void main() {
  test('a REFUSED delete keeps the local tombstone for retry', () async {
    final (repo, result) = await _run(refuse: true);

    expect(repo.hardDeleted, isFalse,
        reason: 'destroying the tombstone is what caused resurrection');
    expect(repo.tombstonePresent, isTrue,
        reason: 'the delete must still be pending, so the next sync retries');
    expect(result.pushFailures, isNotEmpty,
        reason: 'the user must be told the row did not sync');
    expect(result.pushFailures.join(), contains('source_points'));
    expect(result.success, isTrue,
        reason: 'per-row isolation: one refused row must not abort the run');
  });

  test('a refused delete is NOT reported as a fully successful sync', () async {
    final (_, result) = await _run(refuse: true);

    expect(syncFullySucceeded(result, const SyncResult(success: true)), isFalse,
        reason: 'this is the gate the AppBar status reads — a refused delete '
            'must not show as "Synced"');
  });

  test('an ACCEPTED delete still hard-deletes the tombstone', () async {
    final (repo, result) = await _run(refuse: false);

    expect(repo.hardDeleted, isTrue,
        reason: 'the tombstone has served its purpose once the remote row is '
            'confirmed gone');
    expect(result.pushFailures, isEmpty);
    expect(syncFullySucceeded(result, const SyncResult(success: true)), isTrue);
  });
}
