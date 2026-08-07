import '../models/block.dart';
import '../models/bom_manual_edit_snapshot.dart';
import '../models/bom_manual_edit_snapshot_line.dart';
import '../models/bom_manual_entry.dart';
import '../models/bom_revision.dart';
import '../models/bom_revision_line.dart';
import '../models/bom_snapshot.dart';
import '../models/bom_snapshot_line.dart';
import '../models/client_inputs.dart';
import '../models/duct_lora.dart';
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
  /// Creates a site. Only [name] is mandatory — [address], [clientName] and
  /// [clientContact] are the same Sales-owned metadata
  /// [EditSiteDetailsScreen] edits, accepted here too so creating a site and
  /// immediately reopening it to fill them in isn't the normal path. They are
  /// deliberately NOT the engineer's on-site Client Inputs (note
  /// `ClientInputs.clientPocName`/`clientPocContact` are a different,
  /// similarly-named pair owned by a different role).
  Future<Site> createSite({
    required String name,
    List<String> blocks,
    String address,
    String clientName,
    String clientContact,
  });

  Future<void> updateSite(Site site);

  /// Replaces a site's block list with [blocks] (a flat list of labels — the
  /// UI, [ManageBlocksScreen], has no concept of a block's identity beyond
  /// its position). Internally reconciled against the site's currently
  /// stored blocks (each with its own stable id) via [diffBlocks] — an
  /// unchanged label produces no write at all, a changed one updates that
  /// row in place, a shorter list tombstones the excess, a longer one
  /// inserts new rows — rather than deleting and recreating the whole set,
  /// which had no way to tell a genuinely unchanged block from a
  /// deleted-then-recreated one and could resurrect a block another device
  /// had already deleted (Full sync Group 1's blocks-push investigation).
  /// Leaves the site name and client inputs untouched (unlike [updateSite],
  /// which writes the whole site). Blocks have had their own per-row dirty
  /// flag since that rework — no longer rides on the site row's.
  Future<void> updateSiteBlocks(String siteId, List<String> blocks);

  /// Saves (or replaces) the Client inputs form for an existing site.
  Future<void> saveClientInputs(String siteId, ClientInputs inputs);

  /// Whether [siteId]'s Client inputs have changed locally since they last
  /// synced successfully. Tracked independently of the site row itself (see
  /// [markSiteSynced] vs [markClientInputsSynced]) so editing one never
  /// forces a redundant push of the other.
  Future<bool> isClientInputsDirty(String siteId);

  /// Clears the sync-pending flag for [siteId]'s site row. Call once that
  /// row's push to Supabase has succeeded. Blocks are tracked independently
  /// — see [markBlockSynced].
  Future<void> markSiteSynced(String siteId);

  /// Clears the sync-pending flag for [siteId]'s Client inputs. Call once
  /// that row's push to Supabase has succeeded.
  Future<void> markClientInputsSynced(String siteId);

  /// [siteId]'s active (not pending-delete) blocks, ordered by position.
  /// [dirtyOnly] limits to blocks not yet pushed since their last local
  /// change — sync-only, see [markBlockSynced].
  Future<List<Block>> getBlocks(String siteId, {bool dirtyOnly = false});

  /// Clears the sync-pending flag for block [id]. Call once that row's push
  /// to Supabase has succeeded.
  Future<void> markBlockSynced(String id);

  /// Every block id currently pending deletion for [siteId] — sync-only,
  /// see [SqfliteSurveyRepository._applyBlockDiff] (the tombstone side of
  /// [updateSiteBlocks]) and [hardDeleteBlock].
  Future<List<String>> getPendingDeleteBlockIds(String siteId);

  /// Removes a tombstoned block row for real, once sync has confirmed its
  /// remote delete succeeded. Sync-only — never called from the UI, which
  /// already treats a pending-delete block as gone (see [updateSiteBlocks]).
  Future<void> hardDeleteBlock(String id);

  /// Marks a site permanently unpushable by the signed-in account — called
  /// when its push is refused with a Postgres 42501 (RLS authorization),
  /// which byte-identical retries can never overcome. The row keeps
  /// `dirty = 1` so the local edit is preserved, but leaves the push queue
  /// so it stops being retried (and re-failing) on every sync. Cleared
  /// automatically if a pull later brings down the authoritative remote
  /// version — see [upsertSitesFromRemote].
  Future<void> markSiteSyncBlocked(String id);

  /// Same as [markSiteSyncBlocked], for a block row.
  Future<void> markBlockSyncBlocked(String id);

  /// How many rows are currently sync-blocked across every table that
  /// tracks it (sites + blocks today). Surfaced by the sync UI as "N rows
  /// can't sync — needs attention", instead of silently retrying forever.
  Future<int> countSyncBlocked();

  /// Merges Supabase's sites rows into local storage — new rows inserted,
  /// existing ones updated (never replaced wholesale: a column the remote
  /// payload doesn't carry, e.g. address/client_name/client_contact, is left
  /// exactly as it was), unless that local row has an unsynced edit of its
  /// own. Does NOT reconcile deletes by absence — a site is never actually
  /// deleted (see [Site.archived], now a real synced column as of Full sync
  /// Group 1), so there's nothing here for absence to mean in the first
  /// place. [remoteRows] should still be a complete fetch of the whole table
  /// (see [SupabaseSurveyDataSource.fetchSites]'s pagination). Blocks and
  /// Client inputs are separate tables/pulls (see [upsertBlocksFromRemote],
  /// [upsertClientInputsFromRemote]), not touched here.
  Future<void> upsertSitesFromRemote(List<Map<String, dynamic>> remoteRows);

  /// Same merge rule as [upsertSitesFromRemote], for blocks — keyed by their
  /// own stable id (not site_id) since Full sync Group 1's blocks-push
  /// rework gave every block one, same as source_points/inlet_points/etc.
  /// Additionally: a remote row carrying a non-null `deleted_at` (blocks'
  /// explicit delete tombstone) is hard-deleted locally instead of
  /// upserted, unless the local row has an unsynced edit of its own — never
  /// inferred from a row's absence, an explicit marker on the row itself.
  Future<void> upsertBlocksFromRemote(List<Map<String, dynamic>> remoteRows);

  /// Same merge rule as [upsertSitesFromRemote], for Client inputs — keyed by
  /// site_id (not its own id), one row per site.
  Future<void> upsertClientInputsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

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

  /// Same merge rule as [upsertSitesFromRemote], for source points across
  /// every site — not scoped to one, so a complete fetch is required (see
  /// [SupabaseSurveyDataSource.fetchSourcePoints]).
  Future<void> upsertSourcePointsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

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

  /// Same merge rule as [upsertSitesFromRemote], for inlet points across
  /// every site.
  Future<void> upsertInletPointsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  // ---- Duct LoRa units (a site has many) ----------------------------------

  /// [dirtyOnly] limits to units not yet pushed since their last local
  /// change — sync-only, see [markDuctLoraSynced]. Never includes a unit
  /// pending deletion (see [deleteDuctLora]) — deletion is immediate from
  /// every normal read's point of view.
  Future<List<DuctLora>> getDuctLoras(String siteId, {bool dirtyOnly = false});

  /// Persists a new Duct LoRa unit, assigning it an id, and returns it.
  Future<DuctLora> addDuctLora(DuctLora ductLora);

  Future<void> updateDuctLora(DuctLora ductLora);

  /// Marks [id] for deletion (a tombstone, not a hard delete) so sync can
  /// still push a remote delete for it — the row disappears from every
  /// normal read immediately, but survives in storage until
  /// [hardDeleteDuctLora] is called once that remote delete succeeds.
  Future<void> deleteDuctLora(String id);

  /// Every Duct LoRa unit id currently pending deletion for [siteId] —
  /// sync-only, see [deleteDuctLora] / [hardDeleteDuctLora].
  Future<List<String>> getPendingDeleteDuctLoraIds(String siteId);

  /// Physically removes a pending-delete row. Call only after that id's
  /// remote delete has actually succeeded — see [getPendingDeleteDuctLoraIds].
  Future<void> hardDeleteDuctLora(String id);

  /// Clears the sync-pending flag for Duct LoRa unit [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markDuctLoraSynced(String id);

  /// Same merge rule as [upsertSitesFromRemote], for Duct LoRa units across
  /// every site.
  Future<void> upsertDuctLorasFromRemote(List<Map<String, dynamic>> remoteRows);

  // ---- Gateways (a site has many) -----------------------------------------

  /// [dirtyOnly] limits to gateways not yet pushed since their last local
  /// change — sync-only, see [markGatewaySynced]. Never includes a gateway
  /// pending deletion (see [deleteGateway]) — deletion is immediate from
  /// every normal read's point of view.
  Future<List<Gateway>> getGateways(String siteId, {bool dirtyOnly = false});

  /// Persists a new gateway, assigning it an id, and returns it.
  Future<Gateway> addGateway(Gateway gateway);

  Future<void> updateGateway(Gateway gateway);

  /// Marks [id] for deletion (a tombstone, not a hard delete) so sync can
  /// still push a remote delete for it — the row disappears from every
  /// normal read immediately, but survives in storage until
  /// [hardDeleteGateway] is called once that remote delete succeeds.
  Future<void> deleteGateway(String id);

  /// Every gateway id currently pending deletion for [siteId] — sync-only,
  /// see [deleteGateway] / [hardDeleteGateway].
  Future<List<String>> getPendingDeleteGatewayIds(String siteId);

  /// Physically removes a pending-delete row. Call only after that id's
  /// remote delete has actually succeeded — see [getPendingDeleteGatewayIds].
  Future<void> hardDeleteGateway(String id);

  /// Clears the sync-pending flag for gateway [id]. Call once that row's push
  /// to Supabase has succeeded.
  Future<void> markGatewaySynced(String id);

  /// Same merge rule as [upsertSitesFromRemote], for gateways across every
  /// site.
  Future<void> upsertGatewaysFromRemote(List<Map<String, dynamic>> remoteRows);

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

  /// Same merge rule as [upsertSitesFromRemote], for Footers — keyed by
  /// site_id (not its own id), one row per site.
  Future<void> upsertFootersFromRemote(List<Map<String, dynamic>> remoteRows);

  // ---- Material Master (admin-editable reference data, not site-scoped) ---
  //
  // Every create/edit/delete writes to the change log (material_master_audit)
  // as part of the same call — [changedByRole] is a display-name snapshot
  // (the signed-in user's real name, Slice 1d; a bare role label like
  // "Admin" on rows written before it) and [changedByUserId] is the real
  // account id, recorded against each audit entry.

  /// [dirtyOnly] limits to rows not yet pushed since their last local
  /// change — sync-only, see [markMaterialMasterItemSynced]. Never includes
  /// a row pending deletion (see [deleteMaterialMasterItem]) — deletion is
  /// its own sync path, [getPendingDeleteMaterialMasterItemIds] /
  /// [hardDeleteMaterialMasterItem].
  Future<List<MaterialMasterItem>> getMaterialMasterItems({bool dirtyOnly = false});

  /// Persists a new Material Master row, assigning it an id, and returns it.
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
    String? changedByUserId,
  });

  /// Updates an existing row and logs one change-log entry per field that
  /// actually changed (diffed against the row currently stored under
  /// [item.id]).
  Future<void> updateMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
    String? changedByUserId,
  });

  /// Marks [id] for deletion (a tombstone, not a hard delete) and logs a
  /// single change-log entry summarizing what was removed — same convention
  /// as [deleteSourcePoint]/[deleteInletPoint]. The row disappears from
  /// every normal read immediately, but survives in storage until
  /// [hardDeleteMaterialMasterItem] is called once that remote delete
  /// succeeds, so a delete that fails partway (offline, etc.) is retried on
  /// the next sync exactly like any other unsynced change.
  Future<void> deleteMaterialMasterItem(
    String id, {
    required String changedByRole,
    String? changedByUserId,
  });

  /// Every Material Master row id currently pending deletion — sync-only,
  /// see [deleteMaterialMasterItem] / [hardDeleteMaterialMasterItem]. Not
  /// site-scoped, unlike the source/inlet point equivalents.
  Future<List<String>> getPendingDeleteMaterialMasterItemIds();

  /// Physically removes a pending-delete row. Call only after that id's
  /// remote delete has actually succeeded — see
  /// [getPendingDeleteMaterialMasterItemIds].
  Future<void> hardDeleteMaterialMasterItem(String id);

  /// Clears the sync-pending flag for Material Master row [id]. Call once
  /// that row's push to Supabase has succeeded.
  Future<void> markMaterialMasterItemSynced(String id);

  /// Merges Supabase's material_master_items rows into local storage, keyed
  /// by id: inserts anything new, and overwrites anything existing — unless
  /// that local row has an unsynced edit or pending delete of its own, in
  /// which case it's left untouched so a pull never clobbers an admin's
  /// in-flight change before it's had a chance to push. Merged rows are
  /// never marked dirty themselves — they came from Supabase, the table's
  /// source of truth, so they're already in sync.
  ///
  /// Also reconciles the other direction: a local row that's active (not
  /// dirty, not already pending its own local delete) but absent from
  /// [remoteItems] was deleted directly in Supabase, so it's hard-deleted
  /// here too — unless [remoteItems] is empty, in which case reconciliation
  /// is skipped entirely (an empty result is far more likely to mean "the
  /// fetch went wrong somehow" than "every row was really just deleted";
  /// treating it as the latter would wipe the whole local catalog on a
  /// fluke). [remoteItems] must always be a complete, successful fetch of
  /// the whole table (see [SupabaseSurveyDataSource.fetchMaterialMasterItems]'s
  /// pagination) — a partial or failed fetch must never reach this method at
  /// all, since a truncated list would otherwise look identical to a mass
  /// deletion.
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

  /// Same merge rule as [upsertSitesFromRemote], for photos — including the
  /// explicit `deleted_at` tombstone path, which is how the photo cascade
  /// written by Groups 2 and 3 finally reaches other devices.
  ///
  /// Returns the local file paths of any photos this pull removed, so the
  /// caller can delete those files too rather than leaving dead image bytes
  /// on the device forever.
  Future<List<String>> upsertPhotosFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  /// Photos the user removed that still need their delete pushed —
  /// tombstoned locally (see [setPhotos]) and physically present until the
  /// remote `deleted_at` write is confirmed, so a failed or offline sync
  /// retries instead of silently losing the deletion.
  ///
  /// Returns whole photos rather than ids so the caller also has
  /// `localPath`: the image file has to go with the row, and once
  /// [hardDeletePhoto] runs that path is unrecoverable.
  Future<List<SurveyPhoto>> getPendingDeletePhotos();

  /// Removes a tombstoned photo row for real. Call only once its remote
  /// delete has succeeded — the mirror of [hardDeleteBlock].
  Future<void> hardDeletePhoto(String id);

  /// Records where a pulled photo's downloaded file landed on this device.
  ///
  /// Distinct from [updatePhoto], which treats the write as a user edit and
  /// re-queues the row for push. This only fills in device-local state, so
  /// it must leave the row's sync status exactly as it found it.
  Future<void> setPhotoLocalPath(String id, String localPath);

  /// Photos whose bytes this device doesn't have: `remote_path` set (so the
  /// file exists in Storage) but no `local_path`. That's every photo pulled
  /// from another device — the metadata arrives first, the file follows.
  /// Excludes the opposite case (captured here, not yet uploaded).
  Future<List<SurveyPhoto>> getPhotosMissingLocalFile();

  // ---- BoM manual entries (D/E/G "Add materials" picker) -------------------
  //
  // Never read by BomEngine — these feed into a snapshot only at the moment
  // [finalizeBom] runs. Reachable from the BoM preview screen for any survey
  // regardless of status, and still editable after that survey's BoM has been
  // finalized — doing so has no effect on the frozen snapshot (see
  // [finalizeBom]).

  /// All manual entries for one survey, oldest first. [dirtyOnly] limits to
  /// entries not yet pushed since their last local change — sync-only, see
  /// [markBomManualEntrySynced]. Never includes an entry pending deletion
  /// (see [deleteBomManualEntry]) — deletion is immediate from every normal
  /// read's point of view.
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

  /// Marks [id] for deletion (a tombstone, not a hard delete) so sync can
  /// still push a remote delete for it — the row disappears from every
  /// normal read immediately, but survives in storage until
  /// [hardDeleteBomManualEntry] is called once that remote delete succeeds.
  Future<void> deleteBomManualEntry(String id);

  /// Every manual entry id currently pending deletion for [surveyId] —
  /// sync-only, see [deleteBomManualEntry] / [hardDeleteBomManualEntry].
  Future<List<String>> getPendingDeleteBomManualEntryIds(String surveyId);

  /// Physically removes a pending-delete row. Call only after that id's
  /// remote delete has actually succeeded — see
  /// [getPendingDeleteBomManualEntryIds].
  Future<void> hardDeleteBomManualEntry(String id);

  /// Clears the sync-pending flag for manual entry [id]. Call once that
  /// row's push to Supabase has succeeded.
  Future<void> markBomManualEntrySynced(String id);

  /// Same merge rule as [upsertSitesFromRemote], for BoM manual entries
  /// across every survey.
  Future<void> upsertBomManualEntriesFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  // ---- Immutable BoM history pulls (Full sync Group 3) ---------------------
  //
  // These six tables were push-only until this slice, which meant a survey's
  // finalized BoM and its entire revision history existed only on the device
  // that created them — invisible to every other device and lost on
  // reinstall. Each is a plain upsert-by-id merge: they're immutable by
  // design (no delete path anywhere in the app), so unlike
  // [upsertBomManualEntriesFromRemote] there's no tombstone to check, and
  // unlike [upsertSitesFromRemote] no absence-based reconcile either.
  //
  // Callers must pull each parent before its lines — local storage enforces
  // the foreign key.

  Future<void> upsertBomSnapshotsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  Future<void> upsertBomSnapshotLinesFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  Future<void> upsertBomRevisionsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  Future<void> upsertBomRevisionLinesFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  Future<void> upsertBomManualEditSnapshotsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

  Future<void> upsertBomManualEditSnapshotLinesFromRemote(
    List<Map<String, dynamic>> remoteRows,
  );

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
    String? finalizedByUserId,
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
    String? createdByUserId,
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

  // ---- Survey reassignment ---------------------------------------------
  //
  // The engineer roster itself now comes from real accounts (see
  // SyncService.fetchEngineerRoster, which queries `profiles` directly —
  // there's no local, offline-capable roster table anymore; picking an
  // engineer to assign/reassign to needs a network connection, same
  // trade-off already accepted for sign-in itself). Each change writes one
  // audit row recording who it moved from/to, by both real account id and
  // display-name snapshot.
  //
  // Reassignment is deliberately NOT restricted by survey status. It used to
  // throw unless the survey was still 'assigned', which read to users as an
  // arbitrary "you can only reassign 2-3 times" limit: the button simply
  // vanished the moment the engineer opened the survey (status -> in
  // progress). Handing a survey over mid-work is a real operational need
  // (an engineer falls sick, leaves, or is reassigned to another site), so
  // the rule now lives entirely in the UI's warning, not in a hard block.
  //
  // The trade-off this accepts is a genuine one, and the UI warns about it
  // (see SiteHubScreen._confirmReassignInProgress): work the OUTGOING
  // engineer has not yet synced can no longer be pushed once the handover
  // lands, because every survey table's RLS is scoped by can_access_site()
  // — their push is rejected (42501), the row goes sync_blocked, and the
  // next pull reconciles it away. Nothing app-side can force another
  // device to push first, so this is surfaced as an informed choice rather
  // than prevented.

  /// Reassigns [siteId] to [newAssigneeUserId] (a real `profiles.id`, with
  /// [newAssignee] as its display-name snapshot) and writes one audit entry.
  /// Allowed in any status. Throws [StateError] only if the site doesn't
  /// exist.
  Future<void> reassignSurvey({
    required String siteId,
    required String newAssigneeUserId,
    required String newAssignee,
    required String changedByRole,
    String? changedByUserId,
  });

  /// One survey's reassignment history, newest first.
  Future<List<SurveyAssignmentAuditEntry>> getSurveyAssignmentAuditLog(
    String siteId,
  );
}
