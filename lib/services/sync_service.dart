import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_survey_data_source.dart';
import '../data/survey_repository.dart';
import '../models/survey_photo.dart';
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
  final String? message;
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
/// Deletions (Source/Inlet Points only, so far) are the one exception to
/// "push-only": a locally-deleted row is a tombstone (see
/// [SurveyRepository.deleteSourcePoint]) until its remote row is actually
/// deleted too — see `getPendingDeleteSourcePointIds`/`hardDeleteSourcePoint`
/// below — so a delete never leaves an orphaned row in Supabase.
class SyncService {
  SyncService(this._repository, this._supabase, this._remote);

  final SurveyRepository _repository;
  final SupabaseService _supabase;
  final SupabaseSurveyDataSource _remote;

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
      final dirtySiteIds = (await _repository.getSites(
        includeArchived: true,
        dirtyOnly: true,
      )).map((s) => s.id).toSet();
      final sites = await _repository.getSites(includeArchived: true);

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
        // Site row + blocks — bundled (see SupabaseSurveyDataSource.pushSite),
        // so both share the site's own dirty flag.
        if (dirtySiteIds.contains(site.id)) {
          await _remote.pushSite(site);
          await _repository.markSiteSynced(site.id);
          pushedSites++;
          blocks += site.blocks.length;
        }

        // Client inputs — tracked independently, so a site-only edit never
        // forces a redundant push here (and vice versa).
        final inputs = site.clientInputs;
        if (inputs != null && await _repository.isClientInputsDirty(site.id)) {
          await _remote.pushClientInputs(site.id, inputs);
          await _repository.markClientInputsSynced(site.id);
          clientInputs++;
        }

        // Deletions are pushed before normal upserts: a source/inlet point
        // marked for deletion (see SurveyRepository.deleteSourcePoint) stays
        // in local storage as a tombstone until its remote row is actually
        // gone, so a delete that fails partway (offline, etc.) is retried
        // on the next sync exactly like any other unsynced change.
        for (final id in await _repository.getPendingDeleteSourcePointIds(
          site.id,
        )) {
          await _remote.deleteSourcePoint(id);
          await _repository.hardDeleteSourcePoint(id);
          sourcePoints++;
        }
        final sps = await _repository.getSourcePoints(site.id, dirtyOnly: true);
        for (final sp in sps) {
          await _remote.pushSourcePoint(sp);
          await _repository.markSourcePointSynced(sp.id);
        }
        sourcePoints += sps.length;

        for (final id in await _repository.getPendingDeleteInletPointIds(
          site.id,
        )) {
          await _remote.deleteInletPoint(id);
          await _repository.hardDeleteInletPoint(id);
          inletPoints++;
        }
        final ips = await _repository.getInletPoints(site.id, dirtyOnly: true);
        for (final ip in ips) {
          await _remote.pushInletPoint(ip);
          await _repository.markInletPointSynced(ip.id);
        }
        inletPoints += ips.length;

        final dls = await _repository.getDuctLoras(site.id, dirtyOnly: true);
        for (final dl in dls) {
          await _remote.pushDuctLora(dl);
          await _repository.markDuctLoraSynced(dl.id);
        }
        ductLoras += dls.length;

        final gws = await _repository.getGateways(site.id, dirtyOnly: true);
        for (final gw in gws) {
          await _remote.pushGateway(gw);
          await _repository.markGatewaySynced(gw.id);
        }
        gateways += gws.length;

        if (await _repository.isFooterDirty(site.id)) {
          final footer = await _repository.getFooter(site.id);
          if (footer != null) {
            await _remote.pushFooter(site.id, footer);
            await _repository.markFooterSynced(site.id);
            footers++;
          }
        }

        final manualEntries = await _repository.getBomManualEntries(
          site.id,
          dirtyOnly: true,
        );
        for (final entry in manualEntries) {
          await _remote.pushBomManualEntry(entry);
          await _repository.markBomManualEntrySynced(entry.id);
        }
        bomManualEntries += manualEntries.length;

        // The snapshot row and its lines are each dirty-tracked separately —
        // lines never change after finalize, so once pushed they never
        // become dirty again, but the row and lines can still finish syncing
        // on different runs if an earlier sync was interrupted partway.
        final snapshot = await _repository.getBomSnapshot(site.id);
        if (snapshot != null) {
          if (await _repository.isBomSnapshotDirty(site.id)) {
            await _remote.pushBomSnapshot(snapshot);
            await _repository.markBomSnapshotSynced(snapshot.id);
            bomSnapshots++;
          }
          final lines = await _repository.getBomSnapshotLines(
            snapshot.id,
            dirtyOnly: true,
          );
          for (final line in lines) {
            await _remote.pushBomSnapshotLine(line);
            await _repository.markBomSnapshotLineSynced(line.id);
          }
        }

        final revisions = await _repository.getBomRevisions(
          site.id,
          dirtyOnly: true,
        );
        for (final revision in revisions) {
          await _remote.pushBomRevision(revision);
          await _repository.markBomRevisionSynced(revision.id);
          final lines = await _repository.getBomRevisionLines(
            revision.id,
            dirtyOnly: true,
          );
          for (final line in lines) {
            await _remote.pushBomRevisionLine(line);
            await _repository.markBomRevisionLineSynced(line.id);
          }
        }
        bomRevisions += revisions.length;

        final manualEdits = await _repository.getBomManualEditSnapshots(
          site.id,
          dirtyOnly: true,
        );
        for (final edit in manualEdits) {
          await _remote.pushBomManualEditSnapshot(edit);
          await _repository.markBomManualEditSnapshotSynced(edit.id);
          final lines = await _repository.getBomManualEditSnapshotLines(
            edit.id,
            dirtyOnly: true,
          );
          for (final line in lines) {
            await _remote.pushBomManualEditSnapshotLine(line);
            await _repository.markBomManualEditSnapshotLineSynced(line.id);
          }
        }
        bomManualEditSnapshots += manualEdits.length;
      }

      // Material Master is global reference data, not site-scoped — push
      // just the dirty rows once, outside the per-site loop.
      final materials = await _repository.getMaterialMasterItems(
        dirtyOnly: true,
      );
      for (final material in materials) {
        await _remote.pushMaterialMasterItem(material);
        await _repository.markMaterialMasterItemSynced(material.id);
      }

      final auditEntries = await _repository.getMaterialMasterAuditLog(
        dirtyOnly: true,
      );
      for (final entry in auditEntries) {
        await _remote.pushMaterialMasterAuditEntry(entry);
        await _repository.markMaterialMasterAuditEntrySynced(entry.id);
      }

      // Generic photos (slice 2): upload any pending files, then push
      // metadata for whichever photo rows are dirty.
      var photos = 0;
      for (final photo in await _repository.getAllPhotos(dirtyOnly: true)) {
        final pushed = await _withUploadedGenericPhoto(photo);
        if (pushed.remotePath != null) {
          await _remote.pushPhoto(pushed);
          await _repository.markPhotoSynced(pushed.id);
          photos++;
        }
      }

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
        materialMasterItems: materials.length,
        materialMasterAuditEntries: auditEntries.length,
        photos: photos,
        bomManualEntries: bomManualEntries,
        bomSnapshots: bomSnapshots,
        bomRevisions: bomRevisions,
        bomManualEditSnapshots: bomManualEditSnapshots,
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
  /// the merge rule — new rows are inserted, existing ones overwritten
  /// unless they have an unsynced local edit of their own).
  ///
  /// Material Master is the one table in this file that needs a pull at
  /// all: it's global reference data populated centrally (e.g. a bulk SQL
  /// import of the plumbing catalog), so a row entered directly in Supabase
  /// must still reach every device — unlike every other table here, which is
  /// device-authored and reaches Supabase by push alone. Deliberately kept
  /// separate from [pushAll] rather than folded into its loop, so push
  /// behavior for every table (including Material Master's own push) is
  /// completely unaffected by this method existing.
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

    try {
      final remoteItems = await _remote.fetchMaterialMasterItems();
      await _repository.upsertMaterialMasterItemsFromRemote(remoteItems);
      return SyncResult(success: true, materialMasterItems: remoteItems.length);
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

  /// If [photo] has a locally-captured file not yet uploaded, uploads it to
  /// Storage, records the remote key locally (write-back, so we don't
  /// re-upload on the next sync), and returns the updated photo. A missing
  /// local file (already uploaded, or moved) is skipped, not an error.
  Future<SurveyPhoto> _withUploadedGenericPhoto(SurveyPhoto photo) async {
    final localPath = photo.localPath;
    if (localPath == null || photo.remotePath != null) return photo;
    if (!await File(localPath).exists()) return photo;

    final objectKey = 'photos/${photo.id}.jpg';
    await _remote.uploadPhoto(localPath, objectKey);
    final updated = photo.withRemotePath(objectKey);
    await _repository.updatePhoto(updated);
    return updated;
  }
}
