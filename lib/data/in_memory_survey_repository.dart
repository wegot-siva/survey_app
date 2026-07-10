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
  final Set<String> _dirtyDuctLoraIds = {};
  final Set<String> _dirtyGatewayIds = {};
  final Set<String> _dirtyFooterSiteIds = {};
  final Set<String> _dirtyMaterialMasterItemIds = {};
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
  Future<List<DuctLora>> getDuctLoras(
    String siteId, {
    bool dirtyOnly = false,
  }) async => _ductLoras.values
      .where(
        (d) =>
            d.siteId == siteId &&
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
    _ductLoras.remove(id);
    _dirtyDuctLoraIds.remove(id);
  }

  @override
  Future<void> markDuctLoraSynced(String id) async {
    _dirtyDuctLoraIds.remove(id);
  }

  @override
  Future<List<Gateway>> getGateways(
    String siteId, {
    bool dirtyOnly = false,
  }) async => _gateways.values
      .where(
        (g) =>
            g.siteId == siteId &&
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
    _gateways.remove(id);
    _dirtyGatewayIds.remove(id);
  }

  @override
  Future<void> markGatewaySynced(String id) async {
    _dirtyGatewayIds.remove(id);
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
  Future<List<MaterialMasterItem>> getMaterialMasterItems({
    bool dirtyOnly = false,
  }) async => _materialMasterItems.values
      .where((m) => !dirtyOnly || _dirtyMaterialMasterItemIds.contains(m.id))
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
    final existing = _materialMasterItems.remove(id);
    _dirtyMaterialMasterItemIds.remove(id);
    if (existing != null) {
      _writeAudit(
        _auditBuilder.forDelete(
          item: existing,
          changedByRole: changedByRole,
          changedAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<void> markMaterialMasterItemSynced(String id) async {
    _dirtyMaterialMasterItemIds.remove(id);
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
    _bomManualEntries.remove(id);
    _dirtyBomManualEntryIds.remove(id);
  }

  @override
  Future<void> markBomManualEntrySynced(String id) async {
    _dirtyBomManualEntryIds.remove(id);
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
