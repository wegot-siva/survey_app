import 'dart:async';

import 'package:flutter/foundation.dart';

import 'sync_service.dart';

/// State of the app's sync control — drives the AppBar's icon/label/color.
/// Session only: resets to [idle] on app restart (a fresh [SyncController] is
/// built per signed-in account — see main.dart's `_AuthGateState`).
///
/// [partial] is distinct from both [success] and [failure]: it's a fully
/// clean sync run (nothing retryable failed) that still has a standing set
/// of rows this account can never push (see [SyncResult.syncBlocked]) —
/// retrying won't help, so it gets its own color/copy instead of being
/// folded into a falsely-reassuring green "Synced" or a falsely-alarming
/// red "Sync failed".
enum SyncStatus { idle, syncing, success, partial, failure }

/// Everything one sync run produced, handed back to whoever asked for it so
/// the UI layer can report it without re-deriving anything or reaching into
/// [SyncService] a second time.
///
/// Deliberately carries the raw [SyncResult]s alongside the derived counts:
/// the failure-details view needs the underlying messages/`pushFailures`
/// verbatim, and re-running the sync to get them would be absurd.
class SyncOutcome {
  const SyncOutcome({
    required this.status,
    required this.manual,
    required this.push,
    required this.materialMasterPull,
    required this.corePull,
  });

  final SyncStatus status;

  /// Whether this run came from an explicit user action (the Sync button)
  /// rather than an automatic trigger. Not used to change *what* a sync
  /// does — only how loudly the UI reports it. Nothing sets this false yet;
  /// automatic triggers are later slices.
  final bool manual;

  final SyncResult push;
  final SyncResult materialMasterPull;
  final SyncResult corePull;

  /// One entry per row that failed to push and will be retried next run.
  List<String> get pushFailures => push.pushFailures;
  int get skipped => push.pushFailures.length;

  /// Standing rows this account can never push — see [SyncResult.syncBlocked].
  int get blocked => push.syncBlocked;

  int get photos => push.photos;

  /// Material Master rows this run pulled down, or 0 if that pull failed.
  int get materialMasterPulled =>
      materialMasterPull.success ? materialMasterPull.materialMasterItems : 0;

  bool get corePullFailed => !corePull.success;

  /// Every per-table push count except photos, which the sync UI reports as
  /// its own separate figure.
  int get records =>
      push.sites +
      push.blocks +
      push.clientInputs +
      push.sourcePoints +
      push.inletPoints +
      push.ductLoras +
      push.gateways +
      push.footers +
      push.materialMasterItems +
      push.materialMasterAuditEntries +
      push.bomManualEntries +
      push.bomSnapshots +
      push.bomRevisions +
      push.bomManualEditSnapshots;
}

/// Owns "what is the sync doing right now" as app-level state, so any screen
/// can read the status or ask for a sync without owning the machinery.
///
/// Split out of `HomeScreen` deliberately: the status used to live in that
/// screen's [State], which meant screens pushed on top of it (every survey
/// section form) had no way to reach it. Orchestration lives here;
/// [SyncService] still does the actual pushing/pulling and is untouched by
/// this class. Presentation (SnackBars, dialogs) stays in the UI layer —
/// this class never shows anything itself.
///
/// One instance per signed-in account, created and disposed alongside the
/// account's [SyncService] (see main.dart) so sync state can never leak
/// across an account switch.
///
/// Automatic triggers are gated three ways — single-flight, [autoDebounce],
/// [autoCooldown] — so a burst of saves costs one sync rather than one per
/// save. A manual sync bypasses the debounce and cooldown entirely.
///
/// Known, bounded gap from the cooldown: a save landing inside
/// [autoCooldown] of a successful sync does not itself trigger one, so those
/// rows stay dirty until the next trigger past the window. Nothing is lost —
/// a push sends every dirty row, not just the one that triggered it, so the
/// next sync (manual, or a later save) carries them. The exposure is a user
/// saving their last section within the cooldown and immediately closing the
/// app; [requestBackgroundPush] is what narrows that particular case.
///
/// ## Background push is best-effort, NOT guaranteed
///
/// [requestBackgroundPush] fires from `AppLifecycleState.paused`, at which
/// point Android gives no contract that the process keeps running long
/// enough to finish a network round-trip. It may be frozen (Android 12+
/// cached-process freezer), Doze-restricted, or killed outright — and the
/// aggressive OEM battery managers common on budget field devices make this
/// materially more likely, not less. A short push on a good connection
/// usually lands; a slow connection, a large photo backlog, or an
/// aggressive OEM will cut it off partway.
///
/// That is acceptable *because nothing depends on it*: a push that doesn't
/// finish leaves its rows dirty, exactly as if it had never run, and the
/// next trigger (resume, a later save, or the manual button) sends them.
/// It shortens the window where data lives only on the device; it does not
/// close it. Closing it properly would need WorkManager or a foreground
/// service — real background execution, deliberately out of scope here.
class SyncController extends ChangeNotifier {
  /// [autoDebounce] and [autoCooldown] are injectable purely for tests —
  /// production always uses the defaults. The cooldown is measured against
  /// `DateTime.now()`, which no Timer-based fake clock can shift, so tests
  /// shorten the real windows rather than trying to virtualize time.
  SyncController(
    this._syncService, {
    this.autoDebounce = defaultAutoDebounce,
    this.autoCooldown = defaultAutoCooldown,
    this.successRevert = defaultSuccessRevert,
  });

  final SyncService _syncService;

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  DateTime? _lastSyncedAt;

  /// When the last run that actually reached the server finished. Session
  /// only — not persisted, so it resets on app restart.
  DateTime? get lastSyncedAt => _lastSyncedAt;

  int _blockedCount = 0;

  /// Set alongside [status] when it's [SyncStatus.partial] — the count the
  /// AppBar's "needs attention" label shows.
  int get blockedCount => _blockedCount;

  /// Reverts [status] to [SyncStatus.idle] [successRevert] after a fully
  /// clean success, restoring the normal Sync button.
  /// Restarted (not stacked) on every new success, so only the most recent
  /// run's timer ever fires. Deliberately NOT applied to [SyncStatus.partial]
  /// or [SyncStatus.failure] — both are standing issues the user may need to
  /// act on, and auto-hiding them would be a regression, not a fix.
  Timer? _revertTimer;

  /// The run currently in flight, if any. A second request while one is
  /// running joins that run instead of starting a parallel one — two
  /// concurrent pushes of the same dirty rows would race each other's
  /// dirty-flag clearing for no benefit.
  Future<SyncOutcome>? _inFlight;

  bool get isSyncing => _inFlight != null;

  /// How long rapid automatic triggers are collapsed for. Saving three
  /// sections in a row fires three requests; they should cost one sync, not
  /// three. Only the last one's timer survives — see [requestSync].
  static const defaultAutoDebounce = Duration(seconds: 3);

  /// How long after a successful sync automatic triggers are ignored, so a
  /// burst of saves just after a sync doesn't re-hit the server for a few
  /// rows. Manual sync always bypasses this.
  static const defaultAutoCooldown = Duration(seconds: 30);

  /// How long a clean success stays on screen before [status] falls back to
  /// [SyncStatus.idle] and the AppBar shows the normal Sync button again.
  /// Long enough to be read, short enough not to linger — the confirmation
  /// has been seen by then, and the persistent green label otherwise reads
  /// as a state the user has to do something about.
  static const defaultSuccessRevert = Duration(seconds: 10);

  final Duration autoDebounce;
  final Duration autoCooldown;
  final Duration successRevert;

  Timer? _debounceTimer;

  /// Completes the future handed back to a debounced automatic request.
  /// Nullable payload so a request that never runs — superseded by a manual
  /// sync, or dropped at [dispose] — still completes instead of leaving a
  /// caller's await hanging forever.
  Completer<SyncOutcome?>? _pendingAuto;

  /// Runs a full sync — Material Master pull, core survey pull, then push —
  /// updating [status] as it goes and returning everything the run produced.
  ///
  /// Returns null when the request was deliberately not run: an automatic
  /// trigger inside [autoCooldown], or one superseded by a later trigger
  /// inside [autoDebounce]. A [manual] request never returns null.
  ///
  /// [manual] marks a user-initiated run (the Sync button). It does not
  /// change what a sync *does* — only whether the debounce/cooldown gates
  /// apply, and how loudly the UI reports the result. A user who taps Sync
  /// asked for a sync and must always get a real attempt.
  ///
  /// Never throws: [SyncService] already converts every failure into a
  /// [SyncResult]. Safe to fire and forget.
  Future<SyncOutcome?> requestSync({required bool manual}) {
    if (manual) {
      // Supersedes any pending automatic run — it's about to do the same
      // work, immediately, and reporting one result is less confusing than
      // two syncs firing seconds apart. The superseded request is completed
      // with this run's outcome rather than dropped, so nothing awaiting it
      // hangs.
      _debounceTimer?.cancel();
      _debounceTimer = null;
      final superseded = _pendingAuto;
      _pendingAuto = null;
      final run = _runExclusive(manual: true);
      if (superseded != null && !superseded.isCompleted) {
        unawaited(run.then((outcome) {
          if (!superseded.isCompleted) superseded.complete(outcome);
        }));
      }
      return run;
    }

    final since = _lastSyncedAt;
    if (since != null && DateTime.now().difference(since) < autoCooldown) {
      // Nothing is lost by skipping: the rows this save dirtied stay dirty,
      // and the next trigger past the cooldown pushes ALL dirty rows, not
      // just its own. See the class doc for the bounded risk window.
      return Future<SyncOutcome?>.value();
    }

    _debounceTimer?.cancel();
    final pending = _pendingAuto ??= Completer<SyncOutcome?>();
    _debounceTimer = Timer(autoDebounce, () async {
      _debounceTimer = null;
      _pendingAuto = null;
      final outcome = await _runExclusive(manual: false);
      if (!pending.isCompleted) pending.complete(outcome);
    });
    return pending.future;
  }

  /// Push-only, fired when the app is being backgrounded, to get local edits
  /// out before the user leaves. **Best-effort, not guaranteed** — see the
  /// "Background push" section of this class's doc.
  ///
  /// Deliberately skips both automatic gates, unlike every other automatic
  /// trigger:
  ///
  ///  * **Debounce** would defeat the purpose entirely. Waiting
  ///    [autoDebounce] before starting means the timer almost certainly
  ///    never fires — the process is being suspended in exactly that window.
  ///  * **Cooldown** would drop precisely the case this exists for: an edit
  ///    made shortly after a sync, with the user then leaving the app. That
  ///    edit is the one at risk, and it's the one the cooldown would skip.
  ///
  /// Cheap when there's nothing to do: [SyncService.pushAll] only touches
  /// rows flagged dirty, so with a clean queue this is a few local queries
  /// and no network round-trip at all. Single-flight still applies — if a
  /// full sync is already running it joins that instead of racing it.
  Future<SyncOutcome> requestBackgroundPush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final superseded = _pendingAuto;
    _pendingAuto = null;
    final run = _runExclusive(manual: false, pushOnly: true);
    if (superseded != null && !superseded.isCompleted) {
      unawaited(run.then((outcome) {
        if (!superseded.isCompleted) superseded.complete(outcome);
      }));
    }
    return run;
  }

  /// Single-flight: one sync at a time, later callers join the running one.
  Future<SyncOutcome> _runExclusive({
    required bool manual,
    bool pushOnly = false,
  }) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final run = _run(manual: manual, pushOnly: pushOnly)
        .whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<SyncOutcome> _run({
    required bool manual,
    bool pushOnly = false,
  }) async {
    _setStatus(SyncStatus.syncing);

    // Pull before push: Material Master rows added centrally in Supabase,
    // and core survey data (sites, source/inlet points, ...) added/edited on
    // another device, since the last sync both land locally first, so this
    // run's push (and anything the user does right after tapping Sync) sees
    // them.
    //
    // Skipped entirely for a push-only run: pulling data into an app the
    // user is walking away from has no value, and every millisecond spent
    // on it is one the push may not get (see requestBackgroundPush). The
    // stand-in results are `success: true` because the pulls were never
    // attempted — treating "not run" as a failure would wrongly downgrade a
    // clean push to SyncStatus.failure via syncFullySucceeded below.
    const notAttempted = SyncResult(success: true);
    // End-to-end wall clock for the whole run, so the per-phase SYNCPERF
    // lines emitted inside SyncService can be checked against one number the
    // user actually waits for. See _SyncPerf in sync_service.dart.
    final runWatch = Stopwatch()..start();
    final materialMasterPull = pushOnly
        ? notAttempted
        : await _syncService.pullMaterialMasterItems();
    final corePull =
        pushOnly ? notAttempted : await _syncService.pullCoreSurveyData();
    final push = await _syncService.pushAll();
    debugPrint(
      'SYNCPERF RUN TOTAL wall ${runWatch.elapsedMilliseconds}ms '
      'manual=$manual pushOnly=$pushOnly',
    );

    // "Fully synced" is NOT push.success — pushAll() isolates per-row
    // failures and still returns success:true with those rows left dirty
    // (see syncFullySucceeded's doc). Reporting a partial push or a failed
    // pull as a success was the false-success bug: an RLS-rejected site
    // stayed dirty on the device while the AppBar showed a green "Synced
    // just now", so the failure was invisible. A run only counts as a
    // success when it left nothing unsynced — for every table pushAll()
    // touches, since pushFailures aggregates them all.
    final fullySynced = syncFullySucceeded(push, corePull);
    final blocked = push.syncBlocked;

    final SyncStatus outcomeStatus;
    if (fullySynced && blocked == 0) {
      // Clean success: everything pushable pushed, nothing standing needs
      // attention. The only tier that auto-fades back to idle.
      outcomeStatus = SyncStatus.success;
      _lastSyncedAt = DateTime.now();
      _blockedCount = 0;
      _revertTimer?.cancel();
      _revertTimer = Timer(successRevert, () {
        _setStatus(SyncStatus.idle);
      });
    } else if (fullySynced) {
      // Everything that COULD sync did — but a standing set of rows can
      // never sync with this account. Retrying won't fix that, so this is
      // neither a clean success nor a failure of this run.
      outcomeStatus = SyncStatus.partial;
      _lastSyncedAt = DateTime.now();
      _blockedCount = blocked;
    } else {
      // Something retryable failed (a per-row push failure and/or the core
      // pull) — genuinely worth another attempt, unlike the partial case.
      outcomeStatus = SyncStatus.failure;
    }
    // Notified unconditionally, NOT via _setStatus: [lastSyncedAt] and
    // [blockedCount] can change while [status] itself stays the same (two
    // partial runs in a row with different counts, or two successes a minute
    // apart), and a status-equality guard would swallow those updates and
    // leave the AppBar showing stale numbers.
    _status = outcomeStatus;
    _notify();

    return SyncOutcome(
      status: outcomeStatus,
      manual: manual,
      push: push,
      materialMasterPull: materialMasterPull,
      corePull: corePull,
    );
  }

  /// Set once [dispose] runs. A sync already in flight when the account
  /// switches (or the app shuts down) still completes — it's a plain
  /// awaited Future, nothing cancels it — and would otherwise call
  /// [notifyListeners] on a disposed notifier, which throws. Its result is
  /// simply irrelevant by then: a new account has its own controller.
  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setStatus(SyncStatus next) {
    if (_status == next) return;
    _status = next;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _revertTimer?.cancel();
    _debounceTimer?.cancel();
    // A debounced request that will now never run still has to complete, or
    // anything awaiting it hangs for the process's lifetime.
    final pending = _pendingAuto;
    _pendingAuto = null;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    super.dispose();
  }
}
