// Slice D: sync when the device regains a connection.
//
// Two layers, tested separately and then together:
//
//   * ConnectivityWatcher turns the raw platform stream into the one signal
//     the sync layer cares about — an offline -> online transition. It
//     deliberately stays "dumb": no throttling lives here.
//   * SyncController's existing debounce is what stops a flapping
//     connection from storming the server, so the throttling policy lives
//     in exactly one place rather than being half-implemented in two.
//
// The end-to-end flapping test is the one the slice actually requires:
// several rapid reconnects must cost one sync.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/models/engineer.dart';
import 'package:survey_app/services/connectivity_watcher.dart';
import 'package:survey_app/services/sync_controller.dart';
import 'package:survey_app/services/sync_service.dart';

const _offline = <ConnectivityResult>[ConnectivityResult.none];
const _wifi = <ConnectivityResult>[ConnectivityResult.wifi];
const _mobile = <ConnectivityResult>[ConnectivityResult.mobile];

const _debounce = Duration(milliseconds: 60);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
Future<void> _pastDebounce() =>
    Future<void>.delayed(_debounce + const Duration(milliseconds: 120));

class _FakeSyncService implements SyncService {
  int pushCalls = 0;

  @override
  Future<SyncResult> pushAll() async {
    pushCalls++;
    return const SyncResult(success: true);
  }

  @override
  Future<SyncResult> pullMaterialMasterItems() async =>
      const SyncResult(success: true);

  @override
  Future<SyncResult> pullCoreSurveyData() async =>
      const SyncResult(success: true);

  @override
  Future<List<Engineer>> fetchEngineerRoster() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ConnectivityWatcher', () {
    late StreamController<List<ConnectivityResult>> stream;
    late ConnectivityWatcher watcher;
    late int restores;

    setUp(() {
      stream = StreamController<List<ConnectivityResult>>.broadcast();
      watcher = ConnectivityWatcher(stream: stream.stream);
      restores = 0;
      watcher.start(() => restores++);
    });

    tearDown(() async {
      await watcher.dispose();
      await stream.close();
    });

    test('fires on a genuine offline -> online transition', () async {
      stream.add(_offline);
      await _settle();
      expect(restores, 0, reason: 'going offline is not a restore');

      stream.add(_wifi);
      await _settle();
      expect(restores, 1);
    });

    test('does NOT fire when an already-online device swaps transport — '
        'nothing became reachable that was not already', () async {
      stream.add(_wifi);
      await _settle();
      stream.add(_mobile);
      await _settle();

      expect(restores, 0);
    });

    test('does NOT treat a first-event-online as a restore — launch already '
        'syncs on its own, firing here too would just duplicate it', () async {
      stream.add(_wifi);
      await _settle();

      expect(restores, 0);
    });

    test('an app that LAUNCHES offline still gets its restore', () async {
      stream.add(_offline); // first event: offline
      await _settle();
      stream.add(_mobile);
      await _settle();

      expect(restores, 1);
    });

    test('an empty result list counts as offline — some platforms report '
        'that instead of [none]', () async {
      stream.add(const <ConnectivityResult>[]);
      await _settle();
      stream.add(_wifi);
      await _settle();

      expect(restores, 1);
    });

    test('each offline -> online cycle is its own restore', () async {
      for (var i = 0; i < 3; i++) {
        stream.add(_offline);
        await _settle();
        stream.add(_wifi);
        await _settle();
      }
      expect(restores, 3, reason: 'the watcher itself does not throttle');
    });

    test('stops firing after dispose', () async {
      await watcher.dispose();
      stream.add(_offline);
      await _settle();
      stream.add(_wifi);
      await _settle();

      expect(restores, 0);
      expect(watcher.isListening, isFalse);
    });
  });

  group('flapping connection -> one sync (the case this slice requires)', () {
    test('four rapid reconnects collapse into a single sync run', () async {
      final service = _FakeSyncService();
      // Cooldown disabled so this isolates the debounce: with it on, the
      // test could pass merely because runs 2-4 were skipped for being too
      // soon, which would not prove the debounce collapsed anything.
      final controller = SyncController(
        service,
        autoDebounce: _debounce,
        autoCooldown: Duration.zero,
      );
      final stream = StreamController<List<ConnectivityResult>>.broadcast();
      final watcher = ConnectivityWatcher(stream: stream.stream);
      watcher.start(() => controller.requestSync(manual: false));

      // Airplane mode toggled on and off four times in quick succession —
      // each cycle is a real restore, spaced well inside the debounce
      // window.
      for (var i = 0; i < 4; i++) {
        stream.add(_offline);
        await _settle();
        stream.add(_wifi);
        await _settle();
      }

      // Still nothing: every restore restarted the window.
      expect(service.pushCalls, 0);

      await _pastDebounce();
      expect(
        service.pushCalls,
        1,
        reason: 'four reconnects, one sync — the debounce did the collapsing',
      );

      await watcher.dispose();
      await stream.close();
      controller.dispose();
    });

    test('a reconnect after a genuine offline stretch is NOT suppressed by '
        'the cooldown — a failed sync never starts one', () async {
      final service = _FakeSyncService();
      final controller = SyncController(
        service,
        autoDebounce: _debounce,
        autoCooldown: const Duration(hours: 1), // deliberately huge
      );
      final stream = StreamController<List<ConnectivityResult>>.broadcast();
      final watcher = ConnectivityWatcher(stream: stream.stream);
      watcher.start(() => controller.requestSync(manual: false));

      // No successful sync has happened yet, so lastSyncedAt is null and the
      // cooldown has nothing to measure against — mirroring a device that
      // has been offline and whose sync attempts have all been failing.
      stream.add(_offline);
      await _settle();
      stream.add(_wifi);
      await _settle();
      await _pastDebounce();

      expect(service.pushCalls, 1, reason: 'the restore must get through');

      await watcher.dispose();
      await stream.close();
      controller.dispose();
    });
  });
}
