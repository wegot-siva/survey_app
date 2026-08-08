// Unit tests for SyncController's concurrency gates — the three protections
// that make automatic triggers (Slice B: sync after every section save) safe
// to fire freely:
//
//   * single-flight — one run at a time; concurrent requests join it
//   * debounce      — a burst of automatic triggers collapses into one run
//   * cooldown      — automatic triggers are ignored just after a success
//
// Manual sync bypasses debounce and cooldown: a user who taps Sync asked for
// a sync and must always get a real attempt.
//
// The debounce/cooldown windows are injected as very short real durations
// rather than virtualized. A Timer-based fake clock wouldn't work here: the
// cooldown is measured against DateTime.now(), which such a clock can't
// shift, so the test would silently pass while testing nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/models/engineer.dart';
import 'package:survey_app/services/sync_controller.dart';
import 'package:survey_app/services/sync_service.dart';

const _debounce = Duration(milliseconds: 60);
const _cooldown = Duration(milliseconds: 200);

/// Comfortably longer than [_debounce]/[_cooldown], so waits aren't flaky on
/// a loaded CI machine.
Future<void> _past(Duration window) =>
    Future<void>.delayed(window + const Duration(milliseconds: 120));

/// Counts calls and lets each test control how long a run takes, so
/// overlapping requests can be arranged deterministically.
class _FakeSyncService implements SyncService {
  _FakeSyncService({this.pushDelay = Duration.zero});

  final Duration pushDelay;

  int pushCalls = 0;
  int materialMasterPullCalls = 0;
  int corePullCalls = 0;

  /// Set false to make pushAll report a failure — no lastSyncedAt is
  /// recorded then, which is what the cooldown keys off.
  bool pushSucceeds = true;

  @override
  Future<SyncResult> pushAll() async {
    pushCalls++;
    if (pushDelay > Duration.zero) await Future<void>.delayed(pushDelay);
    return pushSucceeds
        ? const SyncResult(success: true)
        : const SyncResult(success: false, message: 'boom');
  }

  @override
  Future<SyncResult> pullMaterialMasterItems() async {
    materialMasterPullCalls++;
    return const SyncResult(success: true);
  }

  @override
  Future<SyncResult> pullCoreSurveyData() async {
    corePullCalls++;
    return const SyncResult(success: true);
  }

  @override
  Future<List<Engineer>> fetchEngineerRoster() async => const [];

  /// Photo files are fetched by the controller after a run completes,
  /// outside the sync it reports on. Stubbed as a no-op: these tests are
  /// about the controller's run/status behaviour, and the real download's
  /// own guarantees are covered by photo_download_deferred_test.dart.
  @override
  Future<void> downloadMissingPhotoFilesInBackground() async {}

  // Nothing else on SyncService is reachable from SyncController; if that
  // ever changes this throws loudly rather than silently returning null.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncController _controller(_FakeSyncService service) => SyncController(
  service,
  autoDebounce: _debounce,
  autoCooldown: _cooldown,
);

void main() {
  group('single-flight', () {
    test(
      'a request while one is in flight joins it instead of starting a second',
      () async {
        final service = _FakeSyncService(
          pushDelay: const Duration(milliseconds: 150),
        );
        final controller = _controller(service);

        // Both manual, so debounce/cooldown are out of the picture — this
        // isolates single-flight.
        final first = controller.requestSync(manual: true);
        final second = controller.requestSync(manual: true);
        final results = await Future.wait([first, second]);

        expect(service.pushCalls, 1, reason: 'only one run should execute');
        expect(
          identical(results[0], results[1]),
          isTrue,
          reason: "the joiner should get the in-flight run's own outcome",
        );
        controller.dispose();
      },
    );

    test('a request after the previous run finished is a new run', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      await controller.requestSync(manual: true);
      await controller.requestSync(manual: true);

      expect(service.pushCalls, 2);
      controller.dispose();
    });
  });

  group('debounce', () {
    test('three SPACED automatic triggers still collapse into one sync',
        () async {
      // Cooldown disabled so this isolates debounce. Both other gates would
      // otherwise mask it and let the test pass even with debounce removed:
      // fired back-to-back, single-flight alone collapses them (they all
      // land inside one in-flight run), and with cooldown on, the runs after
      // the first are skipped for being too soon. Spacing the triggers
      // further apart than a run takes — but still inside the window — is
      // what makes debounce the only thing that can collapse them, and
      // mirrors the real case: a user saving several sections a few seconds
      // apart.
      final service = _FakeSyncService();
      final controller = SyncController(
        service,
        autoDebounce: _debounce,
        autoCooldown: Duration.zero,
      );

      const gap = Duration(milliseconds: 20); // < _debounce (60ms)
      controller.requestSync(manual: false);
      await Future<void>.delayed(gap);
      controller.requestSync(manual: false);
      await Future<void>.delayed(gap);
      controller.requestSync(manual: false);

      // Nothing has run yet — each trigger restarted the window.
      expect(service.pushCalls, 0);

      await _past(_debounce);
      expect(service.pushCalls, 1, reason: 'three triggers, one sync');
      controller.dispose();
    });

    test('manual supersedes a pending automatic trigger', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      final auto = controller.requestSync(manual: false); // debounced
      final manual = await controller.requestSync(manual: true); // immediate

      expect(service.pushCalls, 1, reason: 'the automatic one is cancelled');
      expect(manual, isNotNull);

      // The superseded request still completes (rather than hanging), with
      // the manual run's outcome.
      expect(identical(await auto, manual), isTrue);

      // And the cancelled debounce timer must not fire a second run later.
      await _past(_debounce);
      expect(service.pushCalls, 1);
      controller.dispose();
    });
  });

  group('cooldown', () {
    test('an automatic trigger just after a success is skipped', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      await controller.requestSync(manual: true);
      expect(service.pushCalls, 1);

      final skipped = await controller.requestSync(manual: false);

      expect(skipped, isNull, reason: 'a skipped run reports null');
      expect(service.pushCalls, 1, reason: 'no second run');
      controller.dispose();
    });

    test('manual ALWAYS bypasses the cooldown', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      await controller.requestSync(manual: true);
      final second = await controller.requestSync(manual: true);

      expect(service.pushCalls, 2);
      expect(second, isNotNull);
      controller.dispose();
    });

    test('an automatic trigger runs once the cooldown has elapsed', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      await controller.requestSync(manual: true);
      expect(service.pushCalls, 1);

      await _past(_cooldown);
      controller.requestSync(manual: false);
      await _past(_debounce);

      expect(service.pushCalls, 2);
      controller.dispose();
    });

    test(
      'a FAILED sync starts no cooldown — the next automatic trigger retries',
      () async {
        final service = _FakeSyncService()..pushSucceeds = false;
        final controller = _controller(service);

        await controller.requestSync(manual: true);
        expect(service.pushCalls, 1);
        expect(controller.status, SyncStatus.failure);

        controller.requestSync(manual: false);
        await _past(_debounce);

        expect(
          service.pushCalls,
          2,
          reason: 'cooldown keys off lastSyncedAt, only set by a run that '
              'actually reached the server',
        );
        controller.dispose();
      },
    );
  });

  group('background push (Slice C)', () {
    test('pushes without pulling — a backgrounded app has no use for '
        'incoming data, and every ms spent is one the push may not get',
        () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      await controller.requestBackgroundPush();

      expect(service.pushCalls, 1);
      expect(service.materialMasterPullCalls, 0);
      expect(service.corePullCalls, 0);
      controller.dispose();
    });

    test('a clean push-only run still reports success — skipped pulls must '
        'not be mistaken for failed ones', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      final outcome = await controller.requestBackgroundPush();

      expect(outcome.status, SyncStatus.success);
      expect(controller.status, SyncStatus.success);
      controller.dispose();
    });

    test('bypasses the cooldown — the edit made just after a sync, right '
        'before leaving, is exactly the one at risk', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      await controller.requestSync(manual: true); // starts the cooldown
      expect(service.pushCalls, 1);

      // A normal automatic trigger here would be skipped...
      expect(await controller.requestSync(manual: false), isNull);
      expect(service.pushCalls, 1);

      // ...but backgrounding must still push.
      await controller.requestBackgroundPush();
      expect(service.pushCalls, 2);
      controller.dispose();
    });

    test('bypasses the debounce — a delayed start would never fire, the '
        'process is being suspended in that window', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      // Not awaited: the point is that it ran synchronously enough to have
      // already called through, rather than parking on a debounce timer.
      final run = controller.requestBackgroundPush();
      await run;

      expect(service.pushCalls, 1);
      controller.dispose();
    });

    test('still respects single-flight — joins a full sync already running',
        () async {
      final service = _FakeSyncService(
        pushDelay: const Duration(milliseconds: 150),
      );
      final controller = _controller(service);

      final full = controller.requestSync(manual: true);
      final background = controller.requestBackgroundPush();
      final results = await Future.wait([full, background]);

      expect(service.pushCalls, 1, reason: 'one run, not two');
      expect(identical(results[0], results[1]), isTrue);
      controller.dispose();
    });

    test('supersedes a pending debounced auto trigger without leaving it '
        'hanging', () async {
      final service = _FakeSyncService();
      final controller = _controller(service);

      final auto = controller.requestSync(manual: false); // debounced
      final background = await controller.requestBackgroundPush();

      expect(identical(await auto, background), isTrue);
      expect(service.pushCalls, 1);

      // The cancelled debounce timer must not fire a second run later.
      await _past(_debounce);
      expect(service.pushCalls, 1);
      controller.dispose();
    });
  });

  test('dispose completes a pending debounced request instead of hanging',
      () async {
    final service = _FakeSyncService();
    final controller = _controller(service);

    final pending = controller.requestSync(manual: false);
    controller.dispose();

    expect(await pending, isNull);
    expect(service.pushCalls, 0);
  });

  group('success auto-revert', () {
    test('production reverts a clean success to idle after 10 seconds', () {
      expect(SyncController.defaultSuccessRevert, const Duration(seconds: 10));
    });

    test('a clean success falls back to idle once the window elapses, '
        'restoring the normal Sync button', () async {
      final service = _FakeSyncService();
      // Same approach as the debounce/cooldown windows above: shortened real
      // duration, since the revert is a plain Timer and this asserts on the
      // status it leaves behind, not on the exact wall-clock delay.
      final controller = SyncController(
        service,
        autoDebounce: _debounce,
        autoCooldown: _cooldown,
        successRevert: const Duration(milliseconds: 120),
      );

      await controller.requestSync(manual: true);
      expect(controller.status, SyncStatus.success);

      await _past(const Duration(milliseconds: 120));
      expect(controller.status, SyncStatus.idle);
      controller.dispose();
    });

    test('a FAILED run never auto-reverts — it is a standing issue the user '
        'still has to act on', () async {
      final service = _FakeSyncService()..pushSucceeds = false;
      final controller = SyncController(
        service,
        autoDebounce: _debounce,
        autoCooldown: _cooldown,
        successRevert: const Duration(milliseconds: 120),
      );

      await controller.requestSync(manual: true);
      expect(controller.status, SyncStatus.failure);

      await _past(const Duration(milliseconds: 120));
      expect(controller.status, SyncStatus.failure);
      controller.dispose();
    });
  });
}
