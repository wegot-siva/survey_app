// A site kept back because it still holds unsynced work must be REPORTED,
// not just preserved.
//
// Preserving the data and saying nothing would fix half the bug and hide the
// other half: the engineer keeps a day of field work on the device, has no
// way to push it (RLS refuses — the site is someone else's now), and no
// reason to suspect anything is wrong. A green "Synced" over the top of that
// is the same false-success pattern this project already fixed once for
// blocked rows.
//
// So the preserved site downgrades the run to SyncStatus.partial — the
// existing "needs attention" tier — and carries the site NAME through, since
// a bare count tells an engineer nothing about which site to raise.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/models/engineer.dart';
import 'package:survey_app/services/sync_controller.dart';
import 'package:survey_app/services/sync_service.dart';

class _FakeSyncService implements SyncService {
  _FakeSyncService({this.preserved = const [], this.blocked = 0});

  final List<String> preserved;
  final int blocked;

  @override
  Future<SyncResult> pushAll() async => SyncResult(
        success: true,
        syncBlocked: blocked,
      );

  @override
  Future<SyncResult> pullMaterialMasterItems() async =>
      const SyncResult(success: true);

  @override
  Future<SyncResult> pullCoreSurveyData() async =>
      SyncResult(success: true, preservedSites: preserved);

  @override
  Future<List<Engineer>> fetchEngineerRoster() async => const [];

  @override
  Future<void> downloadMissingPhotoFilesInBackground() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a preserved site downgrades an otherwise clean run to needs-attention',
      () async {
    final controller = SyncController(
      _FakeSyncService(preserved: const ['Block B Apt 3']),
    );
    addTearDown(controller.dispose);

    final outcome = (await controller.requestSync(manual: true))!;

    expect(outcome.status, SyncStatus.partial,
        reason: 'a green "Synced" here would hide unsendable field work');
    expect(controller.status, SyncStatus.partial);
  });

  test('the site NAME reaches the UI, not just a count', () async {
    final controller = SyncController(
      _FakeSyncService(preserved: const ['Block B Apt 3', 'Admin One']),
    );
    addTearDown(controller.dispose);

    final outcome = (await controller.requestSync(manual: true))!;

    expect(outcome.preservedSites, ['Block B Apt 3', 'Admin One']);
    expect(controller.preservedSites, ['Block B Apt 3', 'Admin One'],
        reason: 'the AppBar and the details dialog both read this');
  });

  test('nothing preserved and nothing blocked is still a clean success',
      () async {
    final controller = SyncController(_FakeSyncService());
    addTearDown(controller.dispose);

    final outcome = (await controller.requestSync(manual: true))!;

    expect(outcome.status, SyncStatus.success,
        reason: 'the guard must not make every ordinary sync look alarming');
    expect(controller.preservedSites, isEmpty);
  });

  test('preserved sites and blocked rows coexist — both need reporting',
      () async {
    final controller = SyncController(
      _FakeSyncService(preserved: const ['Admin One'], blocked: 3),
    );
    addTearDown(controller.dispose);

    final outcome = (await controller.requestSync(manual: true))!;

    expect(outcome.status, SyncStatus.partial);
    expect(outcome.blocked, 3);
    expect(outcome.preservedSites, ['Admin One']);
    // The AppBar sums them; 3 blocked rows plus 1 preserved site is 4 things
    // the user should look at, not 3.
    expect(controller.blockedCount + controller.preservedSites.length, 4);
  });
}
