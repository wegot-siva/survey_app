import '../models/bom_manual_edit_snapshot.dart';
import '../models/bom_manual_edit_snapshot_line.dart';
import '../models/bom_manual_entry.dart';
import '../models/bom_revision.dart';
import '../models/bom_revision_line.dart';
import '../models/bom_snapshot.dart';
import '../models/bom_snapshot_line.dart';
import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
import '../models/engineer.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_audit_entry.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_assignment_audit_entry.dart';
import '../models/survey_photo.dart';

/// The single gateway between the UI and stored survey data.
///
/// PROJECT RULE: UI/screens must NEVER touch storage directly — all reads and
/// writes go through a [SurveyRepository]. The local implementation is sqflite;
/// an in-memory stub backs widget tests.
abstract class SurveyRepository {
  /// Lists sites, ordered by name. Excludes soft-deleted (archived) sites
  /// unless [includeArchived] is true — sync needs the full set so an
  /// archived site's already-recorded survey/BoM/photo data keeps syncing;
  /// every UI list should use the default (active only). [dirtyOnly] limits
  /// to sites not yet pushed since their last local change — sync-only, see
  /// [markSiteSynced].
  Future<List<Site>> getSites({bool includeArchived = false, bool dirtyOnly = false});

  Future<Site?> getSiteById(String id);

  /// Creates and persists a new site, returning the stored instance.
  Future<Site> createSite({required String name, List<String> blocks});

  Future<void> updateSite(Site site);

  /// Replaces a site's block list. Leaves the site name and client inputs
  /// untouched (unlike [updateSite], which writes the whole site). Blocks
  /// have no independent dirty flag — they ride on the site's own (see
  /// [markSiteSynced]), since they have no stable per-row id.
  Future<void> updateSiteBlocks(String siteId, List<String> blocks);

  /// Saves (or replaces) the Client inputs form for an existing site.
  Future<void> saveClientInputs(String siteId, ClientInputs inputs);

  /// Whether [siteId]'s Client inputs have changed locally since they last
  /// synced successfully. Tracked independently of the site row itself (see
  /// [markSiteSynced] vs [markClientInputsSynced]) so editing one never
  /// forces a redundant push of the other.
  Future<bool> isClientInputsDirty(String siteId);

  /// Clears the sync-pending flag for [siteId]'s site row (and blocks, which
  /// share this flag — see [updateSiteBlocks]). Call once that row's push to
  /// Supabase has succeeded.
  Future<void> markSiteSynced(String siteId);

  /// Clears the sync-pending flag for [siteId]'s Client inputs. Call once
  /// that row's push to Supabase has succeeded.
  Future<void> markClientInputsSynced(String siteId);

  // ---- Source points (a site has many) ------------------------------------

  /// [dirtyOnly] limits to points not yet pushed since their last local
  /// change — sync-only, see [markSourcePointSynced]. Never includes a
  /// point pending deletion (see [deleteSourcePoint]) — deletion is
  /// immediate from every normal read's point of view.
  Future<List<SourcePoint>> getSourcePoints(String siteId, {bool dirtyOnly = false});

  /// Persists a new source point, assigning it an id, and returns it.
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint);

  Future<void> updateSourcePoint(SourcePoint sourcePoint);

  /// Marks [id] for deletion (a tombstone, not a hard delete) so sync can
  /// still push a remote delete for it — the row disappears from every
  /// normal read immediately, but survives in storage until
  /// [hardDeleteSourcePoint] is called once that remote delete succeeds.
  Future<void> deleteSourcePoint(String id);

  /// Every source point id currently pending deletion for [siteId] —
  /// sync-only, see [deleteSourcePoint] / [hardDeleteSourcePoint].
  Future<List<String>> getPendingDeleteSourcePointIds(String siteId);

  /// Physically removes a pending-delete row. Call only after that id's
  /// remote delete has actually succeeded — see [getPendingDeleteSourcePointIds].
  Future<void> hardDeleteSourcePoint(String id);

  /// Clears the sync-pending flag for source point [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markSourcePointSynced(String id);

  // ---- Inlet points (a site has many) -------------------------------------

  /// [dirtyOnly] limits to points not yet pushed since their last local
  /// change — sync-only, see [markInletPointSynced]. Never includes a point
  /// pending deletion (see [deleteInletPoint]) — deletion is immediate from
  /// every normal read's point of view.
  Future<List<InletPoint>> getInletPoints(String siteId, {bool dirtyOnly = false});

  /// Persists a new inlet point, assigning it an id, and returns it.
  Future<InletPoint> addInletPoint(InletPoint inletPoint);

  Future<void> updateInletPoint(InletPoint inletPoint);

  /// Marks [id] for deletion (a tombstone, not a hard delete) so sync can
  /// still push a remote delete for it — the row disappears from every
  /// normal read immediately, but survives in storage until
  /// [hardDeleteInletPoint] is called once that remote delete succeeds.
  Future<void> deleteInletPoint(String id);

  /// Every inlet point id currently pending deletion for [siteId] —
  /// sync-only, see [deleteInletPoint] / [hardDeleteInletPoint].
  Future<List<String>> getPendingDeleteInletPointIds(String siteId);

  /// Physically removes a pending-delete row. Call only after that id's
  /// remote delete has actually succeeded — see [getPendingDeleteInletPointIds].
  Future<void> hardDeleteInletPoint(String id);

  /// Clears the sync-pending flag for inlet point [id]. Call once that row's
  /// push to Supabase has succeeded.
  Future<void> markInletPointSynced(String id);

  // ---- Duct LoRa units (a site has many) ----------------------------------

  /// [dirtyOnly] limits to units not yet pushed since their last local
  /// change — sync-only, see [markDuctLoraSynced].
  Future<List<DuctLora>> getDuctLoras(String siteId, {bool dirtyOnly = false});

  /// Persists a new Duct LoRa unit, assigning it an id, and returns it.
  Future<DuctLora> addDuctLora(DuctLora ductLora);

  Future<void> updateDuctLora(DuctLora ductLora);

  Future<void> deleteDuctLora(String id);

  /// Clears the sync-pending flag for Duct LoRa unit [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markDuctLoraSynced(String id);

  // ---- Gateways (a site has many) -----------------------------------------

  /// [dirtyOnly] limits to gateways not yet pushed since their last local
  /// change — sync-only, see [markGatewaySynced].
  Future<List<Gateway>> getGateways(String siteId, {bool dirtyOnly = false});

  /// Persists a new gateway, assigning it an id, and returns it.
  Future<Gateway> addGateway(Gateway gateway);

  Future<void> updateGateway(Gateway gateway);

  Future<void> deleteGateway(String id);

  /// Clears the sync-pending flag for gateway [id]. Call once that row's push
  /// to Supabase has succeeded.
  Future<void> markGatewaySynced(String id);

  // ---- Footer (one per site, like Client inputs) --------------------------

  /// Returns the site's Footer form, or null if not filled yet.
  Future<Footer?> getFooter(String siteId);

  /// Saves (or replaces) the Footer form for an existing site.
  Future<void> saveFooter(String siteId, Footer footer);

  /// Whether [siteId]'s Footer has changed locally since it last synced
  /// successfully.
  Future<bool> isFooterDirty(String siteId);

  /// Clears the sync-pending flag for [siteId]'s Footer. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markFooterSynced(String siteId);

  // ---- Material Master (admin-editable reference data, not site-scoped) ---
  //
  // Every create/edit/delete writes to the change log (material_master_audit)
  // as part of the same call — [changedByRole] is the signed-in role's label
  // (e.g. "Admin"), recorded against each audit entry.

  /// [dirtyOnly] limits to rows not yet pushed since their last local
  /// change — sync-only, see [markMaterialMasterItemSynced].
  Future<List<MaterialMasterItem>> getMaterialMasterItems({bool dirtyOnly = false});

  /// Persists a new Material Master row, assigning it an id, and returns it.
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  });

  /// Updates an existing row and logs one change-log entry per field that
  /// actually changed (diffed against the row currently stored under
  /// [item.id]).
  Future<void> updateMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  });

  /// Deletes a row and logs a single change-log entry summarizing what was
  /// removed.
  Future<void> deleteMaterialMasterItem(String id, {required String changedByRole});

  /// Clears the sync-pending flag for Material Master row [id]. Call once
  /// that row's push to Supabase has succeeded.
  Future<void> markMaterialMasterItemSynced(String id);

  /// Merges Supabase's material_master_items rows into local storage, keyed
  /// by id: inserts anything new, and overwrites anything existing — unless
  /// that local row has an unsynced edit of its own (still dirty), in which
  /// case it's left untouched so a pull never clobbers an admin's in-flight
  /// change before it's had a chance to push. Merged rows are never marked
  /// dirty themselves — they came from Supabase, the table's source of
  /// truth, so they're already in sync.
  ///
  /// The pull half of Material Master's sync (the other tables here are all
  /// device-authored and push-only) — Material Master is populated
  /// centrally (e.g. a bulk SQL import of the plumbing catalog) and needs to
  /// reach every device, not just the one that entered it.
  Future<void> upsertMaterialMasterItemsFromRemote(
    List<MaterialMasterItem> remoteItems,
  );

  /// The full Material Master change log, newest first. [dirtyOnly] limits
  /// to entries not yet pushed — sync-only, see
  /// [markMaterialMasterAuditEntrySynced].
  Future<List<MaterialMasterAuditEntry>> getMaterialMasterAuditLog({
    bool dirtyOnly = false,
  });

  /// Clears the sync-pending flag for change-log entry [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markMaterialMasterAuditEntrySynced(String id);

  // ---- Photos (polymorphic, slot-based — photo slice 2) -------------------

  /// All photos for one owner record, ordered by slot then position.
  Future<List<SurveyPhoto>> getPhotos(String ownerType, String ownerId);

  /// Replaces the full photo set for ([ownerType], [ownerId]) with [photos]:
  /// rows not present are deleted, new ones (empty id) inserted, existing ones
  /// updated. Lets a form submit its whole desired set in one call while
  /// preserving each kept photo's remote-path linkage.
  Future<void> setPhotos(
    String ownerType,
    String ownerId,
    List<SurveyPhoto> photos,
  );

  /// Every photo across all owners — used by sync to find pending uploads.
  /// [dirtyOnly] limits to photos not yet pushed since their last local
  /// change — sync-only, see [markPhotoSynced].
  Future<List<SurveyPhoto>> getAllPhotos({bool dirtyOnly = false});

  /// Updates one photo row by id (e.g. sync writing back a remote path).
  Future<void> updatePhoto(SurveyPhoto photo);

  /// Clears the sync-pending flag for photo [id]. Call once that row's push
  /// to Supabase has succeeded.
  Future<void> markPhotoSynced(String id);

  // ---- BoM manual entries (D/E/G "Add materials" picker) -------------------
  //
  // Never read by BomEngine — these feed into a snapshot only at the moment
  // [finalizeBom] runs. Reachable from the BoM preview screen for any survey
  // regardless of status, and still editable after that survey's BoM has been
  // finalized — doing so has no effect on the frozen snapshot (see
  // [finalizeBom]).

  /// All manual entries for one survey, oldest first. [dirtyOnly] limits to
  /// entries not yet pushed since their last local change — sync-only, see
  /// [markBomManualEntrySynced].
  Future<List<BomManualEntry>> getBomManualEntries(
    String surveyId, {
    bool dirtyOnly = false,
  });

  /// Persists a new manual entry, assigning it an id, and returns it.
  Future<BomManualEntry> addBomManualEntry(BomManualEntry entry);

  /// Updates an existing entry. [entry.addedBy] / [entry.addedAt] are carried
  /// over from the original entry, not re-stamped — this is an edit, not a
  /// new addition.
  Future<void> updateBomManualEntry(BomManualEntry entry);

  Future<void> deleteBomManualEntry(String id);

  /// Clears the sync-pending flag for manual entry [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markBomManualEntrySynced(String id);

  // ---- BoM snapshots (Finalize — immutable, frozen BoM) --------------------
  //
  // Version 1 only in this slice — no revisions/re-finalize flow. Once a
  // survey has a snapshot, editing Material Master or bom_manual_entries can
  // never alter it: [finalizeBom] copies every value in at write time.

  /// The survey's snapshot, if its BoM has been finalized. Null otherwise.
  Future<BomSnapshot?> getBomSnapshot(String surveyId);

  /// Whether [surveyId]'s BoM snapshot row itself is pending sync. False if
  /// there is no snapshot yet.
  Future<bool> isBomSnapshotDirty(String surveyId);

  /// Clears the sync-pending flag for the BoM snapshot row [id]. Call once
  /// that row's push to Supabase has succeeded.
  Future<void> markBomSnapshotSynced(String id);

  /// A snapshot's frozen lines, in the order they were written. [dirtyOnly]
  /// limits to lines not yet pushed — sync-only, see
  /// [markBomSnapshotLineSynced].
  Future<List<BomSnapshotLine>> getBomSnapshotLines(
    String snapshotId, {
    bool dirtyOnly = false,
  });

  /// Clears the sync-pending flag for snapshot line [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markBomSnapshotLineSynced(String id);

  /// Freezes [lines] as a new, permanent [BomSnapshot] for [surveyId] and
  /// flips that survey's `bomLocked` flag. [lines]' `id` / `snapshotId` are
  /// ignored (assigned fresh). Idempotent: if [surveyId] already has a
  /// snapshot, returns it unchanged rather than creating a duplicate.
  Future<BomSnapshot> finalizeBom({
    required String surveyId,
    required List<BomSnapshotLine> lines,
    required String finalizedBy,
  });

  // ---- BoM revisions (additive deltas on top of a locked v1 snapshot) ------
  //
  // Version 2+ only — v1 is the BomSnapshot above. A revision's own row and
  // its lines never change after creation; a later correction is a new
  // revision, not an edit. The running total (see BomRevisionEngine) is
  // computed on read only, from the v1 snapshot lines plus every revision's
  // delta lines — no per-version total is ever stored.

  /// All revisions for a survey, oldest first (v2, v3, ...). Empty if the
  /// survey has no revisions yet. [dirtyOnly] limits to revisions not yet
  /// pushed — sync-only, see [markBomRevisionSynced].
  Future<List<BomRevision>> getBomRevisions(String surveyId, {bool dirtyOnly = false});

  /// Clears the sync-pending flag for revision [id]. Call once that row's
  /// push to Supabase has succeeded.
  Future<void> markBomRevisionSynced(String id);

  /// One revision's delta lines, in the order they were written. [dirtyOnly]
  /// limits to lines not yet pushed — sync-only, see
  /// [markBomRevisionLineSynced].
  Future<List<BomRevisionLine>> getBomRevisionLines(
    String revisionId, {
    bool dirtyOnly = false,
  });

  /// Clears the sync-pending flag for revision line [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markBomRevisionLineSynced(String id);

  /// Creates a new revision — version is (the survey's highest existing
  /// version across both bom_revisions and bom_manual_edit_snapshots, or 1
  /// if neither exists) + 1 — plus its delta lines, in one atomic write.
  /// [lines]' `id` / `revisionId` are ignored (assigned fresh). Sharing the
  /// version counter with bom_manual_edit_snapshots keeps every version
  /// number unique regardless of which table created it.
  Future<BomRevision> addBomRevision({
    required String surveyId,
    required String reason,
    required List<BomRevisionLine> lines,
    required String createdBy,
  });

  // ---- BoM manual-edit snapshots (Admin/Approver full-version edits) -------
  //
  // Version 2+, sharing the same version counter as bom_revisions (see
  // addBomManualEditSnapshot) — a manual edit can change a line's identity
  // fields (SKU, name), so unlike a revision it can't be expressed as a
  // delta; each save is instead a brand-new, complete, immutable line list.
  // A row here never changes after creation; a later correction is a new
  // manual edit, not an edit to this one.

  /// All manual-edit snapshots for a survey, oldest first. [dirtyOnly] limits
  /// to snapshots not yet pushed — sync-only, see
  /// [markBomManualEditSnapshotSynced].
  Future<List<BomManualEditSnapshot>> getBomManualEditSnapshots(
    String surveyId, {
    bool dirtyOnly = false,
  });

  /// Clears the sync-pending flag for manual-edit snapshot [id]. Call once
  /// that row's push to Supabase has succeeded.
  Future<void> markBomManualEditSnapshotSynced(String id);

  /// One manual-edit snapshot's full line list, in the order they were
  /// written. [dirtyOnly] limits to lines not yet pushed — sync-only, see
  /// [markBomManualEditSnapshotLineSynced].
  Future<List<BomManualEditSnapshotLine>> getBomManualEditSnapshotLines(
    String snapshotId, {
    bool dirtyOnly = false,
  });

  /// Clears the sync-pending flag for manual-edit snapshot line [id]. Call
  /// once that row's push to Supabase has succeeded.
  Future<void> markBomManualEditSnapshotLineSynced(String id);

  /// Creates a new manual-edit snapshot — version is (the survey's highest
  /// existing version across both bom_revisions and
  /// bom_manual_edit_snapshots, or 1 if neither exists) + 1 — plus its full
  /// line list, in one atomic write. [lines]' `id` / `snapshotId` are ignored
  /// (assigned fresh). [basedOnVersion] is recorded for traceability only.
  Future<BomManualEditSnapshot> addBomManualEditSnapshot({
    required String surveyId,
    required int basedOnVersion,
    required String reason,
    required List<BomManualEditSnapshotLine> lines,
    required String editedBy,
  });

  // ---- Engineer roster + survey reassignment -------------------------------
  //
  // A lightweight roster, not an auth system — the shared Engineer login is
  // unchanged (see UserRole / SessionController.currentEngineerName).
  // Reassignment is only meaningful while a survey is still 'assigned' —
  // enforced here (throws StateError otherwise), not just hidden in the UI —
  // and each change writes one audit row recording who it moved from/to.

  /// The engineer roster Sales assigns/reassigns surveys against.
  Future<List<Engineer>> getEngineers();

  /// Reassigns [siteId] to [newAssignee] and writes one audit entry. Throws
  /// [StateError] if the site doesn't exist or its status isn't 'assigned'.
  Future<void> reassignSurvey({
    required String siteId,
    required String newAssignee,
    required String changedByRole,
  });

  /// One survey's reassignment history, newest first.
  Future<List<SurveyAssignmentAuditEntry>> getSurveyAssignmentAuditLog(
    String siteId,
  );
}
