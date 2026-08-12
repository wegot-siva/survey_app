import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

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
import '../models/engineer.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_audit_entry.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';

/// Whether a delete that PostgREST answered with zero affected rows was
/// refused by row-level security (true) or simply had nothing to delete
/// (false).
///
/// Separated from the request code so the rule can be tested directly: it is
/// a three-input decision whose two branches are INVERTED, which is exactly
/// the kind of thing that reads as correct and behaves as backwards.
///
/// Zero rows is ambiguous — the row may never have reached Supabase, or RLS
/// may have refused the write — and the cases need opposite handling, so the
/// probe differs by how the table's SELECT policy is scoped:
///
///   * [siteScoped] tables (every survey table): policies resolve through
///     `can_access_site(site_id)`, so the probe asks whether the row's SITE
///     is still visible. Visible means we were entitled to write it, so zero
///     rows means the row genuinely is not there — an engineer adding a
///     point and removing it again before the first sync, which is ordinary
///     and must succeed. NOT visible means access was lost and the write was
///     refused.
///
///   * global tables (material_master_items): SELECT is universal — every
///     role reads the whole active catalog — so the row itself is the probe,
///     and the sense flips. Still visible means it exists and our delete was
///     refused; absent means it was already gone.
bool deleteWasRefused({
  required int rowsAffected,
  required bool probeFound,
  required bool siteScoped,
}) {
  if (rowsAffected > 0) return false;
  return siteScoped ? !probeFound : probeFound;
}

/// Thrown when a delete/tombstone push provably did NOT reach Supabase
/// because row-level security refused it.
///
/// Exists because PostgREST reports an RLS-refused UPDATE or DELETE as
/// **200 with zero rows**, not as an error — indistinguishable from a
/// successful write unless the affected rows are counted. Treating that as
/// success is what let [SyncService.pushAll] hard-delete a local tombstone
/// whose remote row was still live, so the next pull reinserted the row and
/// the user's deletion silently undid itself.
///
/// Deliberately a distinct type rather than a bare [StateError]: pushAll's
/// per-row isolation catches it, records the row as a retryable failure and
/// leaves the local tombstone in place, so the delete is attempted again on
/// the next sync instead of being lost.
class DeleteRefusedException implements Exception {
  DeleteRefusedException(this.table, this.id, {this.siteId});

  final String table;
  final String id;
  final String? siteId;

  @override
  String toString() =>
      'DeleteRefusedException: the delete of $table/$id was refused by '
      'row-level security (0 rows affected)'
      '${siteId == null ? '' : ' — site $siteId is no longer accessible to '
          'this account'}. The local tombstone was kept for retry.';
}

/// Remote (Supabase) reads/writes for survey data.
///
/// Push-only tables (bom_snapshots/bom_revisions and their line tables,
/// survey_assignment_audit): reachable only from the device that authored
/// them, deliberately deferred — see [SyncService] for why. Every other
/// table also has a pull (`fetchX`) — sites, blocks, client_inputs, footers,
/// source_points, inlet_points, duct_loras, gateways, bom_manual_entries,
/// plus Material Master (global reference data, pulled since the earliest
/// slice). A pulled row reaches every device, not just the one that entered
/// it, and a row deleted directly in Supabase is reconciled away locally too
/// — see [SqfliteSurveyRepository]'s pull-reconcile helper. (Full sync Group
/// 1: blocks joins this list without a tombstone — see [fetchBlocks].)
///
/// Upserts are idempotent — keyed by the same UUIDs used locally — so repeating
/// a sync converges to the same rows instead of duplicating them.
class SupabaseSurveyDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// Pushes one site's row (name/status/assignment/bom_locked/archived
  /// only). Blocks and Client inputs are pushed separately — see
  /// [pushBlock]/[deleteBlock] and [pushClientInputs] — each dirty-tracked
  /// independently of the site row (and, since Full sync Group 1's
  /// blocks-push rework, independently of each other too) so editing one
  /// never forces a redundant push of another.
  ///
  /// UPDATE-if-exists / INSERT-only-if-new, deliberately NOT `.upsert()`.
  /// PostgREST issues upsert as `INSERT ... ON CONFLICT DO UPDATE`, and
  /// Postgres evaluates the INSERT policy's WITH CHECK even when the row
  /// already exists and the operation resolves to an update. sites' INSERT
  /// policy is `is_site_manager()` (Slice 2c) — so an Engineer upserting a
  /// site they already own (e.g. pushing their own status -> in_progress on
  /// an assigned site) got a 42501 RLS violation on the INSERT check, even
  /// though the sites UPDATE policy explicitly permits that exact update and
  /// a plain UPDATE succeeds (verified: upsert 403 vs PATCH 204). That broke
  /// every Engineer site-status push and was masked for a long time by the
  /// sync's false-success reporting. Doing an explicit UPDATE first, then an
  /// INSERT only when the update matched no existing row, routes each role
  /// through the policy that actually applies to it: an Engineer updating
  /// their own site hits only the UPDATE policy (passes); a manager creating
  /// a new site falls through to INSERT (passes is_site_manager); an
  /// Engineer attempting to create a genuinely new site still correctly
  /// fails the INSERT check, since only a manager may create a site.
  Future<void> pushSite(Site site) async {
    final row = {
      'id': site.id,
      'name': site.name,
      'status': site.status,
      'assigned_to': site.assignedTo,
      'assigned_to_user_id': site.assignedToUserId,
      'bom_locked': site.bomLocked,
      'archived': site.archived,
    };
    final updated = await _client
        .from('sites')
        .update(row)
        .eq('id', site.id)
        .select('id');
    if (updated.isEmpty) {
      // No existing row matched — this is a genuinely new site. INSERT is
      // gated to site managers by RLS; an Engineer reaching here (e.g. a
      // site stranded in their local db that was never created remotely)
      // will correctly get a 42501, surfaced as a skipped row.
      await _client.from('sites').insert(row);
    }
  }

  /// Upserts a block by its own stable id (idempotent). The parent site
  /// must already have been pushed (FK). Per-row, not a whole-site replace
  /// — see [SqfliteSurveyRepository.updateSiteBlocks] / block_diff.dart for
  /// why the old delete-all-and-reinsert approach could resurrect a block
  /// another device had already deleted.
  Future<void> pushBlock(Block block) async {
    await _client.from('blocks').upsert({
      'id': block.id,
      'site_id': block.siteId,
      'position': block.position,
      'label': block.label,
    });
  }

  /// Marks a block deleted by id — an explicit `deleted_at` tombstone
  /// (`UPDATE`), not a real `DELETE`. blocks' RLS no longer grants DELETE
  /// at all (see schema.sql's "Blocks explicit delete tombstone" section) —
  /// a real row delete would be invisible to pull reconciliation (which
  /// only ever sees rows a fetch actually returns), silently breaking
  /// propagation to other devices exactly the way absence-based deletion
  /// already proved unsafe. Idempotent: re-tombstoning an already-deleted
  /// row, or one that was somehow never pushed, is a harmless no-op update.
  Future<void> deleteBlock(String id, {required String siteId}) =>
      _tombstone('blocks', id, siteId: siteId);

  /// Upserts the Client inputs form for [siteId] (idempotent). The parent
  /// site must already have been pushed (FK).
  Future<void> pushClientInputs(String siteId, ClientInputs inputs) async {
    await _client
        .from('client_inputs')
        .upsert(_inputsToRemoteRow(siteId, inputs));
  }

  /// Upserts a source point by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushSourcePoint(SourcePoint sp) async {
    await _client.from('source_points').upsert(_sourcePointToRemoteRow(sp));
  }

  /// Marks a source point deleted by id — an explicit `deleted_at`
  /// tombstone (`UPDATE`), not a real `DELETE`, for exactly the reason
  /// given on [deleteBlock]: a hard-deleted row is invisible to pull
  /// reconciliation, so the delete would propagate upward and stop there
  /// while every other device kept the row forever. Cascades to the photos
  /// it owns — see [_tombstoneWithPhotos].
  Future<void> deleteSourcePoint(String id, {required String siteId}) =>
      _tombstoneWithPhotos('source_points', id, PhotoOwner.sourcePoint,
          siteId: siteId);

  /// Upserts an inlet point by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushInletPoint(InletPoint ip) async {
    await _client.from('inlet_points').upsert(_inletPointToRemoteRow(ip));
  }

  /// Marks an inlet point deleted by id — a `deleted_at` tombstone, not a
  /// real `DELETE`. See [deleteSourcePoint].
  Future<void> deleteInletPoint(String id, {required String siteId}) =>
      _tombstoneWithPhotos('inlet_points', id, PhotoOwner.inletPoint,
          siteId: siteId);

  /// Upserts a Duct LoRa unit by its id (idempotent). Parent site must exist.
  Future<void> pushDuctLora(DuctLora d) async {
    await _client.from('duct_loras').upsert(_ductLoraToRemoteRow(d));
  }

  /// Marks a Duct LoRa unit deleted by id — a `deleted_at` tombstone, not a
  /// real `DELETE`. See [deleteSourcePoint].
  Future<void> deleteDuctLora(String id, {required String siteId}) =>
      _tombstoneWithPhotos('duct_loras', id, PhotoOwner.ductLora,
          siteId: siteId);

  /// Upserts a gateway by its id (idempotent). Parent site must exist.
  Future<void> pushGateway(Gateway g) async {
    await _client.from('gateways').upsert(_gatewayToRemoteRow(g));
  }

  /// Marks a gateway deleted by id — a `deleted_at` tombstone, not a real
  /// `DELETE`. See [deleteSourcePoint].
  Future<void> deleteGateway(String id, {required String siteId}) =>
      _tombstoneWithPhotos('gateways', id, PhotoOwner.gateway,
          siteId: siteId);

  /// Tombstones row [id] of [table], then every photos row it owns via the
  /// polymorphic ([ownerType], [ownerId]) link — one shared timestamp, so a
  /// parent and its photos always carry the same deletion time.
  ///
  /// Order matters on failure, not on success: if the photos half throws,
  /// the caller's whole push action throws with it, so the local row stays
  /// `pending_delete` and the next sync retries both halves (both are
  /// idempotent `UPDATE`s). Tombstoning the parent first means that window
  /// leaves a deleted parent with live photos — today's exact status quo,
  /// and invisible until photos' own pull lands in Group 4 — rather than
  /// photos disappearing out from under a row still shown as present.
  ///
  /// The local side already hard-deletes those photos on-device when the
  /// parent is deleted (see SqfliteSurveyRepository.deleteSourcePoint);
  /// this is what finally makes the remote match, closing a pre-existing
  /// orphan gap. Idempotent: re-tombstoning an already-deleted row, or one
  /// never pushed in the first place, is a harmless no-op update.
  Future<void> _tombstoneWithPhotos(
    String table,
    String id,
    String ownerType, {
    required String siteId,
  }) async {
    final deletedAt = DateTime.now().toUtc().toIso8601String();
    // Owner first, and it must be proven to have applied — see [_tombstone].
    await _tombstone(table, id, siteId: siteId, deletedAt: deletedAt);
    // The photo cascade is deliberately NOT row-count-checked: an owner with
    // no photos legitimately affects zero rows, and the owner's tombstone
    // above already proved this account is entitled to write this site.
    await _client
        .from('photos')
        .update({'deleted_at': deletedAt})
        .eq('owner_type', ownerType)
        .eq('owner_id', id);
  }

  /// Tombstones row [id] of [table] — the no-photos half of
  /// [_tombstoneWithPhotos], for a table that owns no photos at all.
  /// Writes a `deleted_at` tombstone and PROVES it landed.
  ///
  /// The `.select()` makes this a `return=representation` request, so the
  /// affected rows come back and can be counted. That check is the entire
  /// point: PostgREST answers an UPDATE that RLS refused with **200 and zero
  /// rows**, not an error. Without counting, a refused delete looked
  /// identical to a successful one — [SyncService.pushAll] then hard-deleted
  /// the local tombstone, destroying the only record that a delete was ever
  /// wanted, while the remote row stayed live and the next pull reinserted
  /// it. Verified against this project's Supabase: tombstoning a row on a
  /// site the account cannot access returns `status=200, rows=0` and leaves
  /// `deleted_at` null.
  ///
  /// Zero rows is genuinely ambiguous, and the two cases need opposite
  /// handling, which is why [_assertRowIsAbsentNotRefused] exists rather
  /// than a blanket throw:
  ///   * the row never reached Supabase at all — an engineer adding a point
  ///     and removing it again before the first sync, which is ordinary and
  ///     must succeed, or the local tombstone would retry forever and report
  ///     a permanent sync failure over a row nobody can see;
  ///   * RLS refused the write — the bug above, which must fail loudly.
  Future<void> _tombstone(
    String table,
    String id, {
    required String? siteId,
    String? deletedAt,
  }) async {
    final applied = await _client
        .from(table)
        .update({
          'deleted_at': deletedAt ?? DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select('id');
    if (applied.isNotEmpty) return;
    await _assertRowIsAbsentNotRefused(table, id, siteId);
  }

  /// Decides whether a zero-row delete meant "already gone" or "refused",
  /// and throws [DeleteRefusedException] for the latter.
  ///
  /// The discriminator is the SELECT policy that governs the table, because
  /// RLS here is site-scoped: every child table's policies resolve through
  /// `can_access_site(site_id)`, so losing access to a row means losing
  /// access to its site. Asking whether the SITE is still visible therefore
  /// answers whether we were entitled to write the row — measured on live
  /// Supabase: an engineer sees 1 row for a site they hold and 0 for one
  /// reassigned away.
  ///
  /// material_master_items has no site and its SELECT policy is universal
  /// (every role reads the whole active catalog), so there the row itself is
  /// the discriminator: still visible means the write was refused, absent
  /// means it was already gone.
  Future<void> _assertRowIsAbsentNotRefused(
    String table,
    String id,
    String? siteId,
  ) async {
    final siteScoped = siteId != null;
    final probeFound = siteScoped
        ? (await _client.from('sites').select('id').eq('id', siteId)).isNotEmpty
        : (await _client.from(table).select('id').eq('id', id)).isNotEmpty;
    if (deleteWasRefused(
      rowsAffected: 0,
      probeFound: probeFound,
      siteScoped: siteScoped,
    )) {
      throw DeleteRefusedException(table, id, siteId: siteId);
    }
  }

  /// Upserts the per-site footer (idempotent, keyed by site_id). Parent site
  /// must exist.
  Future<void> pushFooter(String siteId, Footer f) async {
    await _client.from('footers').upsert(_footerToRemoteRow(siteId, f));
  }

  /// Upserts a Material Master row by its id (idempotent). Not site-scoped —
  /// no parent to push first.
  Future<void> pushMaterialMasterItem(MaterialMasterItem item) async {
    await _client
        .from('material_master_items')
        .upsert(_materialMasterItemToRemoteRow(item));
  }

  /// Deletes a Material Master row by id (idempotent — a no-op if it was
  /// never pushed, or already deleted remotely). Only called once
  /// [SurveyRepository.getPendingDeleteMaterialMasterItemIds] confirms the
  /// row is tombstoned locally.
  Future<void> deleteMaterialMasterItem(String id) async {
    // A real DELETE (this table alone grants it), but verified the same way
    // as every tombstone: PostgREST reports an RLS-refused DELETE as 200
    // with zero rows, so an unverified call let a refused delete look like a
    // successful one. siteId is null because the catalog is global — see
    // _assertRowIsAbsentNotRefused for the discriminator that applies here.
    final deleted =
        await _client.from('material_master_items').delete().eq('id', id).select('id');
    if (deleted.isNotEmpty) return;
    await _assertRowIsAbsentNotRefused('material_master_items', id, null);
  }

  /// Fetches every Material Master row from Supabase — the pull half of
  /// Material Master's sync (see the class doc comment for why this table
  /// alone needs one). The caller merges these into local storage (including
  /// reconciling deletes — a row missing from this result is treated as
  /// deleted remotely), so this MUST return the complete table, never a
  /// partial page.
  ///
  /// Paginates explicitly via `.range()` rather than trusting a single
  /// `.select()` to return everything — PostgREST caps an unbounded request
  /// at a server-configured max-rows (commonly 1000), and the plumbing
  /// catalog import alone is expected to add ~1000 rows on top of what's
  /// already here. See [_fetchAllRows] for how the page count is established
  /// up front from `count=exact`, and why a short page is never treated as
  /// the end of the table.
  Future<List<MaterialMasterItem>> fetchMaterialMasterItems() async {
    return (await _fetchAllRows(
      'material_master_items',
    )).map((r) => _materialMasterItemFromRemoteRow(r)).toList();
  }

  /// How many pages of one table may be in flight at once, once a table is
  /// big enough to need more than one.
  ///
  /// Deliberately small, because this multiplies with the caller's own
  /// concurrency: SyncService fetches up to 6 tables at a time, so the
  /// worst case here is 6 x 4 = 24 simultaneous requests. Measured against
  /// this project's Supabase, latency stayed flat up to 24 concurrent reads,
  /// so that is the ceiling this was sized against rather than a guess.
  ///
  /// At present data volumes every table fits in a single page, so this path
  /// does not execute at all — it exists for the hundreds-of-sites case.
  static const int _pageConcurrency = 4;

  /// Fetches every row of [table] — see [fetchMaterialMasterItems] for why
  /// the caller (here, [SurveyRepository]'s `upsertXFromRemote` methods) must
  /// always receive the complete table, never a partial page, before
  /// reconciling local deletes against it. Shared by every "Phase 1" pull,
  /// returning raw rows rather than a typed model, since
  /// [SqfliteSurveyRepository]'s pull-reconcile helper only ever needs to
  /// write these columns straight into the matching local table (see its own
  /// doc for the one real conversion needed: Postgres booleans -> SQLite
  /// 0/1).
  ///
  /// The first request carries `count=exact`, which PostgREST answers with
  /// the total row count of the whole table — it "respects filters but
  /// ignores modifiers", so a ranged request still reports the full total,
  /// not the size of the page it returned. Knowing the total up front is
  /// what removes the wasted request this used to end on: the old loop could
  /// only recognise the end of a table by asking for one more page and
  /// getting nothing back, so EVERY table cost one entirely empty
  /// round-trip. With 17 tables pulled per sync that was 17 requests
  /// returning zero rows — measured at ~4.8s of a ~9.6s pull.
  ///
  /// Deliberately NOT `page.length < pageSize` as the stop condition, which
  /// would be the obvious way to drop that request without a count: PostgREST
  /// caps an unbounded request at a server-configured max-rows, so a short
  /// page can mean "the server capped you", not "the table ended" — and
  /// treating a capped page as the end would silently hand the caller a
  /// partial table, which for sites and blocks (the two pulls that reconcile
  /// deletes by absence) means deleting every local row that didn't fit in
  /// page one. For the same reason the page size used to walk the rest of the
  /// table is the length actually returned, not the length requested.
  ///
  /// [orderBy] must be a column that exists on [table] and is unique — the
  /// pages are separate requests, and without a deterministic sort Postgres
  /// is free to return rows in a different order each time, which lets a row
  /// appear on two pages or on neither. Defaults to `id`; the two tables
  /// keyed on the site instead (client_inputs, footers) have no `id` column
  /// at all and pass `site_id`.
  Future<List<Map<String, dynamic>>> _fetchAllRows(
    String table, {
    String orderBy = 'id',
  }) async {
    const pageSize = 500;

    final first = await _client
        .from(table)
        .select()
        .order(orderBy, ascending: true)
        .range(0, pageSize - 1)
        .count(CountOption.exact);

    return paginateRemainingPages(
      total: first.count,
      firstPage: [for (final r in first.data) Map<String, dynamic>.from(r)],
      pageConcurrency: _pageConcurrency,
      fetchPage: (offset, limit) async => (await _client
              .from(table)
              .select()
              .order(orderBy, ascending: true)
              .range(offset, offset + limit - 1))
          .map((r) => Map<String, dynamic>.from(r))
          .toList(),
    );
  }

  /// Every site row (id/name/status/assigned_to/assigned_to_user_id/
  /// bom_locked/archived — blocks and client_inputs are separate
  /// tables/pulls; address/client_name/client_contact are Sales-only fields
  /// never pushed to Supabase at all, so they're simply absent from every
  /// remote row — see [SqfliteSurveyRepository]'s pull-reconcile helper for
  /// why that's safe).
  Future<List<Map<String, dynamic>>> fetchSites() => _fetchAllRows('sites');

  /// Every block row across every site this account can see (RLS scopes it
  /// exactly like [fetchSites] — can_access_site(site_id)). Since Full sync
  /// Group 1's blocks-push rework gave every block a stable id, the caller
  /// reconciles these the same per-row way as source_points/inlet_points/
  /// etc. (see SqfliteSurveyRepository.upsertBlocksFromRemote), not a
  /// group-and-replace.
  Future<List<Map<String, dynamic>>> fetchBlocks() => _fetchAllRows('blocks');

  /// The current engineer roster — real accounts (`profiles` rows with
  /// `role = 'engineer'`), not the retired local `engineers` table/hardcoded
  /// roster it used to seed from (removed entirely as of Full sync Group 1).
  /// Deliberately a live query, not a locally-cached pull like every other
  /// `fetchX` here: the roster is small and only needed at the moment
  /// someone is assigning/reassigning a survey, so a network round-trip
  /// there (same trade-off already accepted for sign-in itself) beats
  /// standing up a new sync-scoped table for it.
  Future<List<Engineer>> fetchEngineerRoster() async {
    final rows = await _client
        .from('profiles')
        .select('id, full_name')
        .eq('role', 'engineer')
        .eq('active', true)
        .order('full_name');
    return rows
        .map((r) => Engineer(id: r['id'] as String, name: r['full_name'] as String))
        .toList(growable: false);
  }

  /// Every Client inputs row, keyed by site_id (not its own id).
  /// Ordered by site_id: client_inputs is keyed on the site (one row per
  /// site) and has no `id` column, so _fetchAllRows' default sort would be a
  /// 400 the moment this table ever needed a second page.
  Future<List<Map<String, dynamic>>> fetchClientInputs() =>
      _fetchAllRows('client_inputs', orderBy: 'site_id');

  /// Every Footer row, keyed by site_id (not its own id).
  /// Ordered by site_id for the same reason as [fetchClientInputs] — footers
  /// is keyed on the site and has no `id` column.
  Future<List<Map<String, dynamic>>> fetchFooters() =>
      _fetchAllRows('footers', orderBy: 'site_id');

  Future<List<Map<String, dynamic>>> fetchSourcePoints() =>
      _fetchAllRows('source_points');

  Future<List<Map<String, dynamic>>> fetchInletPoints() =>
      _fetchAllRows('inlet_points');

  Future<List<Map<String, dynamic>>> fetchDuctLoras() =>
      _fetchAllRows('duct_loras');

  Future<List<Map<String, dynamic>>> fetchGateways() => _fetchAllRows('gateways');

  Future<List<Map<String, dynamic>>> fetchBomManualEntries() =>
      _fetchAllRows('bom_manual_entries');

  // ---- Immutable BoM history (Full sync Group 3) --------------------------
  //
  // These six were push-only until this slice: a survey's finalized BoM and
  // its whole revision history lived only on the device that created it, so
  // a reinstall or a second device saw nothing. They're immutable by design
  // (no delete path anywhere in the app, and no DELETE policy), so their
  // pulls are plain upserts — no tombstone, no absence-based reconcile.
  //
  // RLS scopes all six through the owning survey: the three parent tables
  // directly via can_access_site(survey_id), and the three line tables one
  // hop further via can_access_bom_snapshot / can_access_bom_revision /
  // can_access_bom_manual_edit_snapshot, which resolve the parent's own
  // survey_id (see schema.sql's Slice 2g block). So a line row is returned
  // iff its parent snapshot/revision is visible — the caller never has to
  // filter by parent itself.

  Future<List<Map<String, dynamic>>> fetchBomSnapshots() =>
      _fetchAllRows('bom_snapshots');

  Future<List<Map<String, dynamic>>> fetchBomSnapshotLines() =>
      _fetchAllRows('bom_snapshot_lines');

  Future<List<Map<String, dynamic>>> fetchBomRevisions() =>
      _fetchAllRows('bom_revisions');

  Future<List<Map<String, dynamic>>> fetchBomRevisionLines() =>
      _fetchAllRows('bom_revision_lines');

  Future<List<Map<String, dynamic>>> fetchBomManualEditSnapshots() =>
      _fetchAllRows('bom_manual_edit_snapshots');

  Future<List<Map<String, dynamic>>> fetchBomManualEditSnapshotLines() =>
      _fetchAllRows('bom_manual_edit_snapshot_lines');

  /// Upserts a Material Master change-log entry by its id (idempotent). Not
  /// site-scoped, and not FK'd to the material row either (a delete's own
  /// audit entry must survive the row's removal).
  Future<void> pushMaterialMasterAuditEntry(
    MaterialMasterAuditEntry entry,
  ) async {
    await _client
        .from('material_master_audit')
        .upsert(_materialMasterAuditEntryToRemoteRow(entry));
  }

  /// Name of the Storage bucket holding survey photos. Must exist (see
  /// supabase/schema.sql) before uploads succeed.
  static const String photoBucket = 'survey-photos';

  /// Uploads a local photo file to Storage under [objectKey] (idempotent —
  /// re-uploading the same key overwrites). The key's naming convention is
  /// always `.jpg` (set by the caller) regardless of the file's real format —
  /// only the Content-Type header (derived here from the local file's actual
  /// extension) needs to match the bytes, e.g. for markup output (PNG).
  /// Returns the object key on success.
  Future<String> uploadPhoto(String localPath, String objectKey) async {
    await _client.storage
        .from(photoBucket)
        .upload(
          objectKey,
          File(localPath),
          fileOptions: FileOptions(
            upsert: true,
            contentType: _contentTypeFor(localPath),
          ),
        );
    return objectKey;
  }

  /// Upserts a photo metadata row by its id (idempotent). The device-local
  /// file path is never pushed — only the Storage object key.
  Future<void> pushPhoto(SurveyPhoto photo) async {
    await _client.from('photos').upsert(_photoToRemoteRow(photo));
  }

  /// Marks a photo deleted by id — a `deleted_at` tombstone via UPDATE, not
  /// a real DELETE (photos has no DELETE policy at all — Slice 2e — so this
  /// is also the only delete the database permits).
  ///
  /// Used when the user removes a single photo from a form, which no cascade
  /// covers: the Groups 2-3 cascade only fires when a photo's *owner* is
  /// deleted. Without this the removal was never pushed at all, and Group
  /// 4's pull resurrected the photo from the still-live remote row.
  /// Idempotent — re-tombstoning, or tombstoning a photo that was removed
  /// before it ever uploaded, is a harmless no-op affecting zero rows.
  ///
  /// The Storage object is deliberately left in place; see [downloadPhoto].
  Future<void> deletePhoto(String id, {required String? siteId}) =>
      _tombstone('photos', id, siteId: siteId);

  /// Every photo metadata row this account can see (RLS scopes it by
  /// can_access_site(site_id) — Slice 2e). Includes tombstoned rows: the
  /// SELECT policy deliberately does not filter `deleted_at`, because pull
  /// reconcile can only act on a tombstone it can actually see.
  Future<List<Map<String, dynamic>>> fetchPhotos() => _fetchAllRows('photos');

  /// Downloads the Storage object at [objectKey] (a photo's `remote_path`).
  ///
  /// Note there is deliberately no matching delete: Slice 2h granted
  /// storage.objects SELECT and INSERT only, so a client DELETE is refused
  /// (verified: HTTP 403 AccessDenied). Tombstoning a photo therefore leaves
  /// its Storage object behind — an accepted, low-cost tradeoff at this
  /// team's scale, not an oversight. The `deleted_at` tombstone remains the
  /// authoritative record that the photo is gone; only the bytes linger.
  Future<Uint8List> downloadPhoto(String objectKey) =>
      _client.storage.from(photoBucket).download(objectKey);

  /// Upserts a BoM manual entry by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushBomManualEntry(BomManualEntry entry) async {
    await _client
        .from('bom_manual_entries')
        .upsert(_bomManualEntryToRemoteRow(entry));
  }

  /// Marks a BoM manual entry deleted by id — a `deleted_at` tombstone, not
  /// a real `DELETE`, for the same reason as [deleteSourcePoint]. This is the
  /// only BoM table with a delete path at all; the other six are immutable.
  ///
  /// No photos cascade, unlike Group 2's tables: a manual entry owns no
  /// photos. There is no [PhotoOwner] token for one, no app path creates
  /// such a row, and the local delete path (SqfliteSurveyRepository
  /// .deleteBomManualEntry) touches only its own table — where the Group 2
  /// deletes each additionally delete their own photos. Cascading here would
  /// mean inventing an ownership relationship the app doesn't have.
  Future<void> deleteBomManualEntry(String id, {required String siteId}) =>
      _tombstone('bom_manual_entries', id, siteId: siteId);

  /// Upserts a BoM snapshot by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushBomSnapshot(BomSnapshot snapshot) async {
    await _client.from('bom_snapshots').upsert(_bomSnapshotToRemoteRow(snapshot));
  }

  /// Upserts a BoM snapshot line by its id (idempotent). The parent snapshot
  /// must already have been pushed (FK).
  Future<void> pushBomSnapshotLine(BomSnapshotLine line) async {
    await _client
        .from('bom_snapshot_lines')
        .upsert(_bomSnapshotLineToRemoteRow(line));
  }

  /// Upserts a BoM revision by its id (idempotent). The parent site must
  /// already have been pushed (FK).
  Future<void> pushBomRevision(BomRevision revision) async {
    await _client.from('bom_revisions').upsert(_bomRevisionToRemoteRow(revision));
  }

  /// Upserts a BoM revision line by its id (idempotent). The parent revision
  /// must already have been pushed (FK).
  Future<void> pushBomRevisionLine(BomRevisionLine line) async {
    await _client
        .from('bom_revision_lines')
        .upsert(_bomRevisionLineToRemoteRow(line));
  }

  /// Upserts a BoM manual-edit snapshot by its id (idempotent). The parent
  /// site must already have been pushed (FK).
  Future<void> pushBomManualEditSnapshot(BomManualEditSnapshot s) async {
    await _client
        .from('bom_manual_edit_snapshots')
        .upsert(_bomManualEditSnapshotToRemoteRow(s));
  }

  /// Upserts a BoM manual-edit snapshot line by its id (idempotent). The
  /// parent snapshot must already have been pushed (FK).
  Future<void> pushBomManualEditSnapshotLine(
    BomManualEditSnapshotLine line,
  ) async {
    await _client
        .from('bom_manual_edit_snapshot_lines')
        .upsert(_bomManualEditSnapshotLineToRemoteRow(line));
  }
}

/// Maps client inputs to a Supabase row. Unlike SQLite, Postgres has a native
/// boolean type, so yes/no fields are sent as real booleans (null = unanswered).
Map<String, Object?> _inputsToRemoteRow(String siteId, ClientInputs i) {
  return {
    'site_id': siteId,
    'site_name': i.siteName,
    'information_source': i.informationSource?.name,
    'client_poc_name': i.clientPocName,
    'client_poc_contact': i.clientPocContact,
    'goal_of_installation': i.goalOfInstallation,
    'water_sources': i.waterSources.map((w) => w.name).join(','),
    'oht_hns': i.ohtHns?.name,
    'finalised_plumbing_drawings': i.finalisedPlumbingDrawings,
    'points_identified': i.pointsIdentified,
    'max_and_continuous_pressure': i.maxAndContinuousPressure,
    'pressure_boosters': i.pressureBoosters,
    'materials_and_brand_guidelines': i.materialsAndBrandGuidelines,
    'rework_required': i.reworkRequired,
    'rework_details': i.reworkDetails,
    'age_of_plumbing_lines': i.ageOfPlumbingLines,
    'aesthetic_guidelines': i.aestheticGuidelines,
    'aesthetic_details': i.aestheticDetails,
  };
}

Map<String, Object?> _sourcePointToRemoteRow(SourcePoint s) {
  return {
    'id': s.id,
    'site_id': s.siteId,
    'block': s.block,
    'apartment': s.apartment,
    'inlet_description': s.inletDescription,
    'material_id': s.materialId,
    'sensor_size': s.sensorSize?.name,
    'sensor_od': s.sensorOd?.name,
    'pipe_size': s.pipeSize?.name,
    'pipe_type': s.pipeType?.name,
    'qty': s.qty,
    'sensor_type': s.sensorType?.name,
    'rework': s.rework,
    'rework_details': s.reworkDetails,
    'flow_direction': s.flowDirection?.name,
    'clearance_10x': s.clearance10x,
    'pipe_full': s.pipeFull,
    'valve_downstream': s.valveDownstream,
    'reducer_spec': s.reducerSpec,
    'reducer_spec_details': s.reducerSpecDetails,
    'downstream_outlet_above_pipe_fig1': s.downstreamOutletAbovePipeFig1,
    'air_vent_needed_fig2': s.airVentNeededFig2,
    'reverse_flow': s.reverseFlow,
    'distance_from_motor_pump_fig3': s.distanceFromMotorPumpFig3,
    'no_flexible_pipe_within_20x': s.noFlexiblePipeWithin20x,
    'max_and_continuous_pressure_bar': s.maxAndContinuousPressureBar,
    'strainer_screen_filter': s.strainerScreenFilter,
    'chamber_installation': s.chamberInstallation,
    'antenna_required': s.antennaRequired,
    'transmitting_part_open_to_air': s.transmittingPartOpenToAir,
    'nrv_feasibility': s.nrvFeasibility,
  };
}

Map<String, Object?> _inletPointToRemoteRow(InletPoint i) {
  return {
    'id': i.id,
    'site_id': i.siteId,
    'block': i.block,
    'apartment_bhk': i.apartmentBhk,
    'material_id': i.materialId,
    'sensor_size': i.sensorSize?.name,
    'series': i.series,
    'sensor_od': i.sensorOd?.name,
    'pipe_size': i.pipeSize?.name,
    'pipe_type': i.pipeType?.name,
    'qty': i.qty,
    'sensor_type': i.sensorType?.name,
    'rework': i.rework,
    'rework_details': i.reworkDetails,
    'linear_distance_clearance_10x': i.linearDistanceClearance10x,
    'reverse_flow': i.reverseFlow,
    'oht_hns': i.ohtHns?.name,
    'distance_from_motor_pump': i.distanceFromMotorPump,
    'max_and_continuous_pressure_bar': i.maxAndContinuousPressureBar,
    'strainer_screen_filter': i.strainerScreenFilter,
    'flow_direction': i.flowDirection?.name,
    'access_mode': i.accessMode?.name,
    'cable_run_length': i.cableRunLength?.name,
    'conduit_clamping': i.conduitClamping,
    'civil_work_needed': i.civilWorkNeeded,
    'civil_work_details': i.civilWorkDetails,
  };
}

Map<String, Object?> _ductLoraToRemoteRow(DuctLora d) {
  return {
    'id': d.id,
    'site_id': d.siteId,
    'block': d.block,
    // Comma-separated set, mirroring the local store and client_inputs.
    'series_served': d.seriesServed.join(','),
    'accessible_for_service': d.accessibleForService,
    'rssi_if_tcl': d.rssiIfTcl,
    'power_point_available_shielded': d.powerPointAvailableShielded,
    'separate_mcb_for_series': d.separateMcbForSeries,
    'ups_power_supply': d.upsPowerSupply,
    'cable_length': d.cableLength,
  };
}

Map<String, Object?> _gatewayToRemoteRow(Gateway g) {
  return {
    'id': g.id,
    'site_id': g.siteId,
    'placement': g.placement?.name,
    'location_description': g.locationDescription,
    'blocks_covered': g.blocksCovered.join(','),
    'quantity': g.quantity,
    'uplink_type': g.uplinkType?.name,
    'wifi_interference_check': g.wifiInterferenceCheck,
    'wifi_interference_details': g.wifiInterferenceDetails,
    'sim_coverage': g.simCoverage?.name,
    'uninterrupted_power_source': g.uninterruptedPowerSource,
    'mounting_hardware_needed': g.mountingHardwareNeeded,
  };
}

Map<String, Object?> _footerToRemoteRow(String siteId, Footer f) {
  return {
    'site_id': siteId,
    'tds_ppm': f.tdsPpm,
    'tss_ppm': f.tssPpm,
    'tcl_service': f.tclService,
    'tcl_service_details': f.tclServiceDetails,
    'general_remarks': f.generalRemarks,
    'survey_date': f.surveyDate?.toIso8601String(),
    'surveyor_name': f.surveyorName,
  };
}

/// Fetches one page of a table: [limit] rows starting at [offset].
typedef PageFetcher = Future<List<Map<String, dynamic>>> Function(
  int offset,
  int limit,
);

/// Walks the pages of a table after the first one, given the total row count
/// the first response reported.
///
/// Deliberately separate from [SupabaseSurveyDataSource] and its Supabase
/// client: the interesting behaviour here is arithmetic with several edge
/// cases that are easy to get subtly wrong and impossible to observe from
/// outside — a total that divides exactly by the page size (must NOT cost a
/// trailing empty request), a server returning fewer rows than asked for,
/// and an empty table. Welded to the client, none of that could be tested at
/// all; as a plain function over a [PageFetcher], all of it can.
///
/// Returns [firstPage] plus every remaining row, so the caller always
/// receives the complete table — which is load-bearing, since sites' and
/// blocks' pulls reconcile deletes by absence and would remove local rows
/// that merely failed to be fetched.
Future<List<Map<String, dynamic>>> paginateRemainingPages({
  required int total,
  required List<Map<String, dynamic>> firstPage,
  required PageFetcher fetchPage,
  int pageConcurrency = 4,
}) async {
  final all = [...firstPage];

  // The common case by far, and the whole point of asking for a count: one
  // request and no empty follow-up. Also covers a genuinely empty table, and
  // guards the division below against a zero-length page.
  if (all.isEmpty || all.length >= total) return all;

  // What the server was actually willing to return, which may be less than
  // was asked for — PostgREST caps at a configured max-rows. Stepping by the
  // requested size instead would skip every row in the gap.
  final effectivePageSize = all.length;
  final offsets = [
    for (var o = effectivePageSize; o < total; o += effectivePageSize) o,
  ];

  // Bounded batches rather than one Future.wait over every offset: a table
  // needing 20 pages must not open 20 connections at once, especially while
  // the caller is fetching other tables concurrently.
  for (var i = 0; i < offsets.length; i += pageConcurrency) {
    final pages = await Future.wait([
      for (final offset in offsets.skip(i).take(pageConcurrency))
        fetchPage(offset, effectivePageSize),
    ]);
    for (final page in pages) {
      all.addAll(page);
    }
  }

  return all;
}

Map<String, Object?> _photoToRemoteRow(SurveyPhoto p) {
  return {
    'id': p.id,
    'owner_type': p.ownerType,
    'owner_id': p.ownerId,
    'slot': p.slot,
    'position': p.position,
    // Local path is device-specific and never pushed.
    'remote_path': p.remotePath,
    'site_id': p.siteId,
  };
}

/// Content-Type for an upload, derived from the local file's real extension.
/// Camera captures are `.jpg`; markup output is `.png` — defaults to JPEG for
/// anything else.
String _contentTypeFor(String localPath) {
  switch (p.extension(localPath).toLowerCase()) {
    case '.png':
      return 'image/png';
    default:
      return 'image/jpeg';
  }
}

Map<String, Object?> _materialMasterItemToRemoteRow(MaterialMasterItem m) {
  return {
    'id': m.id,
    'group_code': m.group.name,
    'material_name': m.materialName,
    'sku': m.sku,
    'item_label': m.itemLabel,
    'unit': m.unit,
    'behavior_type': m.behaviorType.name,
    'sensor_size': m.sensorSize?.name,
    'sensor_type': m.sensorType?.name,
    'quantity_per_sensor': m.quantityPerSensor,
    'derived_formula': m.derivedFormula?.name,
    'formula_divisor': m.formulaDivisor,
    'variable_source': m.variableSource?.name,
    'notes': m.notes,
    'material_type': m.materialType,
    'category': m.category,
    'variant': m.variant,
    'size_mm': m.sizeMm,
    'size_display': m.sizeDisplay,
  };
}

MaterialMasterItem _materialMasterItemFromRemoteRow(Map<String, dynamic> r) {
  return MaterialMasterItem(
    id: r['id'] as String,
    group: _materialGroupFromRemoteCode(r['group_code'] as String?),
    materialName: (r['material_name'] as String?) ?? '',
    sku: (r['sku'] as String?) ?? '',
    itemLabel: (r['item_label'] as String?) ?? '',
    unit: (r['unit'] as String?) ?? '',
    behaviorType:
        _enumByName(MaterialBehaviorType.values, r['behavior_type'] as String?) ??
        MaterialBehaviorType.fixed,
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    quantityPerSensor: (r['quantity_per_sensor'] as num?)?.toDouble() ?? 0,
    derivedFormula: _enumByName(
      DerivedFormula.values,
      r['derived_formula'] as String?,
    ),
    formulaDivisor: (r['formula_divisor'] as num?)?.toDouble(),
    variableSource: _enumByName(
      VariableSource.values,
      r['variable_source'] as String?,
    ),
    notes: (r['notes'] as String?) ?? '',
    materialType: r['material_type'] as String?,
    category: r['category'] as String?,
    variant: r['variant'] as String?,
    sizeMm: (r['size_mm'] as num?)?.toDouble(),
    sizeDisplay: r['size_display'] as String?,
  );
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Resolves a Supabase material_master_items.group_code value to its
/// [MaterialGroup]. This table's own convention (every row this app itself
/// writes) is the lowercase enum identifier, e.g. 'c' — but a bulk SQL
/// import (the plumbing catalog) instead used the uppercase display letter,
/// e.g. 'C', for every row. `_enumByName`'s exact, case-sensitive match
/// against `.name` silently missed all of those and fell back to A, so
/// this accepts either form, matched case-insensitively, before falling
/// back. Falls back to A only when truly unrecognized — same default
/// [_enumByName] already used here.
MaterialGroup _materialGroupFromRemoteCode(String? code) {
  if (code == null) return MaterialGroup.a;
  final normalized = code.toLowerCase();
  for (final group in MaterialGroup.values) {
    if (group.name == normalized || group.code.toLowerCase() == normalized) {
      return group;
    }
  }
  return MaterialGroup.a;
}

Map<String, Object?> _materialMasterAuditEntryToRemoteRow(
  MaterialMasterAuditEntry e,
) {
  return {
    'id': e.id,
    'material_row_id': e.materialRowId,
    'field_changed': e.fieldChanged,
    'old_value': e.oldValue,
    'new_value': e.newValue,
    'changed_by_role': e.changedByRole,
    'changed_by_user_id': e.changedByUserId,
    'changed_at': e.changedAt.toIso8601String(),
  };
}

Map<String, Object?> _bomManualEntryToRemoteRow(BomManualEntry e) {
  return {
    'id': e.id,
    'survey_id': e.surveyId,
    'material_name': e.materialName,
    'sku': e.sku,
    'item_label': e.itemLabel,
    'sensor_size': e.sensorSize?.name,
    'sensor_type': e.sensorType?.name,
    'unit': e.unit,
    'qty': e.qty,
    // Literal 'D' / 'E' / 'G' — see the matching comment in
    // sqflite_survey_repository.dart's _bomManualEntryToRow.
    'group_code': e.group.code,
    'added_by': e.addedBy,
    'added_by_user_id': e.addedByUserId,
    'added_at': e.addedAt.toIso8601String(),
  };
}

Map<String, Object?> _bomSnapshotToRemoteRow(BomSnapshot s) {
  return {
    'id': s.id,
    'survey_id': s.surveyId,
    'version': s.version,
    'status': s.status,
    'finalized_by': s.finalizedBy,
    'finalized_by_user_id': s.finalizedByUserId,
    'finalized_at': s.finalizedAt.toIso8601String(),
  };
}

Map<String, Object?> _bomSnapshotLineToRemoteRow(BomSnapshotLine l) {
  return {
    'id': l.id,
    'snapshot_id': l.snapshotId,
    'sku': l.sku,
    'item': l.item,
    'material_name': l.materialName,
    'item_label': l.itemLabel,
    'sensor_size': l.sensorSize?.name,
    'sensor_type': l.sensorType?.name,
    'unit': l.unit,
    'qty': l.qty,
    // Literal 'A'..'G' — see the matching comment in
    // sqflite_survey_repository.dart's _bomSnapshotLineToRow.
    'group_code': l.group.code,
    'source': l.source.name, // literal 'auto' | 'manual'
  };
}

Map<String, Object?> _bomRevisionToRemoteRow(BomRevision v) {
  return {
    'id': v.id,
    'survey_id': v.surveyId,
    'version': v.version,
    'reason': v.reason,
    'created_by': v.createdBy,
    'created_by_user_id': v.createdByUserId,
    'created_at': v.createdAt.toIso8601String(),
  };
}

Map<String, Object?> _bomRevisionLineToRemoteRow(BomRevisionLine l) {
  return {
    'id': l.id,
    'revision_id': l.revisionId,
    'sku': l.sku,
    'item': l.item,
    'material_name': l.materialName,
    'item_label': l.itemLabel,
    'sensor_size': l.sensorSize?.name,
    'sensor_type': l.sensorType?.name,
    'unit': l.unit,
    'qty_delta': l.qtyDelta,
    // Literal 'A'..'G' — see the matching comment in
    // sqflite_survey_repository.dart's _bomRevisionLineToRow.
    'group_code': l.group.code,
  };
}

Map<String, Object?> _bomManualEditSnapshotToRemoteRow(
  BomManualEditSnapshot s,
) {
  return {
    'id': s.id,
    'survey_id': s.surveyId,
    'version': s.version,
    'based_on_version': s.basedOnVersion,
    'edited_by': s.editedBy,
    'edited_at': s.editedAt.toIso8601String(),
    'reason': s.reason,
  };
}

Map<String, Object?> _bomManualEditSnapshotLineToRemoteRow(
  BomManualEditSnapshotLine l,
) {
  return {
    'id': l.id,
    'snapshot_id': l.snapshotId,
    'sku': l.sku,
    'item_name': l.itemName,
    'description': l.description,
    'unit': l.unit,
    'qty': l.qty,
    'group_code': l.group.code,
  };
}
