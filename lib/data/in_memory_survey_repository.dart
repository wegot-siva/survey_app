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
import '../models/engineer_directory.dart';
import '../models/footer.dart';
import '../models/gateway.dart';
import '../models/inlet_point.dart';
import '../models/material_master_audit_entry.dart';
import '../models/material_master_item.dart';
import '../models/site.dart';
import '../models/source_point.dart';
import '../models/survey_assignment_audit_entry.dart';
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import '../models/survey_status.dart';
import '../services/id_service.dart';
import '../services/material_master_audit_builder.dart';
import 'survey_repository.dart';

/// Phase 0 storage: everything lives in a map and is lost on restart.
/// Swappable for a real DB later — the UI only sees [SurveyRepository].
class InMemorySurveyRepository implements SurveyRepository {
  InMemorySurveyRepository(this._idService) {
    _engineers = [
      for (final name in kEngineerDirectory)
        Engineer(id: _idService.newId(), name: name),
    ];
  }

  final IdService _idService;
  final Map<String, Site> _sites = {};
  final Map<String, SourcePoint> _sourcePoints = {};
  final Map<String, InletPoint> _inletPoints = {};
  final Map<String, DuctLora> _ductLoras = {};
  final Map<String, Gateway> _gateways = {};
  final Map<String, Footer> _footers = {};
  final Map<String, MaterialMasterItem> _materialMasterItems = {};
  final Map<String, SurveyPhoto> _photos = {};
  final Map<String, MaterialMasterAuditEntry> _materialMasterAudit = {};
  static const _auditBuilder = MaterialMasterAuditBuilder();
  final Map<String, BomManualEntry> _bomManualEntries = {};
  final Map<String, BomSnapshot> _bomSnapshots = {}; // keyed by surveyId
  final Map<String, List<BomSnapshotLine>> _bomSnapshotLines = {}; // keyed by snapshotId
  final Map<String, BomRevision> _bomRevisions = {}; // keyed by id
  final Map<String, List<BomRevisionLine>> _bomRevisionLines = {}; // keyed by revisionId
  final Map<String, BomManualEditSnapshot> _bomManualEditSnapshots = {}; // keyed by id
  final Map<String, List<BomManualEditSnapshotLine>> _bomManualEditSnapshotLines = {}; // keyed by snapshotId
  late final List<Engineer> _engineers;
  final Map<String, SurveyAssignmentAuditEntry> _assignmentAudit = {};

  // ---- Dirty-tracking (sync) --------------------------------------------
  //
  // Mirrors the sqflite repo's `dirty` column with a per-table id set: added
  // on every local create/update, removed by the matching markXxxSynced.
  // Blocks have no set of their own — they ride on _dirtySiteIds, same as
  // the sqflite implementation (see updateSiteBlocks).
  final Set<String> _dirtySiteIds = {};
  final Set<String> _dirtyClientInputsSiteIds = {};
  final Set<String> _dirtySourcePointIds = {};
  final Set<String> _dirtyInletPointIds = {};
  final Set<String> _pendingDeleteSourcePointIds = {};
  final Set<String> _pendingDeleteInletPointIds = {};
  final Set<String> _pendingDeleteDuctLoraIds = {};
  final Set<String> _pendingDeleteGatewayIds = {};
  final Set<String> _pendingDeleteBomManualEntryIds = {};
  final Set<String> _dirtyDuctLoraIds = {};
  final Set<String> _dirtyGatewayIds = {};
  final Set<String> _dirtyFooterSiteIds = {};
  final Set<String> _dirtyMaterialMasterItemIds = {};
  final Set<String> _pendingDeleteMaterialMasterItemIds = {};
  final Set<String> _dirtyMaterialMasterAuditIds = {};
  final Set<String> _dirtyPhotoIds = {};
  final Set<String> _dirtyBomManualEntryIds = {};
  final Set<String> _dirtyBomSnapshotIds = {};
  final Set<String> _dirtyBomSnapshotLineIds = {};
  final Set<String> _dirtyBomRevisionIds = {};
  final Set<String> _dirtyBomRevisionLineIds = {};
  final Set<String> _dirtyBomManualEditSnapshotIds = {};
  final Set<String> _dirtyBomManualEditSnapshotLineIds = {};

  @override
  Future<List<Site>> getSites({
    bool includeArchived = false,
    bool dirtyOnly = false,
  }) async => _sites.values
      .where(
        (s) =>
            (includeArchived || !s.archived) &&
            (!dirtyOnly || _dirtySiteIds.contains(s.id)),
      )
      .toList(growable: false);

  @override
  Future<Site?> getSiteById(String id) async => _sites[id];

  @override
  Future<Site> createSite({
    required String name,
    List<String> blocks = const [],
  }) async {
    final site = Site(
      id: _idService.newId(),
      name: name,
      blocks: List.unmodifiable(blocks),
    );
    _sites[site.id] = site;
    _dirtySiteIds.add(site.id);
    return site;
  }

  @override
  Future<void> updateSite(Site site) async {
    _sites[site.id] = site;
    _dirtySiteIds.add(site.id);
    // Mirrors the sqflite repo: updateSite always re-persists client inputs
    // when present, so it's also dirty after this call.
    if (site.clientInputs != null) _dirtyClientInputsSiteIds.add(site.id);
  }

  @override
  Future<void> updateSiteBlocks(String siteId, List<String> blocks) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot update blocks: site "$siteId" not found.');
    }
    _sites[siteId] = site.copyWith(blocks: List.unmodifiable(blocks));
    _dirtySiteIds.add(siteId);
  }

  @override
  Future<void> saveClientInputs(String siteId, ClientInputs inputs) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot save client inputs: site "$siteId" not found.');
    }
    _sites[siteId] = site.copyWith(clientInputs: inputs);
    _dirtyClientInputsSiteIds.add(siteId);
  }

  @override
  Future<bool> isClientInputsDirty(String siteId) async =>
      _dirtyClientInputsSiteIds.contains(siteId);

  @override
  Future<void> markSiteSynced(String siteId) async {
    _dirtySiteIds.remove(siteId);
  }

  @override
  Future<void> markClientInputsSynced(String siteId) async {
    _dirtyClientInputsSiteIds.remove(siteId);
  }

  /// Mirrors [SqfliteSurveyRepository]'s pull-reconcile: an unsynced local
  /// edit is left untouched; blocks/clientInputs and the Sales-only fields
  /// (archived/address/clientName/clientContact — never pushed to Supabase
  /// at all) are carried over from the existing row, not reset, since the
  /// remote payload never carries them.
  @override
  Future<void> upsertSitesFromRemote(List<Map<String, dynamic>> remoteRows) async {
    for (final row in remoteRows) {
      final id = row['id'] as String;
      if (_dirtySiteIds.contains(id)) continue;
      final existing = _sites[id];
      _sites[id] = Site(
        id: id,
        name: (row['name'] as String?) ?? '',
        blocks: existing?.blocks ?? const [],
        clientInputs: existing?.clientInputs,
        status: row['status'] as String?,
        assignedTo: row['assigned_to'] as String?,
        bomLocked: (row['bom_locked'] as bool?) ?? false,
        archived: existing?.archived ?? false,
        address: existing?.address ?? '',
        clientName: existing?.clientName ?? '',
        clientContact: existing?.clientContact ?? '',
      );
    }

    if (remoteRows.isEmpty) return;
    final remoteIds = remoteRows.map((r) => r['id'] as String).toSet();
    for (final id in _sites.keys.toList()) {
      if (remoteIds.contains(id)) continue;
      if (_dirtySiteIds.contains(id)) continue;
      _sites.remove(id);
    }
  }

  @override
  Future<void> upsertClientInputsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    for (final row in remoteRows) {
      final siteId = row['site_id'] as String;
      if (_dirtyClientInputsSiteIds.contains(siteId)) continue;
      final site = _sites[siteId];
      if (site == null) continue; // parent site not pulled yet
      _sites[siteId] = site.copyWith(clientInputs: _clientInputsFromRemoteRow(row));
    }

    if (remoteRows.isEmpty) return;
    final remoteSiteIds = remoteRows.map((r) => r['site_id'] as String).toSet();
    for (final entry in _sites.entries.toList()) {
      final site = entry.value;
      if (site.clientInputs == null) continue;
      if (remoteSiteIds.contains(entry.key)) continue;
      if (_dirtyClientInputsSiteIds.contains(entry.key)) continue;
      _sites[entry.key] = Site(
        id: site.id,
        name: site.name,
        blocks: site.blocks,
        status: site.status,
        assignedTo: site.assignedTo,
        bomLocked: site.bomLocked,
        archived: site.archived,
        address: site.address,
        clientName: site.clientName,
        clientContact: site.clientContact,
      );
    }
  }

  @override
  Future<List<SourcePoint>> getSourcePoints(
    String siteId, {
    bool dirtyOnly = false,
  }) async => _sourcePoints.values
      .where(
        (sp) =>
            sp.siteId == siteId &&
            !_pendingDeleteSourcePointIds.contains(sp.id) &&
            (!dirtyOnly || _dirtySourcePointIds.contains(sp.id)),
      )
      .toList(growable: false);

  @override
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint) async {
    final stored = sourcePoint.copyWithId(_idService.newId());
    _sourcePoints[stored.id] = stored;
    _dirtySourcePointIds.add(stored.id);
    return stored;
  }

  @override
  Future<void> updateSourcePoint(SourcePoint sourcePoint) async {
    _sourcePoints[sourcePoint.id] = sourcePoint;
    _dirtySourcePointIds.add(sourcePoint.id);
  }

  @override
  Future<void> deleteSourcePoint(String id) async {
    _pendingDeleteSourcePointIds.add(id);
    _dirtySourcePointIds.add(id);
    _photos.removeWhere(
      (_, p) => p.ownerType == PhotoOwner.sourcePoint && p.ownerId == id,
    );
  }

  @override
  Future<List<String>> getPendingDeleteSourcePointIds(String siteId) async =>
      _sourcePoints.values
          .where(
            (sp) =>
                sp.siteId == siteId &&
                _pendingDeleteSourcePointIds.contains(sp.id),
          )
          .map((sp) => sp.id)
          .toList(growable: false);

  @override
  Future<void> hardDeleteSourcePoint(String id) async {
    _sourcePoints.remove(id);
    _pendingDeleteSourcePointIds.remove(id);
    _dirtySourcePointIds.remove(id);
  }

  @override
  Future<void> markSourcePointSynced(String id) async {
    _dirtySourcePointIds.remove(id);
  }

  /// Mirrors [SqfliteSurveyRepository]'s generic pull-reconcile helper, for
  /// every id-keyed, site/survey-scoped table this phase adds pull-sync to
  /// (source_points, inlet_points, duct_loras, gateways, bom_manual_entries)
  /// — an unsynced local edit or pending delete is left untouched, and a
  /// local row absent from a complete [remoteRows] fetch is removed.
  void _upsertFromRemoteById<T>({
    required Map<String, T> store,
    required Set<String> dirtyIds,
    required Set<String> pendingDeleteIds,
    required List<Map<String, dynamic>> remoteRows,
    required T Function(Map<String, dynamic>) fromRow,
  }) {
    for (final row in remoteRows) {
      final id = row['id'] as String;
      if (dirtyIds.contains(id) || pendingDeleteIds.contains(id)) continue;
      store[id] = fromRow(row);
    }

    if (remoteRows.isEmpty) return;
    final remoteIds = remoteRows.map((r) => r['id'] as String).toSet();
    for (final id in store.keys.toList()) {
      if (remoteIds.contains(id)) continue;
      if (dirtyIds.contains(id) || pendingDeleteIds.contains(id)) continue;
      store.remove(id);
    }
  }

  @override
  Future<void> upsertSourcePointsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    _upsertFromRemoteById<SourcePoint>(
      store: _sourcePoints,
      dirtyIds: _dirtySourcePointIds,
      pendingDeleteIds: _pendingDeleteSourcePointIds,
      remoteRows: remoteRows,
      fromRow: _sourcePointFromRemoteRow,
    );
  }

  @override
  Future<List<InletPoint>> getInletPoints(
    String siteId, {
    bool dirtyOnly = false,
  }) async => _inletPoints.values
      .where(
        (ip) =>
            ip.siteId == siteId &&
            !_pendingDeleteInletPointIds.contains(ip.id) &&
            (!dirtyOnly || _dirtyInletPointIds.contains(ip.id)),
      )
      .toList(growable: false);

  @override
  Future<InletPoint> addInletPoint(InletPoint inletPoint) async {
    final stored = inletPoint.copyWithId(_idService.newId());
    _inletPoints[stored.id] = stored;
    _dirtyInletPointIds.add(stored.id);
    return stored;
  }

  @override
  Future<void> updateInletPoint(InletPoint inletPoint) async {
    _inletPoints[inletPoint.id] = inletPoint;
    _dirtyInletPointIds.add(inletPoint.id);
  }

  @override
  Future<void> deleteInletPoint(String id) async {
    _pendingDeleteInletPointIds.add(id);
    _dirtyInletPointIds.add(id);
    _photos.removeWhere(
      (_, p) => p.ownerType == PhotoOwner.inletPoint && p.ownerId == id,
    );
  }

  @override
  Future<List<String>> getPendingDeleteInletPointIds(String siteId) async =>
      _inletPoints.values
          .where(
            (ip) =>
                ip.siteId == siteId &&
                _pendingDeleteInletPointIds.contains(ip.id),
          )
          .map((ip) => ip.id)
          .toList(growable: false);

  @override
  Future<void> hardDeleteInletPoint(String id) async {
    _inletPoints.remove(id);
    _pendingDeleteInletPointIds.remove(id);
    _dirtyInletPointIds.remove(id);
  }

  @override
  Future<void> markInletPointSynced(String id) async {
    _dirtyInletPointIds.remove(id);
  }

  @override
  Future<void> upsertInletPointsFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    _upsertFromRemoteById<InletPoint>(
      store: _inletPoints,
      dirtyIds: _dirtyInletPointIds,
      pendingDeleteIds: _pendingDeleteInletPointIds,
      remoteRows: remoteRows,
      fromRow: _inletPointFromRemoteRow,
    );
  }

  @override
  Future<List<DuctLora>> getDuctLoras(
    String siteId, {
    bool dirtyOnly = false,
  }) async => _ductLoras.values
      .where(
        (d) =>
            d.siteId == siteId &&
            !_pendingDeleteDuctLoraIds.contains(d.id) &&
            (!dirtyOnly || _dirtyDuctLoraIds.contains(d.id)),
      )
      .toList(growable: false);

  @override
  Future<DuctLora> addDuctLora(DuctLora ductLora) async {
    final stored = ductLora.copyWithId(_idService.newId());
    _ductLoras[stored.id] = stored;
    _dirtyDuctLoraIds.add(stored.id);
    return stored;
  }

  @override
  Future<void> updateDuctLora(DuctLora ductLora) async {
    _ductLoras[ductLora.id] = ductLora;
    _dirtyDuctLoraIds.add(ductLora.id);
  }

  @override
  Future<void> deleteDuctLora(String id) async {
    _pendingDeleteDuctLoraIds.add(id);
    _dirtyDuctLoraIds.add(id);
    _photos.removeWhere(
      (_, p) => p.ownerType == PhotoOwner.ductLora && p.ownerId == id,
    );
  }

  @override
  Future<List<String>> getPendingDeleteDuctLoraIds(String siteId) async =>
      _ductLoras.values
          .where(
            (d) => d.siteId == siteId && _pendingDeleteDuctLoraIds.contains(d.id),
          )
          .map((d) => d.id)
          .toList(growable: false);

  @override
  Future<void> hardDeleteDuctLora(String id) async {
    _ductLoras.remove(id);
    _pendingDeleteDuctLoraIds.remove(id);
    _dirtyDuctLoraIds.remove(id);
  }

  @override
  Future<void> markDuctLoraSynced(String id) async {
    _dirtyDuctLoraIds.remove(id);
  }

  @override
  Future<void> upsertDuctLorasFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    _upsertFromRemoteById<DuctLora>(
      store: _ductLoras,
      dirtyIds: _dirtyDuctLoraIds,
      pendingDeleteIds: _pendingDeleteDuctLoraIds,
      remoteRows: remoteRows,
      fromRow: _ductLoraFromRemoteRow,
    );
  }

  @override
  Future<List<Gateway>> getGateways(
    String siteId, {
    bool dirtyOnly = false,
  }) async => _gateways.values
      .where(
        (g) =>
            g.siteId == siteId &&
            !_pendingDeleteGatewayIds.contains(g.id) &&
            (!dirtyOnly || _dirtyGatewayIds.contains(g.id)),
      )
      .toList(growable: false);

  @override
  Future<Gateway> addGateway(Gateway gateway) async {
    final stored = gateway.copyWithId(_idService.newId());
    _gateways[stored.id] = stored;
    _dirtyGatewayIds.add(stored.id);
    return stored;
  }

  @override
  Future<void> updateGateway(Gateway gateway) async {
    _gateways[gateway.id] = gateway;
    _dirtyGatewayIds.add(gateway.id);
  }

  @override
  Future<void> deleteGateway(String id) async {
    _pendingDeleteGatewayIds.add(id);
    _dirtyGatewayIds.add(id);
    _photos.removeWhere(
      (_, p) => p.ownerType == PhotoOwner.gateway && p.ownerId == id,
    );
  }

  @override
  Future<List<String>> getPendingDeleteGatewayIds(String siteId) async =>
      _gateways.values
          .where(
            (g) => g.siteId == siteId && _pendingDeleteGatewayIds.contains(g.id),
          )
          .map((g) => g.id)
          .toList(growable: false);

  @override
  Future<void> hardDeleteGateway(String id) async {
    _gateways.remove(id);
    _pendingDeleteGatewayIds.remove(id);
    _dirtyGatewayIds.remove(id);
  }

  @override
  Future<void> markGatewaySynced(String id) async {
    _dirtyGatewayIds.remove(id);
  }

  @override
  Future<void> upsertGatewaysFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    _upsertFromRemoteById<Gateway>(
      store: _gateways,
      dirtyIds: _dirtyGatewayIds,
      pendingDeleteIds: _pendingDeleteGatewayIds,
      remoteRows: remoteRows,
      fromRow: _gatewayFromRemoteRow,
    );
  }

  @override
  Future<Footer?> getFooter(String siteId) async => _footers[siteId];

  @override
  Future<void> saveFooter(String siteId, Footer footer) async {
    if (!_sites.containsKey(siteId)) {
      throw StateError('Cannot save footer: site "$siteId" not found.');
    }
    _footers[siteId] = footer;
    _dirtyFooterSiteIds.add(siteId);
  }

  @override
  Future<bool> isFooterDirty(String siteId) async =>
      _dirtyFooterSiteIds.contains(siteId);

  @override
  Future<void> markFooterSynced(String siteId) async {
    _dirtyFooterSiteIds.remove(siteId);
  }

  @override
  Future<void> upsertFootersFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    for (final row in remoteRows) {
      final siteId = row['site_id'] as String;
      if (_dirtyFooterSiteIds.contains(siteId)) continue;
      _footers[siteId] = _footerFromRemoteRow(row);
    }

    if (remoteRows.isEmpty) return;
    final remoteSiteIds = remoteRows.map((r) => r['site_id'] as String).toSet();
    for (final siteId in _footers.keys.toList()) {
      if (remoteSiteIds.contains(siteId)) continue;
      if (_dirtyFooterSiteIds.contains(siteId)) continue;
      _footers.remove(siteId);
    }
  }

  @override
  Future<List<MaterialMasterItem>> getMaterialMasterItems({
    bool dirtyOnly = false,
  }) async => _materialMasterItems.values
      .where(
        (m) =>
            !_pendingDeleteMaterialMasterItemIds.contains(m.id) &&
            (!dirtyOnly || _dirtyMaterialMasterItemIds.contains(m.id)),
      )
      .toList(growable: false);

  @override
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  }) async {
    final stored = item.copyWithId(_idService.newId());
    _materialMasterItems[stored.id] = stored;
    _dirtyMaterialMasterItemIds.add(stored.id);
    _writeAudit(
      _auditBuilder.forCreate(
        item: stored,
        changedByRole: changedByRole,
        changedAt: DateTime.now(),
      ),
    );
    return stored;
  }

  @override
  Future<void> updateMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  }) async {
    final existing = _materialMasterItems[item.id];
    _materialMasterItems[item.id] = item;
    _dirtyMaterialMasterItemIds.add(item.id);
    if (existing != null) {
      _writeAudit(
        _auditBuilder.forUpdate(
          oldItem: existing,
          newItem: item,
          changedByRole: changedByRole,
          changedAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<void> deleteMaterialMasterItem(
    String id, {
    required String changedByRole,
  }) async {
    final existing = _materialMasterItems[id];
    if (existing == null) return;
    // Tombstone (and mark dirty, so sync pushes a real remote delete for
    // it) instead of removing the row yet — same convention as source/inlet
    // points. hardDeleteMaterialMasterItem does the actual removal.
    _pendingDeleteMaterialMasterItemIds.add(id);
    _dirtyMaterialMasterItemIds.add(id);
    _writeAudit(
      _auditBuilder.forDelete(
        item: existing,
        changedByRole: changedByRole,
        changedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<String>> getPendingDeleteMaterialMasterItemIds() async =>
      _pendingDeleteMaterialMasterItemIds.toList(growable: false);

  @override
  Future<void> hardDeleteMaterialMasterItem(String id) async {
    _materialMasterItems.remove(id);
    _pendingDeleteMaterialMasterItemIds.remove(id);
    _dirtyMaterialMasterItemIds.remove(id);
  }

  @override
  Future<void> markMaterialMasterItemSynced(String id) async {
    _dirtyMaterialMasterItemIds.remove(id);
  }

  @override
  Future<void> upsertMaterialMasterItemsFromRemote(
    List<MaterialMasterItem> remoteItems,
  ) async {
    for (final item in remoteItems) {
      if (_dirtyMaterialMasterItemIds.contains(item.id) ||
          _pendingDeleteMaterialMasterItemIds.contains(item.id)) {
        continue; // Unsynced local edit/delete — leave it, don't clobber.
      }
      _materialMasterItems[item.id] = item;
      // Deliberately not added to _dirtyMaterialMasterItemIds — it came from
      // remote, already in sync.
    }

    // Reconciliation: a row that's active locally (not dirty, not already
    // pending its own local delete) but absent from this complete remote
    // fetch was deleted directly in Supabase — remove it here too. Skipped
    // entirely when remoteItems is empty — see the sqflite repository's
    // implementation for why.
    if (remoteItems.isEmpty) return;
    final remoteIds = remoteItems.map((i) => i.id).toSet();
    for (final id in _materialMasterItems.keys.toList()) {
      if (remoteIds.contains(id)) continue;
      if (_dirtyMaterialMasterItemIds.contains(id) ||
          _pendingDeleteMaterialMasterItemIds.contains(id)) {
        continue;
      }
      _materialMasterItems.remove(id);
    }
  }

  @override
  Future<List<MaterialMasterAuditEntry>> getMaterialMasterAuditLog({
    bool dirtyOnly = false,
  }) async {
    final list = _materialMasterAudit.values
        .where((e) => !dirtyOnly || _dirtyMaterialMasterAuditIds.contains(e.id))
        .toList()
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return List.unmodifiable(list);
  }

  @override
  Future<void> markMaterialMasterAuditEntrySynced(String id) async {
    _dirtyMaterialMasterAuditIds.remove(id);
  }

  void _writeAudit(List<MaterialMasterAuditEntry> entries) {
    for (final entry in entries) {
      final stored = entry.copyWithId(_idService.newId());
      _materialMasterAudit[stored.id] = stored;
      _dirtyMaterialMasterAuditIds.add(stored.id);
    }
  }

  @override
  Future<List<SurveyPhoto>> getPhotos(String ownerType, String ownerId) async {
    final list =
        _photos.values
            .where((p) => p.ownerType == ownerType && p.ownerId == ownerId)
            .toList()
          ..sort((a, b) {
            final bySlot = a.slot.compareTo(b.slot);
            return bySlot != 0 ? bySlot : a.position.compareTo(b.position);
          });
    return List.unmodifiable(list);
  }

  @override
  Future<void> setPhotos(
    String ownerType,
    String ownerId,
    List<SurveyPhoto> photos,
  ) async {
    final keepIds = photos.where((p) => p.id.isNotEmpty).map((p) => p.id).toSet();
    _photos.removeWhere((id, p) {
      final drop =
          p.ownerType == ownerType &&
          p.ownerId == ownerId &&
          !keepIds.contains(id);
      if (drop) _dirtyPhotoIds.remove(id);
      return drop;
    });
    for (final photo in photos) {
      if (photo.id.isEmpty) {
        final stored = photo.copyWithId(_idService.newId());
        _photos[stored.id] = stored;
        _dirtyPhotoIds.add(stored.id);
        continue;
      }
      // Re-saving the owner's form passes back every existing photo
      // unchanged — only re-dirty rows whose content actually differs.
      final existing = _photos[photo.id];
      if (existing != null && _photoUnchanged(existing, photo)) {
        continue;
      }
      _photos[photo.id] = photo;
      _dirtyPhotoIds.add(photo.id);
    }
  }

  @override
  Future<List<SurveyPhoto>> getAllPhotos({bool dirtyOnly = false}) async =>
      _photos.values
          .where((p) => !dirtyOnly || _dirtyPhotoIds.contains(p.id))
          .toList(growable: false);

  @override
  Future<void> updatePhoto(SurveyPhoto photo) async {
    _photos[photo.id] = photo;
    _dirtyPhotoIds.add(photo.id);
  }

  @override
  Future<void> markPhotoSynced(String id) async {
    _dirtyPhotoIds.remove(id);
  }

  @override
  Future<List<BomManualEntry>> getBomManualEntries(
    String surveyId, {
    bool dirtyOnly = false,
  }) async {
    final list =
        _bomManualEntries.values
            .where(
              (e) =>
                  e.surveyId == surveyId &&
                  !_pendingDeleteBomManualEntryIds.contains(e.id) &&
                  (!dirtyOnly || _dirtyBomManualEntryIds.contains(e.id)),
            )
            .toList()
          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return List.unmodifiable(list);
  }

  @override
  Future<BomManualEntry> addBomManualEntry(BomManualEntry entry) async {
    final stored = entry.copyWithId(_idService.newId());
    _bomManualEntries[stored.id] = stored;
    _dirtyBomManualEntryIds.add(stored.id);
    return stored;
  }

  @override
  Future<void> updateBomManualEntry(BomManualEntry entry) async {
    _bomManualEntries[entry.id] = entry;
    _dirtyBomManualEntryIds.add(entry.id);
  }

  @override
  Future<void> deleteBomManualEntry(String id) async {
    _pendingDeleteBomManualEntryIds.add(id);
    _dirtyBomManualEntryIds.add(id);
  }

  @override
  Future<List<String>> getPendingDeleteBomManualEntryIds(String surveyId) async =>
      _bomManualEntries.values
          .where(
            (e) =>
                e.surveyId == surveyId &&
                _pendingDeleteBomManualEntryIds.contains(e.id),
          )
          .map((e) => e.id)
          .toList(growable: false);

  @override
  Future<void> hardDeleteBomManualEntry(String id) async {
    _bomManualEntries.remove(id);
    _pendingDeleteBomManualEntryIds.remove(id);
    _dirtyBomManualEntryIds.remove(id);
  }

  @override
  Future<void> markBomManualEntrySynced(String id) async {
    _dirtyBomManualEntryIds.remove(id);
  }

  @override
  Future<void> upsertBomManualEntriesFromRemote(
    List<Map<String, dynamic>> remoteRows,
  ) async {
    _upsertFromRemoteById<BomManualEntry>(
      store: _bomManualEntries,
      dirtyIds: _dirtyBomManualEntryIds,
      pendingDeleteIds: _pendingDeleteBomManualEntryIds,
      remoteRows: remoteRows,
      fromRow: _bomManualEntryFromRemoteRow,
    );
  }

  @override
  Future<BomSnapshot?> getBomSnapshot(String surveyId) async =>
      _bomSnapshots[surveyId];

  @override
  Future<bool> isBomSnapshotDirty(String surveyId) async {
    final snapshot = _bomSnapshots[surveyId];
    return snapshot != null && _dirtyBomSnapshotIds.contains(snapshot.id);
  }

  @override
  Future<void> markBomSnapshotSynced(String id) async {
    _dirtyBomSnapshotIds.remove(id);
  }

  @override
  Future<List<BomSnapshotLine>> getBomSnapshotLines(
    String snapshotId, {
    bool dirtyOnly = false,
  }) async {
    final lines = _bomSnapshotLines[snapshotId] ?? const [];
    return List.unmodifiable(
      dirtyOnly
          ? lines.where((l) => _dirtyBomSnapshotLineIds.contains(l.id))
          : lines,
    );
  }

  @override
  Future<void> markBomSnapshotLineSynced(String id) async {
    _dirtyBomSnapshotLineIds.remove(id);
  }

  @override
  Future<BomSnapshot> finalizeBom({
    required String surveyId,
    required List<BomSnapshotLine> lines,
    required String finalizedBy,
  }) async {
    final existing = _bomSnapshots[surveyId];
    if (existing != null) return existing;

    final snapshot = BomSnapshot(
      id: _idService.newId(),
      surveyId: surveyId,
      finalizedBy: finalizedBy,
      finalizedAt: DateTime.now(),
    );
    _bomSnapshots[surveyId] = snapshot;
    _dirtyBomSnapshotIds.add(snapshot.id);
    _bomSnapshotLines[snapshot.id] = [
      for (final line in lines)
        line.copyWithIds(id: _idService.newId(), snapshotId: snapshot.id),
    ];
    for (final line in _bomSnapshotLines[snapshot.id]!) {
      _dirtyBomSnapshotLineIds.add(line.id);
    }

    final site = _sites[surveyId];
    if (site != null) {
      _sites[surveyId] = Site(
        id: site.id,
        name: site.name,
        blocks: site.blocks,
        clientInputs: site.clientInputs,
        status: site.status,
        assignedTo: site.assignedTo,
        bomLocked: true,
        archived: site.archived,
        address: site.address,
        clientName: site.clientName,
        clientContact: site.clientContact,
      );
      _dirtySiteIds.add(surveyId);
    }

    return snapshot;
  }

  @override
  Future<List<BomRevision>> getBomRevisions(
    String surveyId, {
    bool dirtyOnly = false,
  }) async {
    final list =
        _bomRevisions.values
            .where(
              (r) =>
                  r.surveyId == surveyId &&
                  (!dirtyOnly || _dirtyBomRevisionIds.contains(r.id)),
            )
            .toList()
          ..sort((a, b) => a.version.compareTo(b.version));
    return List.unmodifiable(list);
  }

  @override
  Future<void> markBomRevisionSynced(String id) async {
    _dirtyBomRevisionIds.remove(id);
  }

  @override
  Future<List<BomRevisionLine>> getBomRevisionLines(
    String revisionId, {
    bool dirtyOnly = false,
  }) async {
    final lines = _bomRevisionLines[revisionId] ?? const [];
    return List.unmodifiable(
      dirtyOnly
          ? lines.where((l) => _dirtyBomRevisionLineIds.contains(l.id))
          : lines,
    );
  }

  @override
  Future<void> markBomRevisionLineSynced(String id) async {
    _dirtyBomRevisionLineIds.remove(id);
  }

  @override
  Future<BomRevision> addBomRevision({
    required String surveyId,
    required String reason,
    required List<BomRevisionLine> lines,
    required String createdBy,
  }) async {
    final nextVersion = await _nextBomVersion(surveyId);

    final revision = BomRevision(
      id: _idService.newId(),
      surveyId: surveyId,
      version: nextVersion,
      reason: reason,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    _bomRevisions[revision.id] = revision;
    _dirtyBomRevisionIds.add(revision.id);
    _bomRevisionLines[revision.id] = [
      for (final line in lines)
        line.copyWithIds(id: _idService.newId(), revisionId: revision.id),
    ];
    for (final line in _bomRevisionLines[revision.id]!) {
      _dirtyBomRevisionLineIds.add(line.id);
    }

    return revision;
  }

  // ---- BoM manual-edit snapshots ------------------------------------------

  @override
  Future<List<BomManualEditSnapshot>> getBomManualEditSnapshots(
    String surveyId, {
    bool dirtyOnly = false,
  }) async {
    final list =
        _bomManualEditSnapshots.values
            .where(
              (s) =>
                  s.surveyId == surveyId &&
                  (!dirtyOnly || _dirtyBomManualEditSnapshotIds.contains(s.id)),
            )
            .toList()
          ..sort((a, b) => a.version.compareTo(b.version));
    return List.unmodifiable(list);
  }

  @override
  Future<void> markBomManualEditSnapshotSynced(String id) async {
    _dirtyBomManualEditSnapshotIds.remove(id);
  }

  @override
  Future<List<BomManualEditSnapshotLine>> getBomManualEditSnapshotLines(
    String snapshotId, {
    bool dirtyOnly = false,
  }) async {
    final lines = _bomManualEditSnapshotLines[snapshotId] ?? const [];
    return List.unmodifiable(
      dirtyOnly
          ? lines.where((l) => _dirtyBomManualEditSnapshotLineIds.contains(l.id))
          : lines,
    );
  }

  @override
  Future<void> markBomManualEditSnapshotLineSynced(String id) async {
    _dirtyBomManualEditSnapshotLineIds.remove(id);
  }

  @override
  Future<BomManualEditSnapshot> addBomManualEditSnapshot({
    required String surveyId,
    required int basedOnVersion,
    required String reason,
    required List<BomManualEditSnapshotLine> lines,
    required String editedBy,
  }) async {
    final nextVersion = await _nextBomVersion(surveyId);

    final snapshot = BomManualEditSnapshot(
      id: _idService.newId(),
      surveyId: surveyId,
      version: nextVersion,
      basedOnVersion: basedOnVersion,
      editedBy: editedBy,
      editedAt: DateTime.now(),
      reason: reason,
    );
    _bomManualEditSnapshots[snapshot.id] = snapshot;
    _dirtyBomManualEditSnapshotIds.add(snapshot.id);
    _bomManualEditSnapshotLines[snapshot.id] = [
      for (final line in lines)
        line.copyWithIds(id: _idService.newId(), snapshotId: snapshot.id),
    ];
    for (final line in _bomManualEditSnapshotLines[snapshot.id]!) {
      _dirtyBomManualEditSnapshotLineIds.add(line.id);
    }

    return snapshot;
  }

  /// Next version number for either a new [BomRevision] or a new
  /// [BomManualEditSnapshot] — both draw from the same counter. Mirrors
  /// SqfliteSurveyRepository's `_nextBomVersion`.
  Future<int> _nextBomVersion(String surveyId) async {
    final revisions = await getBomRevisions(surveyId);
    final manualEdits = await getBomManualEditSnapshots(surveyId);
    final versions = [
      1,
      for (final r in revisions) r.version,
      for (final m in manualEdits) m.version,
    ];
    return versions.reduce((a, b) => a > b ? a : b) + 1;
  }

  @override
  Future<List<Engineer>> getEngineers() async => List.unmodifiable(_engineers);

  @override
  Future<void> reassignSurvey({
    required String siteId,
    required String newAssignee,
    required String changedByRole,
  }) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot reassign: site "$siteId" not found.');
    }
    if (site.status != SurveyStatus.assigned) {
      throw StateError(
        'Cannot reassign: survey "$siteId" is not in "assigned" status '
        '(current: ${site.status ?? 'none'}).',
      );
    }

    final oldAssignee = site.assignedTo;
    _sites[siteId] = site.copyWith(assignedTo: newAssignee);
    _dirtySiteIds.add(siteId);

    final entry = SurveyAssignmentAuditEntry(
      id: _idService.newId(),
      siteId: siteId,
      oldAssignee: oldAssignee,
      newAssignee: newAssignee,
      changedByRole: changedByRole,
      changedAt: DateTime.now(),
    );
    _assignmentAudit[entry.id] = entry;
  }

  @override
  Future<List<SurveyAssignmentAuditEntry>> getSurveyAssignmentAuditLog(
    String siteId,
  ) async {
    final list =
        _assignmentAudit.values.where((e) => e.siteId == siteId).toList()
          ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return List.unmodifiable(list);
  }
}

bool _photoUnchanged(SurveyPhoto existing, SurveyPhoto updated) {
  return existing.ownerType == updated.ownerType &&
      existing.ownerId == updated.ownerId &&
      existing.slot == updated.slot &&
      existing.position == updated.position &&
      existing.localPath == updated.localPath &&
      existing.remotePath == updated.remotePath;
}

// ---- Pull-sync (Phase 1): raw remote row -> Dart model -----------------
//
// Same field/column mapping as SqfliteSurveyRepository's local `_xFromRow`
// functions — the only difference is booleans: Postgres returns a native
// bool, so these read `row['x'] as bool?` directly instead of converting
// from a local SQLite 0/1 int.

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

Set<WaterSource> _parseWaterSources(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final result = <WaterSource>{};
  for (final name in raw.split(',')) {
    final value = _enumByName(WaterSource.values, name);
    if (value != null) result.add(value);
  }
  return result;
}

Set<String> _splitStrings(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  return raw.split(',').where((s) => s.isNotEmpty).toSet();
}

/// Mirrors sqflite's `_materialGroupFromCode` — restricted to the D/E/G
/// range bom_manual_entries actually uses, falling back to D on anything
/// unrecognized.
MaterialGroup _materialGroupFromCode(String? code) {
  for (final group in kBomManualEntryGroups) {
    if (group.code == code) return group;
  }
  return MaterialGroup.d;
}

ClientInputs _clientInputsFromRemoteRow(Map<String, dynamic> r) {
  return ClientInputs(
    siteName: (r['site_name'] as String?) ?? '',
    informationSource: _enumByName(
      InformationSource.values,
      r['information_source'] as String?,
    ),
    clientPocName: (r['client_poc_name'] as String?) ?? '',
    clientPocContact: (r['client_poc_contact'] as String?) ?? '',
    goalOfInstallation: (r['goal_of_installation'] as String?) ?? '',
    waterSources: _parseWaterSources(r['water_sources'] as String?),
    ohtHns: _enumByName(OhtHns.values, r['oht_hns'] as String?),
    finalisedPlumbingDrawings: r['finalised_plumbing_drawings'] as bool?,
    pointsIdentified: r['points_identified'] as int?,
    maxAndContinuousPressure: (r['max_and_continuous_pressure'] as String?) ?? '',
    pressureBoosters: r['pressure_boosters'] as bool?,
    materialsAndBrandGuidelines:
        (r['materials_and_brand_guidelines'] as String?) ?? '',
    reworkRequired: r['rework_required'] as bool?,
    reworkDetails: (r['rework_details'] as String?) ?? '',
    ageOfPlumbingLines: (r['age_of_plumbing_lines'] as String?) ?? '',
    aestheticGuidelines: r['aesthetic_guidelines'] as bool?,
    aestheticDetails: (r['aesthetic_details'] as String?) ?? '',
  );
}

Footer _footerFromRemoteRow(Map<String, dynamic> r) {
  return Footer(
    tdsPpm: (r['tds_ppm'] as num?)?.toDouble(),
    tssPpm: (r['tss_ppm'] as num?)?.toDouble(),
    tclService: r['tcl_service'] as bool?,
    tclServiceDetails: (r['tcl_service_details'] as String?) ?? '',
    generalRemarks: (r['general_remarks'] as String?) ?? '',
    surveyDate: DateTime.tryParse((r['survey_date'] as String?) ?? ''),
    surveyorName: (r['surveyor_name'] as String?) ?? '',
  );
}

SourcePoint _sourcePointFromRemoteRow(Map<String, dynamic> r) {
  return SourcePoint(
    id: r['id'] as String,
    siteId: r['site_id'] as String,
    block: r['block'] as String?,
    apartment: (r['apartment'] as String?) ?? '',
    inletDescription: (r['inlet_description'] as String?) ?? '',
    materialId: r['material_id'] as String?,
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorOd: _enumByName(SensorOd.values, r['sensor_od'] as String?),
    pipeSize: _enumByName(PipeSize.values, r['pipe_size'] as String?),
    pipeType: _enumByName(PipeType.values, r['pipe_type'] as String?),
    qty: r['qty'] as int?,
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    rework: r['rework'] as bool?,
    reworkDetails: (r['rework_details'] as String?) ?? '',
    flowDirection: _enumByName(
      FlowDirection.values,
      r['flow_direction'] as String?,
    ),
    clearance10x: r['clearance_10x'] as bool?,
    pipeFull: r['pipe_full'] as bool?,
    valveDownstream: r['valve_downstream'] as bool?,
    reducerSpec: r['reducer_spec'] as bool?,
    reducerSpecDetails: (r['reducer_spec_details'] as String?) ?? '',
    downstreamOutletAbovePipeFig1: r['downstream_outlet_above_pipe_fig1'] as bool?,
    airVentNeededFig2: r['air_vent_needed_fig2'] as bool?,
    reverseFlow: r['reverse_flow'] as bool?,
    distanceFromMotorPumpFig3: r['distance_from_motor_pump_fig3'] as bool?,
    noFlexiblePipeWithin20x: r['no_flexible_pipe_within_20x'] as bool?,
    maxAndContinuousPressureBar:
        (r['max_and_continuous_pressure_bar'] as num?)?.toDouble(),
    strainerScreenFilter: r['strainer_screen_filter'] as bool?,
    chamberInstallation: r['chamber_installation'] as bool?,
    antennaRequired: r['antenna_required'] as bool?,
    transmittingPartOpenToAir: r['transmitting_part_open_to_air'] as bool?,
    nrvFeasibility: r['nrv_feasibility'] as bool?,
  );
}

InletPoint _inletPointFromRemoteRow(Map<String, dynamic> r) {
  return InletPoint(
    id: r['id'] as String,
    siteId: r['site_id'] as String,
    block: r['block'] as String?,
    apartmentBhk: (r['apartment_bhk'] as String?) ?? '',
    materialId: r['material_id'] as String?,
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    series: (r['series'] as String?) ?? '',
    sensorOd: _enumByName(SensorOd.values, r['sensor_od'] as String?),
    pipeSize: _enumByName(PipeSize.values, r['pipe_size'] as String?),
    pipeType: _enumByName(PipeType.values, r['pipe_type'] as String?),
    qty: r['qty'] as int?,
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    rework: r['rework'] as bool?,
    reworkDetails: (r['rework_details'] as String?) ?? '',
    linearDistanceClearance10x: r['linear_distance_clearance_10x'] as bool?,
    reverseFlow: r['reverse_flow'] as bool?,
    ohtHns: _enumByName(OhtHns.values, r['oht_hns'] as String?),
    distanceFromMotorPump: r['distance_from_motor_pump'] as bool?,
    maxAndContinuousPressureBar:
        (r['max_and_continuous_pressure_bar'] as num?)?.toDouble(),
    strainerScreenFilter: r['strainer_screen_filter'] as bool?,
    flowDirection: _enumByName(
      FlowDirection.values,
      r['flow_direction'] as String?,
    ),
    accessMode: _enumByName(AccessMode.values, r['access_mode'] as String?),
    cableRunLength: _enumByName(
      CableRunLength.values,
      r['cable_run_length'] as String?,
    ),
    conduitClamping: r['conduit_clamping'] as bool?,
    civilWorkNeeded: r['civil_work_needed'] as bool?,
    civilWorkDetails: (r['civil_work_details'] as String?) ?? '',
  );
}

DuctLora _ductLoraFromRemoteRow(Map<String, dynamic> r) {
  return DuctLora(
    id: r['id'] as String,
    siteId: r['site_id'] as String,
    block: r['block'] as String?,
    seriesServed: _splitStrings(r['series_served'] as String?),
    accessibleForService: r['accessible_for_service'] as bool?,
    rssiIfTcl: (r['rssi_if_tcl'] as num?)?.toDouble(),
    powerPointAvailableShielded: r['power_point_available_shielded'] as bool?,
    separateMcbForSeries: r['separate_mcb_for_series'] as bool?,
    upsPowerSupply: r['ups_power_supply'] as bool?,
    cableLength: (r['cable_length'] as num?)?.toDouble(),
  );
}

Gateway _gatewayFromRemoteRow(Map<String, dynamic> r) {
  return Gateway(
    id: r['id'] as String,
    siteId: r['site_id'] as String,
    placement: _enumByName(GatewayPlacement.values, r['placement'] as String?),
    locationDescription: (r['location_description'] as String?) ?? '',
    blocksCovered: _splitStrings(r['blocks_covered'] as String?),
    quantity: r['quantity'] as int?,
    uplinkType: _enumByName(UplinkType.values, r['uplink_type'] as String?),
    wifiInterferenceCheck: r['wifi_interference_check'] as bool?,
    wifiInterferenceDetails: (r['wifi_interference_details'] as String?) ?? '',
    simCoverage: _enumByName(SimCoverage.values, r['sim_coverage'] as String?),
    uninterruptedPowerSource: r['uninterrupted_power_source'] as bool?,
    mountingHardwareNeeded: (r['mounting_hardware_needed'] as String?) ?? '',
  );
}

BomManualEntry _bomManualEntryFromRemoteRow(Map<String, dynamic> r) {
  return BomManualEntry(
    id: r['id'] as String,
    surveyId: r['survey_id'] as String,
    materialName: (r['material_name'] as String?) ?? '',
    sku: (r['sku'] as String?) ?? '',
    itemLabel: (r['item_label'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    unit: (r['unit'] as String?) ?? '',
    qty: (r['qty'] as num?)?.toDouble() ?? 0,
    group: _materialGroupFromCode(r['group_code'] as String?),
    addedBy: (r['added_by'] as String?) ?? '',
    addedAt: DateTime.tryParse((r['added_at'] as String?) ?? '') ?? DateTime(1970),
  );
}
