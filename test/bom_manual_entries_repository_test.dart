// Contract tests for the D/E/G "Add materials" picker's storage, exercised
// through the in-memory repository: create/edit/delete, scoping to a single
// survey, and that the group stays restricted to D/E/G at the picker layer
// (this test only asserts the model/repository don't reject other groups
// outright — enforcement of D/E/G-only lives in the form UI).

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/bom_manual_entry.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/id_service.dart';

void main() {
  late InMemorySurveyRepository repo;

  setUp(() => repo = InMemorySurveyRepository(IdService()));

  BomManualEntry draft(String surveyId, {MaterialGroup group = MaterialGroup.d}) =>
      BomManualEntry(
        id: '',
        surveyId: surveyId,
        materialName: 'Extra rework kit',
        sku: 'RWK-1',
        unit: 'set',
        qty: 2,
        group: group,
        addedBy: 'Engineer',
        addedAt: DateTime(2026, 1, 1),
      );

  test('kBomManualEntryGroups is exactly D, E, G', () {
    expect(kBomManualEntryGroups, [
      MaterialGroup.d,
      MaterialGroup.e,
      MaterialGroup.g,
    ]);
  });

  test('the three allowed groups .code is the literal D/E/G the DB stores', () {
    // sqflite/Supabase row mapping persists `.code` (not `.name`) for this
    // table's group_code column — locks that contract in against MaterialGroup
    // changing shape later without this table's storage format being noticed.
    expect(MaterialGroup.d.code, 'D');
    expect(MaterialGroup.e.code, 'E');
    expect(MaterialGroup.g.code, 'G');
  });

  test('add assigns an id and persists the entry', () async {
    final stored = await repo.addBomManualEntry(draft('site1'));
    expect(stored.id, isNotEmpty);

    final entries = await repo.getBomManualEntries('site1');
    expect(entries, hasLength(1));
    expect(entries.single.materialName, 'Extra rework kit');
    expect(entries.single.group, MaterialGroup.d);
  });

  test('getBomManualEntries only returns entries for that survey', () async {
    await repo.addBomManualEntry(draft('site1'));
    await repo.addBomManualEntry(draft('site2', group: MaterialGroup.e));

    expect(await repo.getBomManualEntries('site1'), hasLength(1));
    expect(await repo.getBomManualEntries('site2'), hasLength(1));
    expect((await repo.getBomManualEntries('site2')).single.group, MaterialGroup.e);
  });

  test('update changes fields without changing the id', () async {
    final stored = await repo.addBomManualEntry(draft('site1'));

    await repo.updateBomManualEntry(
      BomManualEntry(
        id: stored.id,
        surveyId: stored.surveyId,
        materialName: stored.materialName,
        sku: stored.sku,
        unit: stored.unit,
        qty: 9, // changed
        group: MaterialGroup.g, // changed
        addedBy: stored.addedBy,
        addedAt: stored.addedAt,
      ),
    );

    final entries = await repo.getBomManualEntries('site1');
    expect(entries, hasLength(1));
    expect(entries.single.id, stored.id);
    expect(entries.single.qty, 9);
    expect(entries.single.group, MaterialGroup.g);
  });

  test('delete removes the entry', () async {
    final stored = await repo.addBomManualEntry(draft('site1'));
    await repo.deleteBomManualEntry(stored.id);
    expect(await repo.getBomManualEntries('site1'), isEmpty);
  });

  test('entries are returned oldest first', () async {
    final first = await repo.addBomManualEntry(
      BomManualEntry(
        id: '',
        surveyId: 'site1',
        materialName: 'First',
        unit: 'pcs',
        qty: 1,
        group: MaterialGroup.d,
        addedBy: 'Engineer',
        addedAt: DateTime(2026, 1, 1),
      ),
    );
    final second = await repo.addBomManualEntry(
      BomManualEntry(
        id: '',
        surveyId: 'site1',
        materialName: 'Second',
        unit: 'pcs',
        qty: 1,
        group: MaterialGroup.e,
        addedBy: 'Engineer',
        addedAt: DateTime(2026, 1, 2),
      ),
    );

    final entries = await repo.getBomManualEntries('site1');
    expect(entries.map((e) => e.id).toList(), [first.id, second.id]);
  });
}
