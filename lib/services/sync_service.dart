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
/// Deletions (Source Points, Inlet Points, Duct LoRa units, Gateways, and BoM
/// manual entries — plus Material Master, handled separately below) are the
/// exception to "push-only": a locally-deleted row is a tombstone (see e.g.
/// [SurveyRepository.deleteSourcePoint]) until its remote row is actually
/// deleted too — see the matching `getPendingDeleteXxxIds`/`hardDeleteXxx`
/// pair for each table below — so a delete never leaves an orphaned row in
/// Supabase. Every other table here (client_inputs, footers, snapshots,
/// revisions, ...) has no delete feature at all, so needs no tombstone.
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

        for (final id in await _repository.getPendingDeleteDuctLoraIds(
          site.id,
        )) {
          await _remote.deleteDuctLora(id);
          await _repository.hardDeleteDuctLora(id);
          ductLoras++;
        }
        final dls = await _repository.getDuctLoras(site.id, dirtyOnly: true);
        for (final dl in dls) {
          await _remote.pushDuctLora(dl);
          await _repository.markDuctLoraSynced(dl.id);
        }
        ductLoras += dls.length;

        for (final id in await _repository.getPendingDeleteGatewayIds(
          site.id,
        )) {
          await _remote.deleteGateway(id);
          await _repository.hardDeleteGateway(id);
          gateways++;
        }
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

        for (final id in await _repository.getPendingDeleteBomManualEntryIds(
          site.id,
        )) {
          await _remote.deleteBomManualEntry(id);
          await _repository.hardDeleteBomManualEntry(id);
          bomManualEntries++;
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
      // once, outside the per-site loop. Deletions first (so a delete that
      // fails partway is retried next sync, same convention as source/inlet
      // point tombstones), then dirty upserts.
      var materialMasterItems = 0;
      for (final id in await _repository.getPendingDeleteMaterialMasterItemIds()) {
        await _remote.deleteMaterialMasterItem(id);
        await _repository.hardDeleteMaterialMasterItem(id);
        materialMasterItems++;
      }
      final materials = await _repository.getMaterialMasterItems(dirtyOnly: true);
      for (final material in materials) {
        await _remote.pushMaterialMasterItem(material);
        await _repository.markMaterialMasterItemSynced(material.id);
      }
      materialMasterItems += materials.length;

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
        materialMasterItems: materialMasterItems,
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

  /// Pulls the "Phase 1" core survey tables — sites, client_inputs, footers,
  /// source_points, inlet_points, duct_loras, gateways, bom_manual_entries —
  /// same merge-and-reconcile rule as [pullMaterialMasterItems], generalized
  /// (see [SqfliteSurveyRepository]'s pull-reconcile helper for the shared
  /// mechanics). bom_snapshots/bom_revisions and their line tables
  /// (immutable once written) and engineers/survey_assignment_audit
  /// (separate decision pending) are deliberately not part of this phase.
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

    try {
      await _repository.upsertSitesFromRemote(await _remote.fetchSites());
      await _repository.upsertClientInputsFromRemote(
        await _remote.fetchClientInputs(),
      );
      await _repository.upsertFootersFromRemote(await _remote.fetchFooters());
      await _repository.upsertSourcePointsFromRemote(
        await _remote.fetchSourcePoints(),
      );
      await _repository.upsertInletPointsFromRemote(
        await _remote.fetchInletPoints(),
      );
      await _repository.upsertDuctLorasFromRemote(await _remote.fetchDuctLoras());
      await _repository.upsertGatewaysFromRemote(await _remote.fetchGateways());
      await _repository.upsertBomManualEntriesFromRemote(
        await _remote.fetchBomManualEntries(),
      );
      return const SyncResult(success: true);
    } on PostgrestException catch (e) {
      return SyncResult(
        success: false,
        message: 'Core survey data pull failed (database):\n\n'
            'message: ${e.message}\n'
            'code: ${e.code}\n'
            'details: ${e.details}\n'
            'hint: ${e.hint}',
      );
    } catch (e) {
      return SyncResult(success: false, message: 'Core survey data pull failed:\n\n$e');
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
