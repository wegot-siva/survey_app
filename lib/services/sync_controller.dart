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
class SyncController extends ChangeNotifier {
  SyncController(this._syncService);

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

  /// Reverts [status] to [SyncStatus.idle] 45s after a fully clean success.
  /// Restarted (not stacked) on every new success, so only the most recent
  /// run's timer ever fires. Deliberately NOT applied to [SyncStatus.partial]
  /// or [SyncStatus.failure] — both are standing issues the user may need to
  /// act on, and auto-hiding them would be a regression, not a fix.
  Timer? _revertTimer;

  /// The run currently in flight, if any. A second request while one is
  /// running joins that run instead of starting a parallel one — two
  /// concurrent pushes of the same dirty rows would race each other's
  /// dirty-flag clearing for no benefit. Harmless today (only the Sync
  /// button can start a run, and it takes a deliberate double-tap to
  /// overlap), and load-bearing once automatic triggers land.
  Future<SyncOutcome>? _inFlight;

  bool get isSyncing => _inFlight != null;

  /// Runs a full sync — Material Master pull, core survey pull, then push —
  /// updating [status] as it goes and returning everything the run produced.
  ///
  /// [manual] marks a user-initiated run (the Sync button). It does not
  /// change what the sync does; it's carried through to [SyncOutcome] so the
  /// UI can decide how loudly to report the result.
  ///
  /// Never throws: [SyncService] already converts every failure into a
  /// [SyncResult], and this returns the resulting outcome instead of
  /// propagating. Safe to fire and forget.
  Future<SyncOutcome> requestSync({required bool manual}) {
    final existing = _inFlight;
    if (existing != null) return existing;

    final run = _run(manual: manual).whenComplete(() => _inFlight = null);
    _inFlight = run;
    return run;
  }

  Future<SyncOutcome> _run({required bool manual}) async {
    _setStatus(SyncStatus.syncing);

    // Pull before push: Material Master rows added centrally in Supabase,
    // and core survey data (sites, source/inlet points, ...) added/edited on
    // another device, since the last sync both land locally first, so this
    // run's push (and anything the user does right after tapping Sync) sees
    // them.
    final materialMasterPull = await _syncService.pullMaterialMasterItems();
    final corePull = await _syncService.pullCoreSurveyData();
    final push = await _syncService.pushAll();

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
      _revertTimer = Timer(const Duration(seconds: 45), () {
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
    super.dispose();
  }
}
