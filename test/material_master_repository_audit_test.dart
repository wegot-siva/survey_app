// Contract tests for the Material Master change log wiring, exercised through
// the in-memory repository: create/edit/delete must each write the audit rows
// MaterialMasterAuditBuilder computes, and the log must survive a row's own
// deletion (it is not FK'd to material_master_items).

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  late InMemorySurveyRepository repo;

  setUp(() => repo = InMemorySurveyRepository(IdService()));

  const draft = MaterialMasterItem(
    id: '',
    group: MaterialGroup.a,
    materialName: 'WEGOTAqua sensor',
    sku: 'WGA-001',
    unit: 'pcs',
    behaviorType: MaterialBehaviorType.fixed,
    quantityPerSensor: 2,
  );

  test('create writes one audit row referencing the new row', () async {
    final stored = await repo.addMaterialMasterItem(
      draft,
      changedByRole: 'Admin',
    );

    final log = await repo.getMaterialMasterAuditLog();
    expect(log, hasLength(1));
    expect(log.single.materialRowId, stored.id);
    expect(log.single.fieldChanged, '(created)');
    expect(log.single.changedByRole, 'Admin');
  });

  test('edit writes one audit row per changed field, referencing that row', () async {
    final stored = await repo.addMaterialMasterItem(
      draft,
      changedByRole: 'Admin',
    );

    await repo.updateMaterialMasterItem(
      MaterialMasterItem(
        id: stored.id,
        group: stored.group,
        materialName: stored.materialName,
        sku: stored.sku,
        unit: stored.unit,
        behaviorType: stored.behaviorType,
        quantityPerSensor: 9, // only this changes
      ),
      changedByRole: 'Admin',
    );

    final log = await repo.getMaterialMasterAuditLog();
    // The create's row, plus one row for the single changed field.
    expect(log, hasLength(2));
    final editEntry = log.firstWhere((e) => e.fieldChanged != '(created)');
    expect(editEntry.fieldChanged, 'Quantity per sensor');
    expect(editEntry.oldValue, '2.0');
    expect(editEntry.newValue, '9.0');
    expect(editEntry.materialRowId, stored.id);
  });

  test('editing with no actual field change adds no new audit row', () async {
    final stored = await repo.addMaterialMasterItem(
      draft,
      changedByRole: 'Admin',
    );
    await repo.updateMaterialMasterItem(stored, changedByRole: 'Admin');

    final log = await repo.getMaterialMasterAuditLog();
    expect(log, hasLength(1)); // just the create
  });

  test('delete writes one audit row that survives the row itself being gone', () async {
    final stored = await repo.addMaterialMasterItem(
      draft,
      changedByRole: 'Admin',
    );
    await repo.deleteMaterialMasterItem(stored.id, changedByRole: 'Admin');

    expect(await repo.getMaterialMasterItems(), isEmpty);

    final log = await repo.getMaterialMasterAuditLog();
    expect(log, hasLength(2)); // create + delete
    final deleteEntry = log.firstWhere((e) => e.fieldChanged == '(deleted)');
    expect(deleteEntry.materialRowId, stored.id);
    expect(deleteEntry.oldValue, contains('WEGOTAqua sensor'));
  });

  test('log is ordered newest first', () async {
    final a = await repo.addMaterialMasterItem(draft, changedByRole: 'Admin');
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await repo.deleteMaterialMasterItem(a.id, changedByRole: 'Admin');

    final log = await repo.getMaterialMasterAuditLog();
    expect(log.first.fieldChanged, '(deleted)');
    expect(log.last.fieldChanged, '(created)');
  });
}
