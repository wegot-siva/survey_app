import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_survey_data_source.dart';
import '../data/survey_repository.dart';
import '../models/engineer.dart';
import '../models/survey_photo.dart';
import 'photo_file_store.dart';
import 'supabase_service.dart';

/// Outcome of a sync run, surfaced to the UI.
class SyncResult {
  const SyncResult({
    required this.success,
    this.sites = 0,
    this.blocks = 0,
    this.clientInputs = 0,
    this.sourcePoints = 0,
    this.inletPoints = 0,
    this.ductLoras = 0,
    this.gateways = 0,
    this.footers = 0,
    this.materialMasterItems = 0,
    this.materialMasterAuditEntries = 0,
    this.photos = 0,
    this.bomManualEntries = 0,
    this.bomSnapshots = 0,
    this.bomRevisions = 0,
    this.bomManualEditSnapshots = 0,
    this.pushFailures = const [],
    this.syncBlocked = 0,
    this.message,
  });

  final bool success;
  final int sites;
  final int blocks;
  final int clientInputs;
  final int sourcePoints;
  final int inletPoints;
  final int ductLoras;
  final int gateways;
  final int footers;
  final int materialMasterItems;
  final int materialMasterAuditEntries;
  final int photos;
  final int bomManualEntries;
  final int bomSnapshots;
  final int bomRevisions;
  final int bomManualEditSnapshots;

  /// One entry per row that failed to push during this run (e.g. an
  /// RLS-rejected write) — each already skipped and left dirty for the next
  /// sync attempt, not why the whole run failed. Empty on a fully clean run.
  /// [success] can still be true with this non-empty: the run completed and
  /// pushed everything it could, it just didn't get everything.
  final List<String> pushFailures;

  /// How many local rows are currently sync-blocked — refused by RLS
  /// (Postgres 42501), so retrying them can never succeed with this
  /// account. Distinct from [pushFailures]: those are retryable and DO mean
  /// the run wasn't fully successful; these are a standing condition the
  /// user has to resolve (a row belonging to someone else's site, or one
  /// that only ever existed on this device). Reported separately by the UI
  /// as "N rows can't sync — needs attention" rather than re-failing the
  /// sync forever. See SurveyRepository.markSiteSyncBlocked.
  final int syncBlocked;

  final String? message;
}

/// Whether a whole sync run — push + the core survey-data pull — fully
/// succeeded, i.e. nothing was left unsynced.
///
/// This is the single source of truth the UI must use to decide "did this
/// sync actually work", NOT [SyncResult.success] alone. [pushAll] isolates
/// per-row failures on purpose (an RLS-rejected or otherwise-failing row is
/// caught, left dirty for the next attempt, and does NOT abort the run), so
/// it returns `success: true` even when it skipped rows — [success] means
/// "the run didn't crash", not "everything reached the server". Reporting a
/// run with skipped rows (or a failed pull) as a success is exactly the
/// false-success bug: the row silently stays dirty while the status says
/// "Synced". [SyncResult.pushFailures] aggregates skips across EVERY table
/// [pushAll] touches, so gating on it here covers all of them uniformly —
/// not a per-table check.
///
/// [corePull] is [SyncService.pullCoreSurveyData]'s result; a failed pull
/// also means the device isn't fully in sync, so it counts against success
/// too. Material Master's pull is deliberately excluded — it's global
/// reference data on its own separate path, and its failure doesn't mean
/// this device's own survey data failed to sync.
bool syncFullySucceeded(SyncResult push, SyncResult corePull) =>
    push.success && push.pushFailures.isEmpty && corePull.success;

/// Log tag for every timing line this file emits. Grep a logcat capture for
/// it to get one sync run's full breakdown:
///
///     adb logcat -d | grep SYNCPERF
const String _perfTag = 'SYNCPERF';

/// How many core-table pulls may be in flight at once.
///
/// Measured on device, the 16 core tables fetched sequentially cost ~4.3 s of
/// almost pure round-trip latency — each table takes about the same ~270 ms
/// regardless of whether it returns 2 rows or 230, so the run was dominated
/// by waiting, not by data.
///
/// 6 rather than all 16: past a handful of parallel connections a phone stops
/// gaining (the requests contend for the same radio and the slowest one sets
/// the finish time), and a burst of 16 is also noticeably ruder to PostgREST
/// when 20 engineers sync at once. Measured contention at up to 24 concurrent
/// requests was flat, so this is a deliberately conservative cap, not a
/// measured ceiling.
const int _pullConcurrency = 6;

/// Timing instrumentation for one sync phase.
///
/// Exists because the sync performance work needs a real on-device baseline
/// to measure each optimisation against — desktop numbers don't settle
/// whether a change helped on the hardware this app actually runs on.
///
/// Deliberately separates the two costs that get conflated when only the
/// total is known:
///   * `fetch` — time on the network, waiting for PostgREST.
///   * `apply` — time writing what came back into local sqlite.
///
/// That split is the whole point. A pull dominated by `fetch` is a
/// round-trip problem (fixed by fetching concurrently / making fewer
/// requests); one dominated by `apply` is a local storage problem. The two
/// have completely different fixes, and the total alone can't tell them
/// apart.
///
/// Uses [debugPrint] rather than a metrics sink: this is a development
/// measurement aid read off logcat during a tuning round, not telemetry.
class _SyncPerf {
  _SyncPerf(this.phase);

  final String phase;
  final Stopwatch _wall = Stopwatch()..start();

  int fetchMs = 0;
  int applyMs = 0;
  int rows = 0;
  int tables = 0;

  /// Network time spent pushing individual rows, and how many were attempted
  /// (see [pushAll]'s pushRow). Both stay 0 for a pull phase.
  int netMs = 0;
  int netRows = 0;

  int get wallMs => _wall.elapsedMilliseconds;

  /// Runs one table's [fetch] and [apply], timing them separately, and
  /// returns whatever [apply] returned (photos hand back the orphaned local
  /// paths their pull detected, so this can't just return void).
  Future<R> table<T, R>(
    String label,
    Future<List<T>> Function() fetch,
    Future<R> Function(List<T>) apply,
  ) async {
    final sw = Stopwatch()..start();
    final fetched = await fetch();
    final fetchedMs = sw.elapsedMilliseconds;
    sw.reset();
    final result = await apply(fetched);
    final appliedMs = sw.elapsedMilliseconds;

    fetchMs += fetchedMs;
    applyMs += appliedMs;
    rows += fetched.length;
    tables++;
    debugPrint(
      '$_perfTag $phase/$label fetch ${fetchedMs}ms '
      'rows ${fetched.length} apply ${appliedMs}ms',
    );
    return result;
  }

  /// Wall time of the concurrent fetch stage, when there is one. Distinct
  /// from [fetchMs], which stays a *sum* of the individual fetches — once
  /// they overlap, that sum deliberately exceeds this. Comparing the two is
  /// how much the concurrency actually bought.
  int fetchWallMs = 0;

  /// Per-table fetch durations, held until the matching apply reports, so
  /// one line can still carry both halves even though the fetch finished
  /// much earlier and out of order.
  final Map<String, int> _fetchByLabel = {};

  /// Times one table's fetch. Safe to run concurrently with other calls —
  /// only the accumulators are touched, and Dart's single isolate makes
  /// those updates atomic between await points.
  Future<T> timedFetch<T extends List<Object?>>(
    String label,
    Future<T> Function() fetch,
  ) async {
    final sw = Stopwatch()..start();
    final fetched = await fetch();
    _fetchByLabel[label] = sw.elapsedMilliseconds;
    fetchMs += sw.elapsedMilliseconds;
    rows += fetched.length;
    tables++;
    return fetched;
  }

  /// Times one table's local apply and emits the combined line for it.
  Future<void> timedApply(
    String label,
    int rowCount,
    Future<void> Function() apply,
  ) async {
    final sw = Stopwatch()..start();
    await apply();
    final appliedMs = sw.elapsedMilliseconds;
    applyMs += appliedMs;
    debugPrint(
      '$_perfTag $phase/$label fetch ${_fetchByLabel[label] ?? 0}ms '
      'rows $rowCount apply ${appliedMs}ms',
    );
  }

  /// Times an un-tabled step (photo file downloads, the site enumeration at
  /// the top of a push) without folding it into the per-table totals.
  Future<T> step<T>(String label, Future<T> Function() body) async {
    final sw = Stopwatch()..start();
    try {
      return await body();
    } finally {
      debugPrint('$_perfTag $phase/$label ${sw.elapsedMilliseconds}ms');
    }
  }

  /// One summary line closing the phase. For a push, `local` is everything
  /// that wasn't network — the per-site query pass, which is the cost that
  /// grows with total site count rather than with what actually changed.
  void done() {
    // Concurrent fetches overlap, so their *sum* no longer represents time
    // the run actually spent; subtract the stage's wall clock instead, or
    // `local` would go absurdly negative and mean nothing.
    final networkWall = fetchWallMs > 0 ? fetchWallMs : fetchMs;
    final local = wallMs - netMs - networkWall;
    debugPrint(
      '$_perfTag $phase TOTAL wall ${wallMs}ms tables $tables rows $rows '
      'fetch ${fetchMs}ms fetchWall ${fetchWallMs}ms apply ${applyMs}ms '
      'net ${netMs}ms netRows $netRows local ${local}ms',
    );
  }
}

/// One table's pull: what to fetch, and how to write it into local storage.
///
/// Kept as an ordered list (see [SyncService.pullCoreSurveyData]) because the
/// two halves have opposite requirements — fetches are independent and want
/// to overlap, applies are foreign-key ordered and must not.
class _PullTable {
  const _PullTable(this.label, this.fetch, this.apply);

  final String label;
  final Future<List<Map<String, dynamic>>> Function() fetch;
  final Future<void> Function(List<Map<String, dynamic>>) apply;
}

/// Counting semaphore bounding how many pulls are in flight at once.
///
/// A phone opening 16 simultaneous HTTPS connections tends to do worse than
/// one opening 6: connection setup competes for the same radio, and the
/// tail latency of the slowest request grows. The cap keeps the win without
/// that.
class _Semaphore {
  _Semaphore(this._permits);

  int _permits;
  final List<Completer<void>> _waiting = [];

  Future<void> acquire() {
    if (_permits > 0) {
      _permits--;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _permits++;
    }
  }
}

/// Mostly-push sync (Phase 3): reads local data via [SurveyRepository] and
/// upserts it to Supabase via [SupabaseSurveyDataSource].
///
/// Dirty-tracking: every synced table carries a local `dirty` flag (see
/// [SurveyRepository]'s `dirtyOnly` params / `isXxxDirty` / `markXxxSynced`
/// methods), so each run only pushes rows that changed locally since they
/// last synced successfully — not the whole table every time. A fresh
/// install (or a device upgrading onto this dirty-tracking schema) has every
/// row starting dirty, so the very first sync still pushes everything once;
/// every sync after that only pushes what actually changed. The UI never
/// touches storage directly; it only calls [pushAll].
///
/// Deletions (Source Points, Inlet Points, Duct LoRa units, Gateways, and BoM
/// manual entries — plus Material Master, handled separately below) are the
/// exception to "push-only": a locally-deleted row is a tombstone (see e.g.
/// [SurveyRepository.deleteSourcePoint]) until its remote row is actually
/// deleted too — see the matching `getPendingDeleteXxxIds`/`hardDeleteXxx`
/// pair for each table below — so a delete never leaves an orphaned row in
/// Supabase. Every other table here (client_inputs, footers, snapshots,
/// revisions, ...) has no delete feature at all, so needs no tombstone.
class SyncService {
  SyncService(
    this._repository,
    this._supabase,
    this._remote, {
    PhotoFileStore? photoFiles,
  }) : _photoFiles = photoFiles ?? PhotoFileStore();

  final SurveyRepository _repository;
  final SupabaseService _supabase;
  final SupabaseSurveyDataSource _remote;

  /// Owns the device-local photo folder — used by the pull half to write
  /// downloaded images and to clean up files behind tombstoned photos.
  /// Injectable so tests can point it somewhere disposable.
  final PhotoFileStore _photoFiles;

  Future<SyncResult> pushAll() async {
    if (!_supabase.isConfigured) {
      return const SyncResult(
        success: false,
        message: 'Supabase is not configured.\n\nRun with '
            '--dart-define-from-file=.env so credentials are available.',
      );
    }

    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      return const SyncResult(
        success: false,
        message: 'Supabase failed to initialize. Check your keys in .env.',
      );
    }

    // Per-row failure isolation: a single row's push failing here (an RLS
    // rejection once site-scoped RLS lands, a transient network blip, ...)
    // must not abort the rest of this run — every failure is caught, the
    // row stays dirty locally for the next sync attempt exactly like an
    // offline failure already worked before this fix, and its own
    // table/id/error goes into [failures] so it's identifiable rather than
    // folded into one generic "couldn't sync". Only a genuinely fatal,
    // whole-run problem (missing config, a thrown error outside any single
    // row's push) still produces success:false — see the outer try/catch.
    final failures = <String>[];
    final perf = _SyncPerf('push');

    /// [onPermissionDenied], when given, is invoked instead of recording a
    /// retryable failure if the push is refused with Postgres 42501
    /// ("violates row-level security policy"). That code is an
    /// authorization verdict, not a transient error: the same account
    /// re-sending the same row can never succeed, so retrying it every sync
    /// forever just reproduces an identical failure and permanently poisons
    /// the sync status. The callback marks the row sync_blocked (keeping
    /// its local edit — see SurveyRepository.markSiteSyncBlocked), which
    /// takes it out of the push queue and into a separate "needs attention"
    /// count the UI reports distinctly. Every other error stays a normal
    /// retryable failure.
    Future<bool> pushRow(
      String label,
      Future<void> Function() action, {
      Future<void> Function()? onPermissionDenied,
    }) async {
      // Every remote write in this method goes through here, so accumulating
      // around `action` captures the phase's entire network cost. What's left
      // over in the summary line is the per-site local query pass.
      final sw = Stopwatch()..start();
      try {
        await action();
        return true;
      } catch (e) {
        if (e is PostgrestException) {
          debugPrint(
            'sync: $label failed (PostgrestException): '
            'message=${e.message} code=${e.code} details=${e.details} '
            'hint=${e.hint}',
          );
          if (e.code == '42501' && onPermissionDenied != null) {
            await onPermissionDenied();
            debugPrint('sync: $label marked sync-blocked (not retried again)');
            return false;
          }
        } else {
          debugPrint('sync: $label failed (${e.runtimeType}): $e');
        }
        failures.add('$label: $e');
        return false;
      } finally {
        perf.netMs += sw.elapsedMilliseconds;
        perf.netRows++;
      }
    }

    try {
      // Archived sites are excluded from every UI list, but their already-
      // recorded survey/BoM/photo data must keep syncing — nothing archived
      // is ever deleted, so nothing archived should stop syncing either.
      //
      // Every site is visited (not just dirty ones) because a site's
      // children (source points, footer, client inputs, ...) are each
      // dirty-tracked independently of the site row itself — a site whose
      // own row hasn't changed can still have a newly-added source point.
      // dirtySiteIds narrows which sites actually get their *row* re-pushed.
      // Both enumerations are timed together: getSites hydrates every row
      // with a per-site blocks + client_inputs query, so this alone is
      // already O(sites) round-trips into local sqlite before the per-site
      // loop below adds ~18 more each.
      final dirtySiteIds = await perf.step('enumerateDirty', () async =>
          (await _repository.getSites(includeArchived: true, dirtyOnly: true))
              .map((s) => s.id)
              .toSet());
      final sites = await perf.step('enumerateAll',
          () => _repository.getSites(includeArchived: true));

      var pushedSites = 0;
      var blocks = 0;
      var clientInputs = 0;
      var sourcePoints = 0;
      var inletPoints = 0;
      var ductLoras = 0;
      var gateways = 0;
      var footers = 0;
      var bomManualEntries = 0;
      var bomSnapshots = 0;
      var bomRevisions = 0;
      var bomManualEditSnapshots = 0;
      for (final site in sites) {
        if (dirtySiteIds.contains(site.id)) {
          final ok = await pushRow(
            'sites/${site.id}',
            () async {
              await _remote.pushSite(site);
              await _repository.markSiteSynced(site.id);
            },
            onPermissionDenied: () =>
                _repository.markSiteSyncBlocked(site.id),
          );
          if (ok) pushedSites++;
        }

        // Blocks — tracked independently of the site row (Full sync Group 1's
        // blocks-push rework: each block has its own stable id and dirty
        // flag now, no longer bundled into the site's delete-all-and-
        // reinsert). Deletions pushed first, same tombstone convention as
        // every other per-row-deletable table below.
        for (final id in await _repository.getPendingDeleteBlockIds(site.id)) {
          final ok = await pushRow(
            'blocks/$id (delete)',
            () async {
              await _remote.deleteBlock(id);
              await _repository.hardDeleteBlock(id);
            },
            onPermissionDenied: () => _repository.markBlockSyncBlocked(id),
          );
          if (ok) blocks++;
        }
        for (final block in await _repository.getBlocks(
          site.id,
          dirtyOnly: true,
        )) {
          final ok = await pushRow(
            'blocks/${block.id}',
            () async {
              await _remote.pushBlock(block);
              await _repository.markBlockSynced(block.id);
            },
            onPermissionDenied: () =>
                _repository.markBlockSyncBlocked(block.id),
          );
          if (ok) blocks++;
        }

        // Client inputs — tracked independently, so a site-only edit never
        // forces a redundant push here (and vice versa).
        final inputs = site.clientInputs;
        if (inputs != null && await _repository.isClientInputsDirty(site.id)) {
          final ok = await pushRow('client_inputs/${site.id}', () async {
            await _remote.pushClientInputs(site.id, inputs);
            await _repository.markClientInputsSynced(site.id);
          });
          if (ok) clientInputs++;
        }

        // Deletions are pushed before normal upserts: a source/inlet point
        // marked for deletion (see SurveyRepository.deleteSourcePoint) stays
        // in local storage as a tombstone until its remote row is actually
        // gone, so a delete that fails partway (offline, etc.) is retried
        // on the next sync exactly like any other unsynced change.
        for (final id in await _repository.getPendingDeleteSourcePointIds(
          site.id,
        )) {
          final ok = await pushRow('source_points/$id (delete)', () async {
            await _remote.deleteSourcePoint(id);
            await _repository.hardDeleteSourcePoint(id);
          });
          if (ok) sourcePoints++;
        }
        for (final sp in await _repository.getSourcePoints(
          site.id,
          dirtyOnly: true,
        )) {
          final ok = await pushRow('source_points/${sp.id}', () async {
            await _remote.pushSourcePoint(sp);
            await _repository.markSourcePointSynced(sp.id);
          });
          if (ok) sourcePoints++;
        }

        for (final id in await _repository.getPendingDeleteInletPointIds(
          site.id,
        )) {
          final ok = await pushRow('inlet_points/$id (delete)', () async {
            await _remote.deleteInletPoint(id);
            await _repository.hardDeleteInletPoint(id);
          });
          if (ok) inletPoints++;
        }
        for (final ip in await _repository.getInletPoints(
          site.id,
          dirtyOnly: true,
        )) {
          final ok = await pushRow('inlet_points/${ip.id}', () async {
            await _remote.pushInletPoint(ip);
            await _repository.markInletPointSynced(ip.id);
          });
          if (ok) inletPoints++;
        }

        for (final id in await _repository.getPendingDeleteDuctLoraIds(
          site.id,
        )) {
          final ok = await pushRow('duct_loras/$id (delete)', () async {
            await _remote.deleteDuctLora(id);
            await _repository.hardDeleteDuctLora(id);
          });
          if (ok) ductLoras++;
        }
        for (final dl in await _repository.getDuctLoras(
          site.id,
          dirtyOnly: true,
        )) {
          final ok = await pushRow('duct_loras/${dl.id}', () async {
            await _remote.pushDuctLora(dl);
            await _repository.markDuctLoraSynced(dl.id);
          });
          if (ok) ductLoras++;
        }

        for (final id in await _repository.getPendingDeleteGatewayIds(
          site.id,
        )) {
          final ok = await pushRow('gateways/$id (delete)', () async {
            await _remote.deleteGateway(id);
            await _repository.hardDeleteGateway(id);
          });
          if (ok) gateways++;
        }
        for (final gw in await _repository.getGateways(
          site.id,
          dirtyOnly: true,
        )) {
          final ok = await pushRow('gateways/${gw.id}', () async {
            await _remote.pushGateway(gw);
            await _repository.markGatewaySynced(gw.id);
          });
          if (ok) gateways++;
        }

        if (await _repository.isFooterDirty(site.id)) {
          final footer = await _repository.getFooter(site.id);
          if (footer != null) {
            final ok = await pushRow('footers/${site.id}', () async {
              await _remote.pushFooter(site.id, footer);
              await _repository.markFooterSynced(site.id);
            });
            if (ok) footers++;
          }
        }

        for (final id in await _repository.getPendingDeleteBomManualEntryIds(
          site.id,
        )) {
          final ok = await pushRow(
            'bom_manual_entries/$id (delete)',
            () async {
              await _remote.deleteBomManualEntry(id);
              await _repository.hardDeleteBomManualEntry(id);
            },
          );
          if (ok) bomManualEntries++;
        }
        for (final entry in await _repository.getBomManualEntries(
          site.id,
          dirtyOnly: true,
        )) {
          final ok = await pushRow('bom_manual_entries/${entry.id}', () async {
            await _remote.pushBomManualEntry(entry);
            await _repository.markBomManualEntrySynced(entry.id);
          });
          if (ok) bomManualEntries++;
        }

        // The snapshot row and its lines are each dirty-tracked separately —
        // lines never change after finalize, so once pushed they never
        // become dirty again, but the row and lines can still finish syncing
        // on different runs if an earlier sync was interrupted partway —
        // which is also why lines are attempted below regardless of whether
        // the row itself was dirty (and pushed successfully) this round.
        final snapshot = await _repository.getBomSnapshot(site.id);
        if (snapshot != null) {
          if (await _repository.isBomSnapshotDirty(site.id)) {
            final ok = await pushRow('bom_snapshots/${snapshot.id}', () async {
              await _remote.pushBomSnapshot(snapshot);
              await _repository.markBomSnapshotSynced(snapshot.id);
            });
            if (ok) bomSnapshots++;
          }
          for (final line in await _repository.getBomSnapshotLines(
            snapshot.id,
            dirtyOnly: true,
          )) {
            await pushRow('bom_snapshot_lines/${line.id}', () async {
              await _remote.pushBomSnapshotLine(line);
              await _repository.markBomSnapshotLineSynced(line.id);
            });
          }
        }

        for (final revision in await _repository.getBomRevisions(
          site.id,
          dirtyOnly: true,
        )) {
          final revisionOk = await pushRow('bom_revisions/${revision.id}', () async {
            await _remote.pushBomRevision(revision);
            await _repository.markBomRevisionSynced(revision.id);
          });
          if (revisionOk) bomRevisions++;
          // Lines FK-reference this revision row remotely — if the row
          // itself didn't make it there this round, pushing its lines would
          // just fail on that FK too; skip and retry the whole revision
          // (row + lines) together next sync instead of adding a second,
          // confusing failure for the same underlying cause.
          if (!revisionOk) continue;
          for (final line in await _repository.getBomRevisionLines(
            revision.id,
            dirtyOnly: true,
          )) {
            await pushRow('bom_revision_lines/${line.id}', () async {
              await _remote.pushBomRevisionLine(line);
              await _repository.markBomRevisionLineSynced(line.id);
            });
          }
        }

        for (final edit in await _repository.getBomManualEditSnapshots(
          site.id,
          dirtyOnly: true,
        )) {
          final editOk = await pushRow(
            'bom_manual_edit_snapshots/${edit.id}',
            () async {
              await _remote.pushBomManualEditSnapshot(edit);
              await _repository.markBomManualEditSnapshotSynced(edit.id);
            },
          );
          if (editOk) bomManualEditSnapshots++;
          if (!editOk) continue; // same FK reasoning as bom_revisions above
          for (final line in await _repository.getBomManualEditSnapshotLines(
            edit.id,
            dirtyOnly: true,
          )) {
            await pushRow('bom_manual_edit_snapshot_lines/${line.id}', () async {
              await _remote.pushBomManualEditSnapshotLine(line);
              await _repository.markBomManualEditSnapshotLineSynced(line.id);
            });
          }
        }
      }

      // Material Master is global reference data, not site-scoped — push
      // once, outside the per-site loop. Deletions first (so a delete that
      // fails partway is retried next sync, same convention as source/inlet
      // point tombstones), then dirty upserts.
      var materialMasterItems = 0;
      for (final id in await _repository.getPendingDeleteMaterialMasterItemIds()) {
        final ok = await pushRow(
          'material_master_items/$id (delete)',
          () async {
            await _remote.deleteMaterialMasterItem(id);
            await _repository.hardDeleteMaterialMasterItem(id);
          },
        );
        if (ok) materialMasterItems++;
      }
      for (final material in await _repository.getMaterialMasterItems(
        dirtyOnly: true,
      )) {
        final ok = await pushRow(
          'material_master_items/${material.id}',
          () async {
            await _remote.pushMaterialMasterItem(material);
            await _repository.markMaterialMasterItemSynced(material.id);
          },
        );
        if (ok) materialMasterItems++;
      }

      var materialMasterAuditEntries = 0;
      for (final entry in await _repository.getMaterialMasterAuditLog(
        dirtyOnly: true,
      )) {
        final ok = await pushRow('material_master_audit/${entry.id}', () async {
          await _remote.pushMaterialMasterAuditEntry(entry);
          await _repository.markMaterialMasterAuditEntrySynced(entry.id);
        });
        if (ok) materialMasterAuditEntries++;
      }

      // Generic photos (slice 2): upload any pending files, then push
      // metadata for whichever photo rows are dirty. The upload and the
      // metadata push both happen inside the same pushRow call (unlike the
      // old split that called _withUploadedGenericPhoto outside pushRow) so
      // a Storage failure on one photo is isolated exactly like every other
      // row's failure here, instead of throwing out past pushRow and
      // aborting the rest of this sync run via the outer try/catch below.
      var photos = 0;
      // Removals first, same order as every other table's tombstone push: a
      // photo the user deleted must reach Supabase as a deleted_at write
      // before anything else touches that row. The local row and its image
      // file are only destroyed once the remote write is confirmed, so a
      // delete interrupted by going offline is retried next sync instead of
      // being silently lost (and, before this existed, silently undone by
      // the pull).
      for (final photo in await _repository.getPendingDeletePhotos()) {
        final ok = await pushRow('photos/${photo.id} (delete)', () async {
          await _remote.deletePhoto(photo.id);
          await _repository.hardDeletePhoto(photo.id);
          final localPath = photo.localPath;
          if (localPath != null && localPath.isNotEmpty) {
            await _photoFiles.deleteLocalFile(localPath);
          }
        });
        if (ok) photos++;
      }
      for (final photo in await _repository.getAllPhotos(dirtyOnly: true)) {
        debugPrint(
          'sync: photo ${photo.id} local=${photo.localPath} '
          'remote=${photo.remotePath} site=${photo.siteId} '
          'owner=${photo.ownerType}/${photo.ownerId}',
        );
        final ok = await pushRow('photos/${photo.id}', () async {
          final pushed = await _pushGenericPhoto(photo);
          await _repository.markPhotoSynced(pushed.id);
        });
        if (ok) photos++;
      }

      debugPrint('$_perfTag push/sitesVisited ${sites.length}');
      perf.done();
      return SyncResult(
        success: true,
        sites: pushedSites,
        blocks: blocks,
        clientInputs: clientInputs,
        sourcePoints: sourcePoints,
        inletPoints: inletPoints,
        ductLoras: ductLoras,
        gateways: gateways,
        footers: footers,
        materialMasterItems: materialMasterItems,
        materialMasterAuditEntries: materialMasterAuditEntries,
        photos: photos,
        bomManualEntries: bomManualEntries,
        bomSnapshots: bomSnapshots,
        bomRevisions: bomRevisions,
        bomManualEditSnapshots: bomManualEditSnapshots,
        pushFailures: failures,
        // Total standing blocked rows, not just the ones newly blocked this
        // run — the UI reports a current condition ("N rows can't sync"),
        // and rows blocked on an earlier run are skipped by the push queue
        // so they'd otherwise vanish from the count entirely.
        syncBlocked: await _repository.countSyncBlocked(),
        message: failures.isEmpty
            ? null
            : '${failures.length} row${failures.length == 1 ? '' : 's'} '
                "could not sync (left dirty for next attempt):\n\n"
                '${failures.join('\n')}',
      );
    } on PostgrestException catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed (database):\n\n'
            'message: ${e.message}\n'
            'code: ${e.code}\n'
            'details: ${e.details}\n'
            'hint: ${e.hint}',
      );
    } catch (e) {
      return SyncResult(success: false, message: 'Sync failed:\n\n$e');
    }
  }

  /// Pulls every Material Master row from Supabase and merges it into local
  /// storage (see [SurveyRepository.upsertMaterialMasterItemsFromRemote] for
  /// the merge rule — new rows are inserted, existing ones overwritten,
  /// unless they have an unsynced local edit/delete of their own, and a row
  /// deleted directly in Supabase is reconciled away locally too).
  ///
  /// Material Master was the first table in this file to need a pull, and
  /// still has its own reasons to (global reference data populated/edited
  /// centrally, e.g. bulk SQL against the plumbing catalog) — kept as its
  /// own method, separate from [pullCoreSurveyData]'s "Phase 1" tables and
  /// from [pushAll], so none of the three affect each other.
  ///
  /// Reuses [SyncResult] purely as a convenient result shape (`success`,
  /// `materialMasterItems` count, `message` on failure) — it does not mean a
  /// push happened.
  Future<SyncResult> pullMaterialMasterItems() async {
    if (!_supabase.isConfigured) {
      return const SyncResult(
        success: false,
        message: 'Supabase is not configured.',
      );
    }

    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      return const SyncResult(
        success: false,
        message: 'Supabase failed to initialize. Check your keys in .env.',
      );
    }

    final perf = _SyncPerf('pullMaterialMaster');
    try {
      await perf.table(
        'material_master_items',
        _remote.fetchMaterialMasterItems,
        _repository.upsertMaterialMasterItemsFromRemote,
      );
      perf.done();
      // perf.rows is this phase's only table, so it *is* the fetched count.
      return SyncResult(success: true, materialMasterItems: perf.rows);
    } on PostgrestException catch (e) {
      return SyncResult(
        success: false,
        message: 'Material Master pull failed (database):\n\n'
            'message: ${e.message}\n'
            'code: ${e.code}\n'
            'details: ${e.details}\n'
            'hint: ${e.hint}',
      );
    } catch (e) {
      return SyncResult(success: false, message: 'Material Master pull failed:\n\n$e');
    }
  }

  /// Pulls the "Phase 1" core survey tables — sites, blocks, client_inputs,
  /// footers, source_points, inlet_points, duct_loras, gateways,
  /// bom_manual_entries — same merge-and-reconcile rule as
  /// [pullMaterialMasterItems], generalized (see [SqfliteSurveyRepository]'s
  /// pull-reconcile helper for the shared mechanics). bom_snapshots/
  /// bom_revisions and their line tables (immutable once written) and
  /// survey_assignment_audit (separate decision pending) are deliberately
  /// not part of this phase.
  ///
  /// Before this phase, every one of these tables was push-only — a survey
  /// created or edited on one device would never reach any other device,
  /// since nothing ever pulled it back down. Sites pull first and complete
  /// before any other table's: every other table here FK's to sites, so a
  /// child row pulled before its parent site exists locally would fail its
  /// insert.
  ///
  /// Reuses [SyncResult] purely as a convenient result shape (`success`,
  /// `message` on failure) — it does not mean a push happened, and the
  /// per-table counts are left at their defaults (0): unlike
  /// [pullMaterialMasterItems], there's no single meaningful count to report
  /// across eight different tables.
  Future<SyncResult> pullCoreSurveyData() async {
    if (!_supabase.isConfigured) {
      return const SyncResult(
        success: false,
        message: 'Supabase is not configured.',
      );
    }

    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      return const SyncResult(
        success: false,
        message: 'Supabase failed to initialize. Check your keys in .env.',
      );
    }

    final perf = _SyncPerf('pullCore');
    try {
      // The pull order below is foreign-key ordered and load-bearing for the
      // APPLY half only:
      //   * sites first — every other table here FK's to it, and local sqlite
      //     enforces that (PRAGMA foreign_keys = ON), so a child row written
      //     before its parent site exists fails its insert.
      //   * blocks after sites — it replaces blocks per local site row.
      //   * each BoM parent before its lines — snapshots before
      //     snapshot_lines, revisions before revision_lines, manual-edit
      //     snapshots before their lines.
      //   * photos last — every photo row points at an owner the pulls above
      //     have just landed.
      //
      // The FETCH half has no such constraint: each is an independent GET
      // against a different table, and nothing in a response depends on
      // another response. That asymmetry is what this method exploits —
      // fetch concurrently, apply strictly in this order.
      final plan = <_PullTable>[
        _PullTable('sites', _remote.fetchSites,
            _repository.upsertSitesFromRemote),
        _PullTable('blocks', _remote.fetchBlocks,
            _repository.upsertBlocksFromRemote),
        _PullTable('client_inputs', _remote.fetchClientInputs,
            _repository.upsertClientInputsFromRemote),
        _PullTable('footers', _remote.fetchFooters,
            _repository.upsertFootersFromRemote),
        _PullTable('source_points', _remote.fetchSourcePoints,
            _repository.upsertSourcePointsFromRemote),
        _PullTable('inlet_points', _remote.fetchInletPoints,
            _repository.upsertInletPointsFromRemote),
        _PullTable('duct_loras', _remote.fetchDuctLoras,
            _repository.upsertDuctLorasFromRemote),
        _PullTable('gateways', _remote.fetchGateways,
            _repository.upsertGatewaysFromRemote),
        _PullTable('bom_manual_entries', _remote.fetchBomManualEntries,
            _repository.upsertBomManualEntriesFromRemote),
        _PullTable('bom_snapshots', _remote.fetchBomSnapshots,
            _repository.upsertBomSnapshotsFromRemote),
        _PullTable('bom_snapshot_lines', _remote.fetchBomSnapshotLines,
            _repository.upsertBomSnapshotLinesFromRemote),
        _PullTable('bom_revisions', _remote.fetchBomRevisions,
            _repository.upsertBomRevisionsFromRemote),
        _PullTable('bom_revision_lines', _remote.fetchBomRevisionLines,
            _repository.upsertBomRevisionLinesFromRemote),
        _PullTable('bom_manual_edit_snapshots',
            _remote.fetchBomManualEditSnapshots,
            _repository.upsertBomManualEditSnapshotsFromRemote),
        _PullTable('bom_manual_edit_snapshot_lines',
            _remote.fetchBomManualEditSnapshotLines,
            _repository.upsertBomManualEditSnapshotLinesFromRemote),
        // Any file left behind by a tombstoned photo is deleted here, outside
        // the write transaction that removed the row (see
        // upsertPhotosFromRemote) — which is why this one apply isn't a bare
        // method reference like the rest.
        _PullTable('photos', _remote.fetchPhotos, (rows) async {
          for (final path in await _repository.upsertPhotosFromRemote(rows)) {
            await _photoFiles.deleteLocalFile(path);
          }
        }),
      ];

      // Stage 1 — network, concurrent and bounded.
      //
      // Future.wait (not a bare loop over un-awaited futures) is deliberate:
      // it attaches a listener to every future immediately, so if two tables
      // fail, the second failure is already handled rather than surfacing
      // later as an unhandled async error. The first error still propagates
      // to the catch blocks below, exactly as it did when this was
      // sequential.
      final fetchWatch = Stopwatch()..start();
      final gate = _Semaphore(_pullConcurrency);
      final fetched = await Future.wait([
        for (final t in plan)
          () async {
            await gate.acquire();
            try {
              return await perf.timedFetch(t.label, t.fetch);
            } finally {
              gate.release();
            }
          }(),
      ]);
      perf.fetchWallMs = fetchWatch.elapsedMilliseconds;

      // Stage 2 — local writes, strictly in `plan` order. Every foreign-key
      // guarantee that held when this method was fully sequential still
      // holds here, because this loop is still fully sequential.
      for (var i = 0; i < plan.length; i++) {
        await perf.timedApply(
          plan[i].label,
          fetched[i].length,
          () => plan[i].apply(fetched[i]),
        );
      }
      // Photo FILES are deliberately NOT downloaded here — see
      // [downloadMissingPhotoFilesInBackground], which the sync run starts
      // once it has finished. Measured on device, downloading them inline
      // cost 20.0 s for 12 photos (~1 MB and ~1.7 s each) against a 5.6 s
      // pull: the metadata was long since safe locally while the run was
      // still held open transferring images. It is also the one cost here
      // that is bandwidth-bound rather than round-trip-bound, so no amount
      // of batching or concurrency in this method would have touched it.
      perf.done();
      return const SyncResult(success: true);
    } on PostgrestException catch (e) {
      // Diagnostic instrumentation (forensic sync investigation): this
      // detail was already captured in the returned message, but never
      // logged anywhere and never actually shown in the sync SnackBar (see
      // home_screen.dart's hardcoded "core data pull failed" text) — so it
      // was effectively swallowed despite the code looking like it wasn't.
      debugPrint(
        'sync: pullCoreSurveyData failed (PostgrestException): '
        'message=${e.message} code=${e.code} details=${e.details} '
        'hint=${e.hint}',
      );
      return SyncResult(
        success: false,
        message: 'Core survey data pull failed (database):\n\n'
            'message: ${e.message}\n'
            'code: ${e.code}\n'
            'details: ${e.details}\n'
            'hint: ${e.hint}',
      );
    } catch (e) {
      debugPrint('sync: pullCoreSurveyData failed (${e.runtimeType}): $e');
      return SyncResult(success: false, message: 'Core survey data pull failed:\n\n$e');
    }
  }

  /// The current engineer roster, straight from Supabase — see
  /// [SupabaseSurveyDataSource.fetchEngineerRoster] for why this is a live
  /// query rather than a locally-cached pull. Throws on failure (missing
  /// config, no network, database error) rather than swallowing it, so the
  /// assign/reassign screen can show a real error instead of a silently
  /// empty picker.
  Future<List<Engineer>> fetchEngineerRoster() async {
    if (!_supabase.isConfigured) {
      throw StateError(
        'Supabase is not configured.\n\n'
        'SUPABASE_URL and SUPABASE_ANON_KEY are empty. Copy .env.example to '
        '.env, fill in your values, and run:\n\n'
        '    flutter run --dart-define-from-file=.env',
      );
    }
    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      throw StateError('Supabase failed to initialize. Check your keys in .env.');
    }
    return _remote.fetchEngineerRoster();
  }

  /// Tracks an in-progress background photo download so a second request
  /// joins it rather than starting a duplicate pass over the same rows.
  Future<void>? _photoDownloadInFlight;

  /// Starts a photo-file download pass that does NOT block the caller, and
  /// returns a future for it so tests (and a future "downloading N photos"
  /// indicator) can await completion if they want to.
  ///
  /// The sync run kicks this off after it has already reported its outcome —
  /// photo metadata is fully synced by then, so the user's data is safe and
  /// the run is honestly complete; only the images are still arriving. That
  /// is the whole point of the change: on device, downloading 12 photos
  /// inline added 20.0 s to a 5.6 s pull.
  ///
  /// Single-flight, because syncs can overlap in ways this must not: a
  /// manual tap during the 30 s cooldown, an auto-sync on reconnect, or a
  /// second run starting while a slow download is still going. Two
  /// concurrent passes would see the same rows from
  /// [SurveyRepository.getPhotosMissingLocalFile] (nothing is marked until
  /// each file lands) and download every image twice.
  ///
  /// Never throws: [downloadMissingPhotoFiles] already isolates per-photo
  /// failures, and anything escaping it is logged here rather than left to
  /// surface as an unhandled async error in whatever zone happened to start
  /// the run.
  Future<void> downloadMissingPhotoFilesInBackground() {
    final existing = _photoDownloadInFlight;
    if (existing != null) return existing;

    final run = () async {
      final sw = Stopwatch()..start();
      try {
        final downloaded = await downloadMissingPhotoFiles();
        if (downloaded > 0) {
          debugPrint(
            '$_perfTag photoFiles/background downloaded $downloaded '
            'in ${sw.elapsedMilliseconds}ms',
          );
        }
      } catch (e) {
        debugPrint('sync: background photo download failed: $e');
      }
    }()
        .whenComplete(() => _photoDownloadInFlight = null);

    _photoDownloadInFlight = run;
    return run;
  }

  /// Fetches the image bytes for every photo this device has metadata for
  /// but no local file — i.e. every photo pulled from another device.
  ///
  /// This exists because photo metadata alone is not viewable: every photo
  /// surface in the app renders `File(localPath)` (see PhotoView), so a
  /// pulled row with a null local_path would sync perfectly and still show
  /// nothing. Downloading the file and recording its path is what makes a
  /// pulled photo actually appear — and keeps it working offline afterwards,
  /// which rendering from a Storage URL would not.
  ///
  /// Best-effort per photo: one failed download (offline mid-sync, a missing
  /// object, an RLS refusal) is logged and skipped, leaving that row's
  /// local_path null so the next sync simply tries again. It never fails the
  /// surrounding pull — the metadata is already correctly stored by then,
  /// and a missing image is a far smaller problem than a sync that reports
  /// failure and re-runs everything.
  ///
  /// Idempotent: [SurveyRepository.getPhotosMissingLocalFile] only returns
  /// rows that still lack a file, and [PhotoFileStore.saveDownload] names
  /// each file after the photo id, so nothing is re-fetched or duplicated
  /// once it has landed.
  Future<int> downloadMissingPhotoFiles() async {
    var downloaded = 0;
    for (final photo in await _repository.getPhotosMissingLocalFile()) {
      final objectKey = photo.remotePath;
      if (objectKey == null || objectKey.isEmpty) continue;
      try {
        final bytes = await _remote.downloadPhoto(objectKey);
        final localPath = await _photoFiles.saveDownload(photo.id, bytes);
        // Records the path only — deliberately not updatePhoto, which would
        // re-dirty the row and queue a pointless re-push of a record that
        // hasn't changed remotely. See SurveyRepository.setPhotoLocalPath.
        await _repository.setPhotoLocalPath(photo.id, localPath);
        downloaded++;
      } catch (e) {
        debugPrint(
          'sync: photo ${photo.id} download failed ($objectKey): $e — '
          'left without a local file, will retry next sync',
        );
      }
    }
    return downloaded;
  }

  /// Pushes [photo] to Supabase, uploading its file to Storage first if it
  /// hasn't been already. Already-uploaded photos (remotePath set) just get
  /// their metadata row refreshed. For a never-uploaded photo, the metadata
  /// row is pushed *before* the Storage upload — reversed from how this used
  /// to work — because Slice 2h's storage.objects RLS resolves a photo
  /// object's site by joining back to this table via remote_path
  /// (can_access_photo_object(name), see schema.sql); if the upload ran
  /// first, that join would find nothing yet and the very first upload of
  /// every photo would be rejected. The object key is deterministic
  /// (`photos/<id>.jpg`), so it's known — and can be pushed — before the
  /// file itself exists in Storage. A missing local file on a never-uploaded
  /// photo throws (surfaces as a failure for this row, isolated by the
  /// caller's pushRow) rather than being silently skipped.
  Future<SurveyPhoto> _pushGenericPhoto(SurveyPhoto photo) async {
    if (photo.remotePath != null) {
      await _remote.pushPhoto(photo);
      return photo;
    }

    final localPath = photo.localPath;
    if (localPath == null || !await File(localPath).exists()) {
      throw StateError(
        'no local file at $localPath to upload for photo ${photo.id}',
      );
    }

    final objectKey = 'photos/${photo.id}.jpg';
    final withRemotePath = photo.withRemotePath(objectKey);
    await _remote.pushPhoto(withRemotePath);
    debugPrint('sync: photo ${photo.id} uploading $localPath -> $objectKey');
    await _remote.uploadPhoto(localPath, objectKey);
    debugPrint('sync: photo ${photo.id} upload complete');
    await _repository.updatePhoto(withRemotePath);
    return withRemotePath;
  }
}
