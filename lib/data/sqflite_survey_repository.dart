import 'package:sqflite/sqflite.dart';

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
import '../models/survey_options.dart';
import '../models/survey_photo.dart';
import '../models/survey_status.dart';
import '../services/id_service.dart';
import '../services/material_master_audit_builder.dart';
import 'survey_repository.dart';

const _materialMasterAuditBuilder = MaterialMasterAuditBuilder();

/// SQLite-backed [SurveyRepository]. Data survives app restarts.
///
/// Sits behind the same interface as the in-memory stub, so no UI code changes.
/// Blocks are stored as ordered rows; client inputs as one row per site.
class SqfliteSurveyRepository implements SurveyRepository {
  SqfliteSurveyRepository(this._db, this._idService);

  final Database _db;
  final IdService _idService;

  @override
  Future<List<Site>> getSites({
    bool includeArchived = false,
    bool dirtyOnly = false,
  }) async {
    final conditions = <String>[
      if (!includeArchived) 'archived = 0',
      if (dirtyOnly) 'dirty = 1',
    ];
    final rows = await _db.query(
      'sites',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      orderBy: 'name COLLATE NOCASE',
    );
    final sites = <Site>[];
    for (final row in rows) {
      sites.add(await _hydrate(row));
    }
    return sites;
  }

  @override
  Future<Site?> getSiteById(String id) async {
    final rows = await _db.query(
      'sites',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _hydrate(rows.first);
  }

  @override
  Future<Site> createSite({
    required String name,
    List<String> blocks = const [],
  }) async {
    final id = _idService.newId();
    await _db.transaction((txn) async {
      await txn.insert('sites', {'id': id, 'name': name, 'dirty': 1});
      await _writeBlocks(txn, id, blocks);
    });
    return Site(id: id, name: name, blocks: List.unmodifiable(blocks));
  }

  @override
  Future<void> updateSite(Site site) async {
    await _db.transaction((txn) async {
      await txn.update(
        'sites',
        {
          'name': site.name,
          'status': site.status,
          'assigned_to': site.assignedTo,
          'archived': site.archived ? 1 : 0,
          'address': site.address,
          'client_name': site.clientName,
          'client_contact': site.clientContact,
          'dirty': 1,
        },
        where: 'id = ?',
        whereArgs: [site.id],
      );
      await txn.delete('blocks', where: 'site_id = ?', whereArgs: [site.id]);
      await _writeBlocks(txn, site.id, site.blocks);

      final inputs = site.clientInputs;
      if (inputs == null) {
        await txn.delete(
          'client_inputs',
          where: 'site_id = ?',
          whereArgs: [site.id],
        );
      } else {
        await txn.insert(
          'client_inputs',
          _inputsToRow(site.id, inputs),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> updateSiteBlocks(String siteId, List<String> blocks) async {
    await _db.transaction((txn) async {
      await txn.delete('blocks', where: 'site_id = ?', whereArgs: [siteId]);
      await _writeBlocks(txn, siteId, blocks);
    });
  }

  @override
  Future<void> saveClientInputs(String siteId, ClientInputs inputs) async {
    // Relies on the FK constraint to reject inputs for a non-existent site.
    await _db.insert(
      'client_inputs',
      _inputsToRow(siteId, inputs),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> isClientInputsDirty(String siteId) async {
    final rows = await _db.query(
      'client_inputs',
      columns: ['site_id'],
      where: 'site_id = ? AND dirty = 1',
      whereArgs: [siteId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markSiteSynced(String siteId) async {
    await _db.update(
      'sites',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [siteId],
    );
  }

  @override
  Future<void> markClientInputsSynced(String siteId) async {
    await _db.update(
      'client_inputs',
      {'dirty': 0},
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
  }

  // ---- Helpers --------------------------------------------------------------

  Future<void> _writeBlocks(
    DatabaseExecutor txn,
    String siteId,
    List<String> blocks,
  ) async {
    for (var i = 0; i < blocks.length; i++) {
      await txn.insert('blocks', {
        'site_id': siteId,
        'position': i,
        'label': blocks[i],
      });
    }
  }

  Future<Site> _hydrate(Map<String, Object?> siteRow) async {
    final id = siteRow['id']! as String;

    final blockRows = await _db.query(
      'blocks',
      columns: ['label'],
      where: 'site_id = ?',
      whereArgs: [id],
      orderBy: 'position',
    );
    final blocks = blockRows
        .map((r) => r['label']! as String)
        .toList(growable: false);

    final inputRows = await _db.query(
      'client_inputs',
      where: 'site_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final clientInputs = inputRows.isEmpty
        ? null
        : _inputsFromRow(inputRows.first);

    return Site(
      id: id,
      name: siteRow['name']! as String,
      blocks: blocks,
      clientInputs: clientInputs,
      status: siteRow['status'] as String?,
      assignedTo: siteRow['assigned_to'] as String?,
      bomLocked: _intToBool(siteRow['bom_locked'] as int?) ?? false,
      archived: _intToBool(siteRow['archived'] as int?) ?? false,
      address: siteRow['address'] as String? ?? '',
      clientName: siteRow['client_name'] as String? ?? '',
      clientContact: siteRow['client_contact'] as String? ?? '',
    );
  }

  // ---- Source points --------------------------------------------------------

  @override
  Future<List<SourcePoint>> getSourcePoints(
    String siteId, {
    bool dirtyOnly = false,
  }) async {
    final conditions = <String>[
      'site_id = ?',
      'pending_delete = 0',
      if (dirtyOnly) 'dirty = 1',
    ];
    final rows = await _db.query(
      'source_points',
      where: conditions.join(' AND '),
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_sourcePointFromRow).toList(growable: false);
  }

  @override
  Future<SourcePoint> addSourcePoint(SourcePoint sourcePoint) async {
    final stored = sourcePoint.copyWithId(_idService.newId());
    await _db.insert('source_points', _sourcePointToRow(stored));
    return stored;
  }

  @override
  Future<void> updateSourcePoint(SourcePoint sourcePoint) async {
    await _db.update(
      'source_points',
      _sourcePointToRow(sourcePoint),
      where: 'id = ?',
      whereArgs: [sourcePoint.id],
    );
  }

  @override
  Future<void> deleteSourcePoint(String id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'source_points',
        {'pending_delete': 1, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'photos',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: [PhotoOwner.sourcePoint, id],
      );
    });
  }

  @override
  Future<List<String>> getPendingDeleteSourcePointIds(String siteId) async {
    final rows = await _db.query(
      'source_points',
      columns: ['id'],
      where: 'site_id = ? AND pending_delete = 1',
      whereArgs: [siteId],
    );
    return rows.map((r) => r['id']! as String).toList(growable: false);
  }

  @override
  Future<void> hardDeleteSourcePoint(String id) async {
    await _db.delete('source_points', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markSourcePointSynced(String id) async {
    await _db.update(
      'source_points',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- Inlet points ---------------------------------------------------------

  @override
  Future<List<InletPoint>> getInletPoints(
    String siteId, {
    bool dirtyOnly = false,
  }) async {
    final conditions = <String>[
      'site_id = ?',
      'pending_delete = 0',
      if (dirtyOnly) 'dirty = 1',
    ];
    final rows = await _db.query(
      'inlet_points',
      where: conditions.join(' AND '),
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_inletPointFromRow).toList(growable: false);
  }

  @override
  Future<InletPoint> addInletPoint(InletPoint inletPoint) async {
    final stored = inletPoint.copyWithId(_idService.newId());
    await _db.insert('inlet_points', _inletPointToRow(stored));
    return stored;
  }

  @override
  Future<void> updateInletPoint(InletPoint inletPoint) async {
    await _db.update(
      'inlet_points',
      _inletPointToRow(inletPoint),
      where: 'id = ?',
      whereArgs: [inletPoint.id],
    );
  }

  @override
  Future<void> deleteInletPoint(String id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'inlet_points',
        {'pending_delete': 1, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'photos',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: [PhotoOwner.inletPoint, id],
      );
    });
  }

  @override
  Future<List<String>> getPendingDeleteInletPointIds(String siteId) async {
    final rows = await _db.query(
      'inlet_points',
      columns: ['id'],
      where: 'site_id = ? AND pending_delete = 1',
      whereArgs: [siteId],
    );
    return rows.map((r) => r['id']! as String).toList(growable: false);
  }

  @override
  Future<void> hardDeleteInletPoint(String id) async {
    await _db.delete('inlet_points', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markInletPointSynced(String id) async {
    await _db.update(
      'inlet_points',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- Duct LoRa units ------------------------------------------------------

  @override
  Future<List<DuctLora>> getDuctLoras(
    String siteId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'duct_loras',
      where: dirtyOnly ? 'site_id = ? AND dirty = 1' : 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_ductLoraFromRow).toList(growable: false);
  }

  @override
  Future<DuctLora> addDuctLora(DuctLora ductLora) async {
    final stored = ductLora.copyWithId(_idService.newId());
    await _db.insert('duct_loras', _ductLoraToRow(stored));
    return stored;
  }

  @override
  Future<void> updateDuctLora(DuctLora ductLora) async {
    await _db.update(
      'duct_loras',
      _ductLoraToRow(ductLora),
      where: 'id = ?',
      whereArgs: [ductLora.id],
    );
  }

  @override
  Future<void> deleteDuctLora(String id) async {
    await _db.delete('duct_loras', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markDuctLoraSynced(String id) async {
    await _db.update(
      'duct_loras',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- Gateways -------------------------------------------------------------

  @override
  Future<List<Gateway>> getGateways(
    String siteId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'gateways',
      where: dirtyOnly ? 'site_id = ? AND dirty = 1' : 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'rowid',
    );
    return rows.map(_gatewayFromRow).toList(growable: false);
  }

  @override
  Future<Gateway> addGateway(Gateway gateway) async {
    final stored = gateway.copyWithId(_idService.newId());
    await _db.insert('gateways', _gatewayToRow(stored));
    return stored;
  }

  @override
  Future<void> updateGateway(Gateway gateway) async {
    await _db.update(
      'gateways',
      _gatewayToRow(gateway),
      where: 'id = ?',
      whereArgs: [gateway.id],
    );
  }

  @override
  Future<void> deleteGateway(String id) async {
    await _db.delete('gateways', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markGatewaySynced(String id) async {
    await _db.update(
      'gateways',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- Footer (one per site) ------------------------------------------------

  @override
  Future<Footer?> getFooter(String siteId) async {
    final rows = await _db.query(
      'footers',
      where: 'site_id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _footerFromRow(rows.first);
  }

  @override
  Future<void> saveFooter(String siteId, Footer footer) async {
    // Relies on the FK constraint to reject a footer for a non-existent site.
    await _db.insert(
      'footers',
      _footerToRow(siteId, footer),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> isFooterDirty(String siteId) async {
    final rows = await _db.query(
      'footers',
      columns: ['site_id'],
      where: 'site_id = ? AND dirty = 1',
      whereArgs: [siteId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markFooterSynced(String siteId) async {
    await _db.update(
      'footers',
      {'dirty': 0},
      where: 'site_id = ?',
      whereArgs: [siteId],
    );
  }

  // ---- Material Master --------------------------------------------------

  @override
  Future<List<MaterialMasterItem>> getMaterialMasterItems({
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'material_master_items',
      where: dirtyOnly ? 'dirty = 1' : null,
      orderBy: 'rowid',
    );
    return rows.map(_materialMasterItemFromRow).toList(growable: false);
  }

  @override
  Future<MaterialMasterItem> addMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  }) async {
    final stored = item.copyWithId(_idService.newId());
    await _db.transaction((txn) async {
      await txn.insert('material_master_items', _materialMasterItemToRow(stored));
      await _writeMaterialMasterAudit(
        txn,
        _materialMasterAuditBuilder.forCreate(
          item: stored,
          changedByRole: changedByRole,
          changedAt: DateTime.now(),
        ),
      );
    });
    return stored;
  }

  @override
  Future<void> updateMaterialMasterItem(
    MaterialMasterItem item, {
    required String changedByRole,
  }) async {
    await _db.transaction((txn) async {
      final existingRows = await txn.query(
        'material_master_items',
        where: 'id = ?',
        whereArgs: [item.id],
        limit: 1,
      );
      await txn.update(
        'material_master_items',
        _materialMasterItemToRow(item),
        where: 'id = ?',
        whereArgs: [item.id],
      );
      if (existingRows.isNotEmpty) {
        final existing = _materialMasterItemFromRow(existingRows.first);
        await _writeMaterialMasterAudit(
          txn,
          _materialMasterAuditBuilder.forUpdate(
            oldItem: existing,
            newItem: item,
            changedByRole: changedByRole,
            changedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  @override
  Future<void> deleteMaterialMasterItem(
    String id, {
    required String changedByRole,
  }) async {
    await _db.transaction((txn) async {
      final existingRows = await txn.query(
        'material_master_items',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      await txn.delete('material_master_items', where: 'id = ?', whereArgs: [id]);
      if (existingRows.isNotEmpty) {
        final existing = _materialMasterItemFromRow(existingRows.first);
        await _writeMaterialMasterAudit(
          txn,
          _materialMasterAuditBuilder.forDelete(
            item: existing,
            changedByRole: changedByRole,
            changedAt: DateTime.now(),
          ),
        );
      }
    });
  }

  @override
  Future<void> markMaterialMasterItemSynced(String id) async {
    await _db.update(
      'material_master_items',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> upsertMaterialMasterItemsFromRemote(
    List<MaterialMasterItem> remoteItems,
  ) async {
    await _db.transaction((txn) async {
      for (final item in remoteItems) {
        final existingRows = await txn.query(
          'material_master_items',
          columns: ['dirty'],
          where: 'id = ?',
          whereArgs: [item.id],
          limit: 1,
        );
        if (existingRows.isNotEmpty &&
            (existingRows.first['dirty'] as int?) == 1) {
          continue; // Unsynced local edit — leave it, don't clobber.
        }
        await txn.insert(
          'material_master_items',
          {..._materialMasterItemToRow(item), 'dirty': 0},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<MaterialMasterAuditEntry>> getMaterialMasterAuditLog({
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'material_master_audit',
      where: dirtyOnly ? 'dirty = 1' : null,
      orderBy: 'changed_at DESC, rowid DESC',
    );
    return rows.map(_materialMasterAuditEntryFromRow).toList(growable: false);
  }

  @override
  Future<void> markMaterialMasterAuditEntrySynced(String id) async {
    await _db.update(
      'material_master_audit',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _writeMaterialMasterAudit(
    DatabaseExecutor txn,
    List<MaterialMasterAuditEntry> entries,
  ) async {
    for (final entry in entries) {
      final stored = entry.copyWithId(_idService.newId());
      await txn.insert('material_master_audit', _materialMasterAuditEntryToRow(stored));
    }
  }

  // ---- Photos (polymorphic, slot-based) -------------------------------------

  @override
  Future<List<SurveyPhoto>> getPhotos(String ownerType, String ownerId) async {
    final rows = await _db.query(
      'photos',
      where: 'owner_type = ? AND owner_id = ?',
      whereArgs: [ownerType, ownerId],
      orderBy: 'slot, position, rowid',
    );
    return rows.map(_photoFromRow).toList(growable: false);
  }

  @override
  Future<void> setPhotos(
    String ownerType,
    String ownerId,
    List<SurveyPhoto> photos,
  ) async {
    await _db.transaction((txn) async {
      final existingRows = await txn.query(
        'photos',
        where: 'owner_type = ? AND owner_id = ?',
        whereArgs: [ownerType, ownerId],
      );
      final existingById = {
        for (final row in existingRows) row['id'] as String: row,
      };

      final keepIds = photos
          .where((p) => p.id.isNotEmpty)
          .map((p) => p.id)
          .toList();
      // Delete any existing rows for this owner that aren't in the kept set.
      final placeholders = List.filled(keepIds.length, '?').join(', ');
      await txn.delete(
        'photos',
        where: keepIds.isEmpty
            ? 'owner_type = ? AND owner_id = ?'
            : 'owner_type = ? AND owner_id = ? AND id NOT IN ($placeholders)',
        whereArgs: [ownerType, ownerId, ...keepIds],
      );
      for (final photo in photos) {
        if (photo.id.isEmpty) {
          await txn.insert(
            'photos',
            _photoToRow(photo.copyWithId(_idService.newId())),
          );
          continue;
        }
        // Re-saving the owner's form (e.g. a text field edit) passes back
        // every existing photo unchanged — only touch (and re-dirty) rows
        // whose actual content differs, so untouched photos don't get
        // re-queued for sync.
        final existing = existingById[photo.id];
        final newRow = _photoToRow(photo);
        if (existing != null && _photoRowUnchanged(existing, newRow)) {
          continue;
        }
        await txn.update(
          'photos',
          newRow,
          where: 'id = ?',
          whereArgs: [photo.id],
        );
      }
    });
  }

  @override
  Future<List<SurveyPhoto>> getAllPhotos({bool dirtyOnly = false}) async {
    final rows = await _db.query(
      'photos',
      where: dirtyOnly ? 'dirty = 1' : null,
      orderBy: 'rowid',
    );
    return rows.map(_photoFromRow).toList(growable: false);
  }

  @override
  Future<void> updatePhoto(SurveyPhoto photo) async {
    await _db.update(
      'photos',
      _photoToRow(photo),
      where: 'id = ?',
      whereArgs: [photo.id],
    );
  }

  @override
  Future<void> markPhotoSynced(String id) async {
    await _db.update(
      'photos',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- BoM manual entries ----------------------------------------------

  @override
  Future<List<BomManualEntry>> getBomManualEntries(
    String surveyId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'bom_manual_entries',
      where: dirtyOnly ? 'survey_id = ? AND dirty = 1' : 'survey_id = ?',
      whereArgs: [surveyId],
      orderBy: 'added_at, rowid',
    );
    return rows.map(_bomManualEntryFromRow).toList(growable: false);
  }

  @override
  Future<BomManualEntry> addBomManualEntry(BomManualEntry entry) async {
    final stored = entry.copyWithId(_idService.newId());
    await _db.insert('bom_manual_entries', _bomManualEntryToRow(stored));
    return stored;
  }

  @override
  Future<void> updateBomManualEntry(BomManualEntry entry) async {
    await _db.update(
      'bom_manual_entries',
      _bomManualEntryToRow(entry),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  @override
  Future<void> deleteBomManualEntry(String id) async {
    await _db.delete('bom_manual_entries', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> markBomManualEntrySynced(String id) async {
    await _db.update(
      'bom_manual_entries',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---- BoM snapshots ---------------------------------------------------

  @override
  Future<BomSnapshot?> getBomSnapshot(String surveyId) async {
    final rows = await _db.query(
      'bom_snapshots',
      where: 'survey_id = ?',
      whereArgs: [surveyId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _bomSnapshotFromRow(rows.first);
  }

  @override
  Future<bool> isBomSnapshotDirty(String surveyId) async {
    final rows = await _db.query(
      'bom_snapshots',
      columns: ['id'],
      where: 'survey_id = ? AND dirty = 1',
      whereArgs: [surveyId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markBomSnapshotSynced(String id) async {
    await _db.update(
      'bom_snapshots',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<BomSnapshotLine>> getBomSnapshotLines(
    String snapshotId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'bom_snapshot_lines',
      where: dirtyOnly
          ? 'snapshot_id = ? AND dirty = 1'
          : 'snapshot_id = ?',
      whereArgs: [snapshotId],
      orderBy: 'group_code, rowid',
    );
    return rows.map(_bomSnapshotLineFromRow).toList(growable: false);
  }

  @override
  Future<void> markBomSnapshotLineSynced(String id) async {
    await _db.update(
      'bom_snapshot_lines',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<BomSnapshot> finalizeBom({
    required String surveyId,
    required List<BomSnapshotLine> lines,
    required String finalizedBy,
  }) async {
    // Idempotent: a survey can only ever have one snapshot in this slice —
    // guards against a double-tap (or any future caller) creating a duplicate.
    final existing = await getBomSnapshot(surveyId);
    if (existing != null) return existing;

    final snapshot = BomSnapshot(
      id: _idService.newId(),
      surveyId: surveyId,
      finalizedBy: finalizedBy,
      finalizedAt: DateTime.now(),
    );

    await _db.transaction((txn) async {
      await txn.insert('bom_snapshots', _bomSnapshotToRow(snapshot));
      for (final line in lines) {
        final stored = line.copyWithIds(
          id: _idService.newId(),
          snapshotId: snapshot.id,
        );
        await txn.insert('bom_snapshot_lines', _bomSnapshotLineToRow(stored));
      }
      await txn.update(
        'sites',
        {'bom_locked': 1, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [surveyId],
      );
    });

    return snapshot;
  }

  // ---- BoM revisions ----------------------------------------------------

  @override
  Future<List<BomRevision>> getBomRevisions(
    String surveyId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'bom_revisions',
      where: dirtyOnly ? 'survey_id = ? AND dirty = 1' : 'survey_id = ?',
      whereArgs: [surveyId],
      orderBy: 'version',
    );
    return rows.map(_bomRevisionFromRow).toList(growable: false);
  }

  @override
  Future<void> markBomRevisionSynced(String id) async {
    await _db.update(
      'bom_revisions',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<BomRevisionLine>> getBomRevisionLines(
    String revisionId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'bom_revision_lines',
      where: dirtyOnly
          ? 'revision_id = ? AND dirty = 1'
          : 'revision_id = ?',
      whereArgs: [revisionId],
      orderBy: 'group_code, rowid',
    );
    return rows.map(_bomRevisionLineFromRow).toList(growable: false);
  }

  @override
  Future<void> markBomRevisionLineSynced(String id) async {
    await _db.update(
      'bom_revision_lines',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
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

    await _db.transaction((txn) async {
      await txn.insert('bom_revisions', _bomRevisionToRow(revision));
      for (final line in lines) {
        final stored = line.copyWithIds(
          id: _idService.newId(),
          revisionId: revision.id,
        );
        await txn.insert('bom_revision_lines', _bomRevisionLineToRow(stored));
      }
    });

    return revision;
  }

  // ---- BoM manual-edit snapshots -----------------------------------------

  @override
  Future<List<BomManualEditSnapshot>> getBomManualEditSnapshots(
    String surveyId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'bom_manual_edit_snapshots',
      where: dirtyOnly ? 'survey_id = ? AND dirty = 1' : 'survey_id = ?',
      whereArgs: [surveyId],
      orderBy: 'version',
    );
    return rows.map(_bomManualEditSnapshotFromRow).toList(growable: false);
  }

  @override
  Future<void> markBomManualEditSnapshotSynced(String id) async {
    await _db.update(
      'bom_manual_edit_snapshots',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<BomManualEditSnapshotLine>> getBomManualEditSnapshotLines(
    String snapshotId, {
    bool dirtyOnly = false,
  }) async {
    final rows = await _db.query(
      'bom_manual_edit_snapshot_lines',
      where: dirtyOnly
          ? 'snapshot_id = ? AND dirty = 1'
          : 'snapshot_id = ?',
      whereArgs: [snapshotId],
      orderBy: 'group_code, rowid',
    );
    return rows.map(_bomManualEditSnapshotLineFromRow).toList(growable: false);
  }

  @override
  Future<void> markBomManualEditSnapshotLineSynced(String id) async {
    await _db.update(
      'bom_manual_edit_snapshot_lines',
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
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

    await _db.transaction((txn) async {
      await txn.insert(
        'bom_manual_edit_snapshots',
        _bomManualEditSnapshotToRow(snapshot),
      );
      for (final line in lines) {
        final stored = line.copyWithIds(
          id: _idService.newId(),
          snapshotId: snapshot.id,
        );
        await txn.insert(
          'bom_manual_edit_snapshot_lines',
          _bomManualEditSnapshotLineToRow(stored),
        );
      }
    });

    return snapshot;
  }

  /// Next version number for either a new [BomRevision] or a new
  /// [BomManualEditSnapshot] — both draw from the same counter (the survey's
  /// highest existing version across both tables, or 1 if neither has any
  /// rows yet, since v1 is always the original [BomSnapshot]), so a version
  /// number is never reused regardless of which table creates it.
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

  // ---- Engineer roster + survey reassignment -------------------------------

  @override
  Future<List<Engineer>> getEngineers() async {
    final rows = await _db.query('engineers', orderBy: 'name COLLATE NOCASE');
    return rows
        .map((r) => Engineer(id: r['id']! as String, name: r['name']! as String))
        .toList(growable: false);
  }

  @override
  Future<void> reassignSurvey({
    required String siteId,
    required String newAssignee,
    required String changedByRole,
  }) async {
    final rows = await _db.query(
      'sites',
      columns: ['assigned_to', 'status'],
      where: 'id = ?',
      whereArgs: [siteId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Cannot reassign: site "$siteId" not found.');
    }
    final oldAssignee = rows.first['assigned_to'] as String?;
    final status = rows.first['status'] as String?;
    if (status != SurveyStatus.assigned) {
      throw StateError(
        'Cannot reassign: survey "$siteId" is not in "assigned" status '
        '(current: ${status ?? 'none'}).',
      );
    }

    await _db.transaction((txn) async {
      await txn.update(
        'sites',
        {'assigned_to': newAssignee, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [siteId],
      );
      await txn.insert('survey_assignment_audit', {
        'id': _idService.newId(),
        'site_id': siteId,
        'old_assignee': oldAssignee,
        'new_assignee': newAssignee,
        'changed_by_role': changedByRole,
        'changed_at': DateTime.now().toIso8601String(),
      });
    });
  }

  @override
  Future<List<SurveyAssignmentAuditEntry>> getSurveyAssignmentAuditLog(
    String siteId,
  ) async {
    final rows = await _db.query(
      'survey_assignment_audit',
      where: 'site_id = ?',
      whereArgs: [siteId],
      orderBy: 'changed_at DESC, rowid DESC',
    );
    return rows.map(_surveyAssignmentAuditEntryFromRow).toList(growable: false);
  }
}

// ---- Row <-> model mapping (hand-written, no codegen) -----------------------

Map<String, Object?> _inputsToRow(String siteId, ClientInputs i) {
  return {
    'site_id': siteId,
    'site_name': i.siteName,
    'information_source': i.informationSource?.name,
    'client_poc_name': i.clientPocName,
    'client_poc_contact': i.clientPocContact,
    'goal_of_installation': i.goalOfInstallation,
    'water_sources': i.waterSources.map((w) => w.name).join(','),
    'oht_hns': i.ohtHns?.name,
    'finalised_plumbing_drawings': _boolToInt(i.finalisedPlumbingDrawings),
    'points_identified': i.pointsIdentified,
    'max_and_continuous_pressure': i.maxAndContinuousPressure,
    'pressure_boosters': _boolToInt(i.pressureBoosters),
    'materials_and_brand_guidelines': i.materialsAndBrandGuidelines,
    'rework_required': _boolToInt(i.reworkRequired),
    'rework_details': i.reworkDetails,
    'age_of_plumbing_lines': i.ageOfPlumbingLines,
    'aesthetic_guidelines': _boolToInt(i.aestheticGuidelines),
    'aesthetic_details': i.aestheticDetails,
    'dirty': 1,
  };
}

ClientInputs _inputsFromRow(Map<String, Object?> r) {
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
    finalisedPlumbingDrawings: _intToBool(
      r['finalised_plumbing_drawings'] as int?,
    ),
    pointsIdentified: r['points_identified'] as int?,
    maxAndContinuousPressure: (r['max_and_continuous_pressure'] as String?) ?? '',
    pressureBoosters: _intToBool(r['pressure_boosters'] as int?),
    materialsAndBrandGuidelines:
        (r['materials_and_brand_guidelines'] as String?) ?? '',
    reworkRequired: _intToBool(r['rework_required'] as int?),
    reworkDetails: (r['rework_details'] as String?) ?? '',
    ageOfPlumbingLines: (r['age_of_plumbing_lines'] as String?) ?? '',
    aestheticGuidelines: _intToBool(r['aesthetic_guidelines'] as int?),
    aestheticDetails: (r['aesthetic_details'] as String?) ?? '',
  );
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

int? _boolToInt(bool? v) => v == null ? null : (v ? 1 : 0);

bool? _intToBool(int? v) => v == null ? null : v != 0;

/// Free-text string sets are stored comma-separated (mirrors water_sources).
/// Assumes the member labels (block names, series tokens) contain no commas.
String _joinStrings(Set<String> values) => values.join(',');

Set<String> _splitStrings(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  return raw.split(',').where((s) => s.isNotEmpty).toSet();
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Maps a stored literal 'D' / 'E' / 'G' back to its [MaterialGroup]. Falls
/// back to D on anything unrecognized, same defensive style as [_enumByName].
MaterialGroup _materialGroupFromCode(String? code) {
  for (final group in kBomManualEntryGroups) {
    if (group.code == code) return group;
  }
  return MaterialGroup.d;
}

Map<String, Object?> _sourcePointToRow(SourcePoint s) {
  return {
    'id': s.id,
    'site_id': s.siteId,
    'block': s.block,
    'apartment': s.apartment,
    'inlet_description': s.inletDescription,
    'sensor_size': s.sensorSize?.name,
    'sensor_od': s.sensorOd?.name,
    'pipe_size': s.pipeSize?.name,
    'pipe_type': s.pipeType?.name,
    'qty': s.qty,
    'sensor_type': s.sensorType?.name,
    'rework': _boolToInt(s.rework),
    'rework_details': s.reworkDetails,
    'flow_direction': s.flowDirection?.name,
    'clearance_10x': _boolToInt(s.clearance10x),
    'pipe_full': _boolToInt(s.pipeFull),
    'valve_downstream': _boolToInt(s.valveDownstream),
    'reducer_spec': _boolToInt(s.reducerSpec),
    'reducer_spec_details': s.reducerSpecDetails,
    'downstream_outlet_above_pipe_fig1': _boolToInt(
      s.downstreamOutletAbovePipeFig1,
    ),
    'air_vent_needed_fig2': _boolToInt(s.airVentNeededFig2),
    'reverse_flow': _boolToInt(s.reverseFlow),
    'distance_from_motor_pump_fig3': _boolToInt(s.distanceFromMotorPumpFig3),
    'no_flexible_pipe_within_20x': _boolToInt(s.noFlexiblePipeWithin20x),
    'max_and_continuous_pressure_bar': s.maxAndContinuousPressureBar,
    'strainer_screen_filter': _boolToInt(s.strainerScreenFilter),
    'chamber_installation': _boolToInt(s.chamberInstallation),
    'antenna_required': _boolToInt(s.antennaRequired),
    'transmitting_part_open_to_air': _boolToInt(s.transmittingPartOpenToAir),
    'nrv_feasibility': _boolToInt(s.nrvFeasibility),
    'dirty': 1,
  };
}

SourcePoint _sourcePointFromRow(Map<String, Object?> r) {
  return SourcePoint(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    block: r['block'] as String?,
    apartment: (r['apartment'] as String?) ?? '',
    inletDescription: (r['inlet_description'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorOd: _enumByName(SensorOd.values, r['sensor_od'] as String?),
    pipeSize: _enumByName(PipeSize.values, r['pipe_size'] as String?),
    pipeType: _enumByName(PipeType.values, r['pipe_type'] as String?),
    qty: r['qty'] as int?,
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    rework: _intToBool(r['rework'] as int?),
    reworkDetails: (r['rework_details'] as String?) ?? '',
    flowDirection: _enumByName(
      FlowDirection.values,
      r['flow_direction'] as String?,
    ),
    clearance10x: _intToBool(r['clearance_10x'] as int?),
    pipeFull: _intToBool(r['pipe_full'] as int?),
    valveDownstream: _intToBool(r['valve_downstream'] as int?),
    reducerSpec: _intToBool(r['reducer_spec'] as int?),
    reducerSpecDetails: (r['reducer_spec_details'] as String?) ?? '',
    downstreamOutletAbovePipeFig1: _intToBool(
      r['downstream_outlet_above_pipe_fig1'] as int?,
    ),
    airVentNeededFig2: _intToBool(r['air_vent_needed_fig2'] as int?),
    reverseFlow: _intToBool(r['reverse_flow'] as int?),
    distanceFromMotorPumpFig3: _intToBool(
      r['distance_from_motor_pump_fig3'] as int?,
    ),
    noFlexiblePipeWithin20x: _intToBool(
      r['no_flexible_pipe_within_20x'] as int?,
    ),
    maxAndContinuousPressureBar:
        (r['max_and_continuous_pressure_bar'] as num?)?.toDouble(),
    strainerScreenFilter: _intToBool(r['strainer_screen_filter'] as int?),
    chamberInstallation: _intToBool(r['chamber_installation'] as int?),
    antennaRequired: _intToBool(r['antenna_required'] as int?),
    transmittingPartOpenToAir: _intToBool(
      r['transmitting_part_open_to_air'] as int?,
    ),
    nrvFeasibility: _intToBool(r['nrv_feasibility'] as int?),
  );
}

Map<String, Object?> _inletPointToRow(InletPoint i) {
  return {
    'id': i.id,
    'site_id': i.siteId,
    'block': i.block,
    'apartment_bhk': i.apartmentBhk,
    'sensor_size': i.sensorSize?.name,
    'series': i.series,
    'sensor_od': i.sensorOd?.name,
    'pipe_size': i.pipeSize?.name,
    'pipe_type': i.pipeType?.name,
    'qty': i.qty,
    'sensor_type': i.sensorType?.name,
    'rework': _boolToInt(i.rework),
    'rework_details': i.reworkDetails,
    'linear_distance_clearance_10x': _boolToInt(i.linearDistanceClearance10x),
    'reverse_flow': _boolToInt(i.reverseFlow),
    'oht_hns': i.ohtHns?.name,
    'distance_from_motor_pump': _boolToInt(i.distanceFromMotorPump),
    'max_and_continuous_pressure_bar': i.maxAndContinuousPressureBar,
    'strainer_screen_filter': _boolToInt(i.strainerScreenFilter),
    'flow_direction': i.flowDirection?.name,
    'access_mode': i.accessMode?.name,
    'cable_run_length': i.cableRunLength?.name,
    'conduit_clamping': _boolToInt(i.conduitClamping),
    'civil_work_needed': _boolToInt(i.civilWorkNeeded),
    'civil_work_details': i.civilWorkDetails,
    'dirty': 1,
  };
}

InletPoint _inletPointFromRow(Map<String, Object?> r) {
  return InletPoint(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    block: r['block'] as String?,
    apartmentBhk: (r['apartment_bhk'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    series: (r['series'] as String?) ?? '',
    sensorOd: _enumByName(SensorOd.values, r['sensor_od'] as String?),
    pipeSize: _enumByName(PipeSize.values, r['pipe_size'] as String?),
    pipeType: _enumByName(PipeType.values, r['pipe_type'] as String?),
    qty: r['qty'] as int?,
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    rework: _intToBool(r['rework'] as int?),
    reworkDetails: (r['rework_details'] as String?) ?? '',
    linearDistanceClearance10x: _intToBool(
      r['linear_distance_clearance_10x'] as int?,
    ),
    reverseFlow: _intToBool(r['reverse_flow'] as int?),
    ohtHns: _enumByName(OhtHns.values, r['oht_hns'] as String?),
    distanceFromMotorPump: _intToBool(r['distance_from_motor_pump'] as int?),
    maxAndContinuousPressureBar:
        (r['max_and_continuous_pressure_bar'] as num?)?.toDouble(),
    strainerScreenFilter: _intToBool(r['strainer_screen_filter'] as int?),
    flowDirection: _enumByName(
      FlowDirection.values,
      r['flow_direction'] as String?,
    ),
    accessMode: _enumByName(AccessMode.values, r['access_mode'] as String?),
    cableRunLength: _enumByName(
      CableRunLength.values,
      r['cable_run_length'] as String?,
    ),
    conduitClamping: _intToBool(r['conduit_clamping'] as int?),
    civilWorkNeeded: _intToBool(r['civil_work_needed'] as int?),
    civilWorkDetails: (r['civil_work_details'] as String?) ?? '',
  );
}

Map<String, Object?> _ductLoraToRow(DuctLora d) {
  return {
    'id': d.id,
    'site_id': d.siteId,
    'block': d.block,
    'series_served': _joinStrings(d.seriesServed),
    'accessible_for_service': _boolToInt(d.accessibleForService),
    'rssi_if_tcl': d.rssiIfTcl,
    'power_point_available_shielded': _boolToInt(d.powerPointAvailableShielded),
    'separate_mcb_for_series': _boolToInt(d.separateMcbForSeries),
    'ups_power_supply': _boolToInt(d.upsPowerSupply),
    'cable_length': d.cableLength,
    'dirty': 1,
  };
}

DuctLora _ductLoraFromRow(Map<String, Object?> r) {
  return DuctLora(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    block: r['block'] as String?,
    seriesServed: _splitStrings(r['series_served'] as String?),
    accessibleForService: _intToBool(r['accessible_for_service'] as int?),
    rssiIfTcl: (r['rssi_if_tcl'] as num?)?.toDouble(),
    powerPointAvailableShielded: _intToBool(
      r['power_point_available_shielded'] as int?,
    ),
    separateMcbForSeries: _intToBool(r['separate_mcb_for_series'] as int?),
    upsPowerSupply: _intToBool(r['ups_power_supply'] as int?),
    cableLength: (r['cable_length'] as num?)?.toDouble(),
  );
}

Map<String, Object?> _gatewayToRow(Gateway g) {
  return {
    'id': g.id,
    'site_id': g.siteId,
    'placement': g.placement?.name,
    'location_description': g.locationDescription,
    'blocks_covered': _joinStrings(g.blocksCovered),
    'quantity': g.quantity,
    'uplink_type': g.uplinkType?.name,
    'wifi_interference_check': _boolToInt(g.wifiInterferenceCheck),
    'wifi_interference_details': g.wifiInterferenceDetails,
    'sim_coverage': g.simCoverage?.name,
    'uninterrupted_power_source': _boolToInt(g.uninterruptedPowerSource),
    'mounting_hardware_needed': g.mountingHardwareNeeded,
    'dirty': 1,
  };
}

Gateway _gatewayFromRow(Map<String, Object?> r) {
  return Gateway(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    placement: _enumByName(GatewayPlacement.values, r['placement'] as String?),
    locationDescription: (r['location_description'] as String?) ?? '',
    blocksCovered: _splitStrings(r['blocks_covered'] as String?),
    quantity: r['quantity'] as int?,
    uplinkType: _enumByName(UplinkType.values, r['uplink_type'] as String?),
    wifiInterferenceCheck: _intToBool(r['wifi_interference_check'] as int?),
    wifiInterferenceDetails: (r['wifi_interference_details'] as String?) ?? '',
    simCoverage: _enumByName(SimCoverage.values, r['sim_coverage'] as String?),
    uninterruptedPowerSource: _intToBool(
      r['uninterrupted_power_source'] as int?,
    ),
    mountingHardwareNeeded: (r['mounting_hardware_needed'] as String?) ?? '',
  );
}

Map<String, Object?> _footerToRow(String siteId, Footer f) {
  return {
    'site_id': siteId,
    'tds_ppm': f.tdsPpm,
    'tss_ppm': f.tssPpm,
    'tcl_service': _boolToInt(f.tclService),
    'tcl_service_details': f.tclServiceDetails,
    'general_remarks': f.generalRemarks,
    'survey_date': f.surveyDate?.toIso8601String(),
    'surveyor_name': f.surveyorName,
    'dirty': 1,
  };
}

Footer _footerFromRow(Map<String, Object?> r) {
  return Footer(
    tdsPpm: (r['tds_ppm'] as num?)?.toDouble(),
    tssPpm: (r['tss_ppm'] as num?)?.toDouble(),
    tclService: _intToBool(r['tcl_service'] as int?),
    tclServiceDetails: (r['tcl_service_details'] as String?) ?? '',
    generalRemarks: (r['general_remarks'] as String?) ?? '',
    surveyDate: DateTime.tryParse((r['survey_date'] as String?) ?? ''),
    surveyorName: (r['surveyor_name'] as String?) ?? '',
  );
}

Map<String, Object?> _materialMasterItemToRow(MaterialMasterItem m) {
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
    'dirty': 1,
  };
}

MaterialMasterItem _materialMasterItemFromRow(Map<String, Object?> r) {
  return MaterialMasterItem(
    id: r['id']! as String,
    group:
        _enumByName(MaterialGroup.values, r['group_code'] as String?) ??
        MaterialGroup.a,
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

Map<String, Object?> _materialMasterAuditEntryToRow(
  MaterialMasterAuditEntry e,
) {
  return {
    'id': e.id,
    'material_row_id': e.materialRowId,
    'field_changed': e.fieldChanged,
    'old_value': e.oldValue,
    'new_value': e.newValue,
    'changed_by_role': e.changedByRole,
    'changed_at': e.changedAt.toIso8601String(),
    'dirty': 1,
  };
}

MaterialMasterAuditEntry _materialMasterAuditEntryFromRow(
  Map<String, Object?> r,
) {
  return MaterialMasterAuditEntry(
    id: r['id']! as String,
    materialRowId: r['material_row_id']! as String,
    fieldChanged: (r['field_changed'] as String?) ?? '',
    oldValue: r['old_value'] as String?,
    newValue: r['new_value'] as String?,
    changedByRole: (r['changed_by_role'] as String?) ?? '',
    changedAt:
        DateTime.tryParse((r['changed_at'] as String?) ?? '') ?? DateTime(1970),
  );
}

Map<String, Object?> _photoToRow(SurveyPhoto p) {
  return {
    'id': p.id,
    'owner_type': p.ownerType,
    'owner_id': p.ownerId,
    'slot': p.slot,
    'position': p.position,
    'local_path': p.localPath,
    'remote_path': p.remotePath,
    'dirty': 1,
  };
}

bool _photoRowUnchanged(
  Map<String, Object?> existing,
  Map<String, Object?> updated,
) {
  return existing['owner_type'] == updated['owner_type'] &&
      existing['owner_id'] == updated['owner_id'] &&
      existing['slot'] == updated['slot'] &&
      existing['position'] == updated['position'] &&
      existing['local_path'] == updated['local_path'] &&
      existing['remote_path'] == updated['remote_path'];
}

SurveyPhoto _photoFromRow(Map<String, Object?> r) {
  return SurveyPhoto(
    id: r['id']! as String,
    ownerType: r['owner_type']! as String,
    ownerId: r['owner_id']! as String,
    slot: r['slot']! as String,
    position: (r['position'] as int?) ?? 0,
    localPath: r['local_path'] as String?,
    remotePath: r['remote_path'] as String?,
  );
}

Map<String, Object?> _bomManualEntryToRow(BomManualEntry e) {
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
    // Literal 'D' / 'E' / 'G' — not the lowercase enum identifier used by
    // material_master_items.group_code. Restricted to kBomManualEntryGroups
    // by the picker UI, not by this mapper.
    'group_code': e.group.code,
    'added_by': e.addedBy,
    'added_at': e.addedAt.toIso8601String(),
    'dirty': 1,
  };
}

BomManualEntry _bomManualEntryFromRow(Map<String, Object?> r) {
  return BomManualEntry(
    id: r['id']! as String,
    surveyId: r['survey_id']! as String,
    materialName: (r['material_name'] as String?) ?? '',
    sku: (r['sku'] as String?) ?? '',
    itemLabel: (r['item_label'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    unit: (r['unit'] as String?) ?? '',
    qty: (r['qty'] as num?)?.toDouble() ?? 0,
    group: _materialGroupFromCode(r['group_code'] as String?),
    addedBy: (r['added_by'] as String?) ?? '',
    addedAt:
        DateTime.tryParse((r['added_at'] as String?) ?? '') ?? DateTime(1970),
  );
}

/// Like [_materialGroupFromCode] but searches the full A–G range — a
/// snapshot line can be either an auto-computed line (A/B/C/F) or a manual
/// entry (D/E/G), unlike bom_manual_entries rows which are always D/E/G.
MaterialGroup _materialGroupFromAnyCode(String? code) {
  for (final group in MaterialGroup.values) {
    if (group.code == code) return group;
  }
  return MaterialGroup.a;
}

Map<String, Object?> _bomSnapshotToRow(BomSnapshot s) {
  return {
    'id': s.id,
    'survey_id': s.surveyId,
    'version': s.version,
    'status': s.status,
    'finalized_by': s.finalizedBy,
    'finalized_at': s.finalizedAt.toIso8601String(),
    'dirty': 1,
  };
}

BomSnapshot _bomSnapshotFromRow(Map<String, Object?> r) {
  return BomSnapshot(
    id: r['id']! as String,
    surveyId: r['survey_id']! as String,
    version: (r['version'] as int?) ?? 1,
    status: (r['status'] as String?) ?? kBomSnapshotStatusFinal,
    finalizedBy: (r['finalized_by'] as String?) ?? '',
    finalizedAt:
        DateTime.tryParse((r['finalized_at'] as String?) ?? '') ?? DateTime(1970),
  );
}

Map<String, Object?> _bomSnapshotLineToRow(BomSnapshotLine l) {
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
    // Literal 'A'..'G' — mirrors the bom_manual_entries.group_code convention,
    // but over the full range since a snapshot line can be auto (A/B/C/F) or
    // manual (D/E/G).
    'group_code': l.group.code,
    'source': l.source.name, // literal 'auto' | 'manual'
    'dirty': 1,
  };
}

BomSnapshotLine _bomSnapshotLineFromRow(Map<String, Object?> r) {
  return BomSnapshotLine(
    id: r['id']! as String,
    snapshotId: r['snapshot_id']! as String,
    sku: (r['sku'] as String?) ?? '',
    item: (r['item'] as String?) ?? '',
    materialName: (r['material_name'] as String?) ?? '',
    itemLabel: (r['item_label'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    unit: (r['unit'] as String?) ?? '',
    qty: (r['qty'] as num?)?.toDouble() ?? 0,
    group: _materialGroupFromAnyCode(r['group_code'] as String?),
    source:
        _enumByName(BomSnapshotSource.values, r['source'] as String?) ??
        BomSnapshotSource.auto,
  );
}

Map<String, Object?> _bomRevisionToRow(BomRevision v) {
  return {
    'id': v.id,
    'survey_id': v.surveyId,
    'version': v.version,
    'reason': v.reason,
    'created_by': v.createdBy,
    'created_at': v.createdAt.toIso8601String(),
    'dirty': 1,
  };
}

BomRevision _bomRevisionFromRow(Map<String, Object?> r) {
  return BomRevision(
    id: r['id']! as String,
    surveyId: r['survey_id']! as String,
    version: (r['version'] as int?) ?? 2,
    reason: (r['reason'] as String?) ?? '',
    createdBy: (r['created_by'] as String?) ?? '',
    createdAt:
        DateTime.tryParse((r['created_at'] as String?) ?? '') ?? DateTime(1970),
  );
}

Map<String, Object?> _bomRevisionLineToRow(BomRevisionLine l) {
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
    // Literal 'A'..'G' — mirrors bom_snapshot_lines.group_code; a revision
    // line is not restricted to D/E/G like bom_manual_entries.
    'group_code': l.group.code,
    'dirty': 1,
  };
}

BomRevisionLine _bomRevisionLineFromRow(Map<String, Object?> r) {
  return BomRevisionLine(
    id: r['id']! as String,
    revisionId: r['revision_id']! as String,
    sku: (r['sku'] as String?) ?? '',
    item: (r['item'] as String?) ?? '',
    materialName: (r['material_name'] as String?) ?? '',
    itemLabel: (r['item_label'] as String?) ?? '',
    sensorSize: _enumByName(SensorSize.values, r['sensor_size'] as String?),
    sensorType: _enumByName(SensorType.values, r['sensor_type'] as String?),
    unit: (r['unit'] as String?) ?? '',
    qtyDelta: (r['qty_delta'] as num?)?.toDouble() ?? 0,
    group: _materialGroupFromAnyCode(r['group_code'] as String?),
  );
}

Map<String, Object?> _bomManualEditSnapshotToRow(BomManualEditSnapshot s) {
  return {
    'id': s.id,
    'survey_id': s.surveyId,
    'version': s.version,
    'based_on_version': s.basedOnVersion,
    'edited_by': s.editedBy,
    'edited_at': s.editedAt.toIso8601String(),
    'reason': s.reason,
    'dirty': 1,
  };
}

BomManualEditSnapshot _bomManualEditSnapshotFromRow(Map<String, Object?> r) {
  return BomManualEditSnapshot(
    id: r['id']! as String,
    surveyId: r['survey_id']! as String,
    version: (r['version'] as int?) ?? 2,
    basedOnVersion: (r['based_on_version'] as int?) ?? 1,
    editedBy: (r['edited_by'] as String?) ?? '',
    editedAt:
        DateTime.tryParse((r['edited_at'] as String?) ?? '') ?? DateTime(1970),
    reason: (r['reason'] as String?) ?? '',
  );
}

Map<String, Object?> _bomManualEditSnapshotLineToRow(
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
    // Literal 'A'..'G' — mirrors bom_snapshot_lines.group_code.
    'group_code': l.group.code,
    'dirty': 1,
  };
}

BomManualEditSnapshotLine _bomManualEditSnapshotLineFromRow(
  Map<String, Object?> r,
) {
  return BomManualEditSnapshotLine(
    id: r['id']! as String,
    snapshotId: r['snapshot_id']! as String,
    sku: (r['sku'] as String?) ?? '',
    itemName: (r['item_name'] as String?) ?? '',
    description: (r['description'] as String?) ?? '',
    unit: (r['unit'] as String?) ?? '',
    qty: (r['qty'] as num?)?.toDouble() ?? 0,
    group: _materialGroupFromAnyCode(r['group_code'] as String?),
  );
}

SurveyAssignmentAuditEntry _surveyAssignmentAuditEntryFromRow(
  Map<String, Object?> r,
) {
  return SurveyAssignmentAuditEntry(
    id: r['id']! as String,
    siteId: r['site_id']! as String,
    oldAssignee: r['old_assignee'] as String?,
    newAssignee: (r['new_assignee'] as String?) ?? '',
    changedByRole: (r['changed_by_role'] as String?) ?? '',
    changedAt:
        DateTime.tryParse((r['changed_at'] as String?) ?? '') ?? DateTime(1970),
  );
}
