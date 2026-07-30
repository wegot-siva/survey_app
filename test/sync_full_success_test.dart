// Unit tests for syncFullySucceeded — the single source of truth the sync
// UI uses to decide "did this run actually sync everything". Encodes the
// false-success reporting fix: a run that pushAll() completed but with
// per-row skips (RLS-rejected rows left dirty), or with a failed core pull,
// is NOT a success even though SyncResult.success is true.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/services/sync_service.dart';

void main() {
  const cleanPull = SyncResult(success: true);
  const failedPull = SyncResult(success: false, message: 'pull boom');

  test('clean push + clean pull is a full success', () {
    expect(syncFullySucceeded(const SyncResult(success: true), cleanPull), isTrue);
  });

  test(
    'push completed but with skipped rows is NOT a success '
    '(the false-success bug: success:true yet rows left dirty)',
    () {
      const partial = SyncResult(
        success: true,
        pushFailures: ['sites/abc: RLS 42501'],
        message: '1 row could not sync',
      );
      expect(syncFullySucceeded(partial, cleanPull), isFalse);
    },
  );

  test('a fatal push failure is not a success', () {
    const fatal = SyncResult(success: false, message: 'Sync failed');
    expect(syncFullySucceeded(fatal, cleanPull), isFalse);
  });

  test('a failed core pull is not a success even if the push was clean', () {
    expect(syncFullySucceeded(const SyncResult(success: true), failedPull), isFalse);
  });

  test('multiple skipped rows across different tables all count against success', () {
    const partial = SyncResult(
      success: true,
      pushFailures: [
        'sites/abc: RLS 42501',
        'blocks/def: RLS 42501',
        'source_points/ghi: RLS 42501',
      ],
    );
    expect(syncFullySucceeded(partial, cleanPull), isFalse);
  });
}
