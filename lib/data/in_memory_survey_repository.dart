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
  late final List<Engineer> _engineers;
  final Map<String, SurveyAssignmentAuditEntry> _assignmentAudit = {};

  @override
  Future<List<Site>> getSites() async => _sites.values.toList(growable: false);

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
    return site;
  }

  @override
  Future<void> updateSite(Site site) async {
    _sites[site.id] = site;
  }

  @override
  Future<void> updateSiteBlocks(String siteId, List<String> blocks) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot update blocks: site "$siteId" not found.');
    }
    _sites[siteId] = site.copyWith(blocks: List.unmodifiable(blocks));
  }

  @override
  Future<void> saveClientInputs(String siteId, ClientInputs inputs) async {
    final site = _sites[siteId];
    if (site == null) {
      throw StateError('Cannot save client inputs: site "$siteId" not found.');
    }
    _sites[siteId] = site.copyWith(clientInputs: inputs);
  }

  @override
  Future<List<SourcePoint>> getSourcePoints(String siteId) async => _sourcePoints
      .values
      .where((sp) => sp.siteId == siteId)
      .toList(growable: false);

  @override
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint) async {
    final stored = sourcePoint.copyWithId(_idService.newId());
    _sourcePoints[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateSourcePoint(SourcePoint sourcePoint) async {
    _sourcePoints[sourcePoint.id] = sourcePoint;
  }

  @override
  Future<void> deleteSourcePoint(String id) async {
    _sourcePoints.remove(id);
  }

  @override
  Future<List<InletPoint>> getInletPoints(String siteId) async => _inletPoints
      .values
      .where((ip) => ip.siteId == siteId)
      .toList(growable: false);

  @override
  Future<InletPoint> addInletPoint(InletPoint inletPoint) async {
    final stored = inletPoint.copyWithId(_idService.newId());
    _inletPoints[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateInletPoint(InletPoint inletPoint) async {
    _inletPoints[inletPoint.id] = inletPoint;
  }

  @override
  Future<void> deleteInletPoint(String id) async {
    _inletPoints.remove(id);
  }

  @override
  Future<List<DuctLora>> getDuctLoras(String siteId) async => _ductLoras.values
      .where((d) => d.siteId == siteId)
      .toList(growable: false);

  @override
  Future<DuctLora> addDuctLora(DuctLora ductLora) async {
    final stored = ductLora.copyWithId(_idService.newId());
    _ductLoras[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateDuctLora(DuctLora ductLora) async {
    _ductLoras[ductLora.id] = ductLora;
  }

  @override
  Future<void> deleteDuctLora(String id) async {
    _ductLoras.remove(id);
  }

  @override
  Future<List<Gateway>> getGateways(String siteId) async => _gateways.values
      .where((g) => g.siteId == siteId)
      .toList(growable: false);

  @override
  Future<Gateway> addGateway(Gateway gateway) async {
    final stored = gateway.copyWithId(_idService.newId());
    _gateways[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateGateway(Gateway gateway) async {
    _gateways[gateway.id] = gateway;
  }

  @override
  Future<void> deleteGateway(String id) async {
    _gateways.remove(id);
  }

  @override
  Future<Footer?> getFooter(String siteId) async => _footers[siteId];

  @override
  Future<void> saveFooter(String siteId, Footer footer) async {
    if (!_sites.containsKey(siteId)) {
      throw StateError('Cannot save footer: site "$siteId" not found.');
    }
    _footers[siteId] = footer;
  }

  @override
  Future<List<MaterialMasterItem>> getMaterialMasterItems() async =>
      _materialMasterItems.values.toList(growable: false);

  @override
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  }) async {
    final stored = item.copyWithId(_idService.newId());
    _materialMasterItems[stored.id] = stored;
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
  Future<List<MaterialMasterAuditEntry>> getMaterialMasterAuditLog() async {
    final list = _materialMasterAudit.values.toList()
      ..sort((a, b) => b.changedAt.compareTo(a.changedAt));
    return List.unmodifiable(list);
  }

  void _writeAudit(List<MaterialMasterAuditEntry> entries) {
    for (final entry in entries) {
      final stored = entry.copyWithId(_idService.newId());
      _materialMasterAudit[stored.id] = stored;
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
    _photos.removeWhere(
      (id, p) =>
          p.ownerType == ownerType &&
          p.ownerId == ownerId &&
          !keepIds.contains(id),
    );
    for (final photo in photos) {
      if (photo.id.isEmpty) {
        final stored = photo.copyWithId(_idService.newId());
        _photos[stored.id] = stored;
      } else {
        _photos[photo.id] = photo;
      }
    }
  }

  @override
  Future<List<SurveyPhoto>> getAllPhotos() async =>
      _photos.values.toList(growable: false);

  @override
  Future<void> updatePhoto(SurveyPhoto photo) async {
    _photos[photo.id] = photo;
  }

  @override
  Future<List<BomManualEntry>> getBomManualEntries(String surveyId) async {
    final list =
        _bomManualEntries.values.where((e) => e.surveyId == surveyId).toList()
          ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return List.unmodifiable(list);
  }

  @override
  Future<BomManualEntry> addBomManualEntry(BomManualEntry entry) async {
    final stored = entry.copyWithId(_idService.newId());
    _bomManualEntries[stored.id] = stored;
    return stored;
  }

  @override
  Future<void> updateBomManualEntry(BomManualEntry entry) async {
    _bomManualEntries[entry.id] = entry;
  }

  @override
  Future<void> deleteBomManualEntry(String id) async {
    _bomManualEntries.remove(id);
  }

  @override
  Future<BomSnapshot?> getBomSnapshot(String surveyId) async =>
      _bomSnapshots[surveyId];

  @override
  Future<List<BomSnapshotLine>> getBomSnapshotLines(String snapshotId) async =>
      List.unmodifiable(_bomSnapshotLines[snapshotId] ?? const []);

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
    _bomSnapshotLines[snapshot.id] = [
      for (final line in lines)
        line.copyWithIds(id: _idService.newId(), snapshotId: snapshot.id),
    ];

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
      );
    }

    return snapshot;
  }

  @override
  Future<List<BomRevision>> getBomRevisions(String surveyId) async {
    final list =
        _bomRevisions.values.where((r) => r.surveyId == surveyId).toList()
          ..sort((a, b) => a.version.compareTo(b.version));
    return List.unmodifiable(list);
  }

  @override
  Future<List<BomRevisionLine>> getBomRevisionLines(String revisionId) async =>
      List.unmodifiable(_bomRevisionLines[revisionId] ?? const []);

  @override
  Future<BomRevision> addBomRevision({
    required String surveyId,
    required String reason,
    required List<BomRevisionLine> lines,
    required String createdBy,
  }) async {
    final existingVersions = await getBomRevisions(surveyId);
    final nextVersion = existingVersions.isEmpty
        ? 2
        : existingVersions.map((r) => r.version).reduce((a, b) => a > b ? a : b) + 1;

    final revision = BomRevision(
      id: _idService.newId(),
      surveyId: surveyId,
      version: nextVersion,
      reason: reason,
      createdBy: createdBy,
      createdAt: DateTime.now(),
    );
    _bomRevisions[revision.id] = revision;
    _bomRevisionLines[revision.id] = [
      for (final line in lines)
        line.copyWithIds(id: _idService.newId(), revisionId: revision.id),
    ];

    return revision;
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
