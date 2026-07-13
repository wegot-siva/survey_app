import '../data/survey_repository.dart';
import '../models/material_master_item.dart';

/// DEV-ONLY: a small, disposable set of group C plumbing rows with
/// material_type/category/variant/size_mm/size_display populated, so the
/// "Add materials" picker's 4-level cascade (Material Type -> Category ->
/// Variant -> Size) has something to show on a test device — those columns
/// are unset on every real Material Master row today.
///
/// Every row is tagged with a `TEST-CASCADE-` SKU prefix, both to make it
/// unmistakable in the catalog and so [seedCascadeTestData]/
/// [removeCascadeTestData] can find exactly (and only) these rows again.
/// Inserted/removed through [SurveyRepository.addMaterialMasterItem] /
/// [SurveyRepository.deleteMaterialMasterItem] — the same write path the
/// Admin Material Master form uses — so seeded rows are indistinguishable
/// from real ones to the rest of the app (dirty flag, audit log, sync).
///
/// DELETE this file and its one call site (the two dev-only AppBar actions on
/// `material_master_screen.dart`) once real plumbing catalog data replaces
/// this placeholder set.
const _testSkuPrefix = 'TEST-CASCADE-';

List<MaterialMasterItem> _cascadeTestData() {
  MaterialMasterItem row({
    required String sku,
    required String materialType,
    required String category,
    required String variant,
    required double sizeMm,
    required String sizeDisplay,
  }) {
    return MaterialMasterItem(
      id: '',
      group: MaterialGroup.c,
      materialName: '[TEST] $materialType $category $variant $sizeDisplay',
      sku: sku,
      unit: 'pcs',
      behaviorType: MaterialBehaviorType.fixed,
      materialType: materialType,
      category: category,
      variant: variant,
      sizeMm: sizeMm,
      sizeDisplay: sizeDisplay,
    );
  }

  return [
    row(
      sku: '${_testSkuPrefix}01',
      materialType: 'uPVC',
      category: 'Elbow 90°',
      variant: 'SCH40',
      sizeMm: 15,
      sizeDisplay: '½"',
    ),
    row(
      sku: '${_testSkuPrefix}02',
      materialType: 'uPVC',
      category: 'Elbow 90°',
      variant: 'SCH40',
      sizeMm: 20,
      sizeDisplay: '¾"',
    ),
    row(
      sku: '${_testSkuPrefix}03',
      materialType: 'uPVC',
      category: 'Elbow 90°',
      variant: 'SCH40',
      sizeMm: 25,
      sizeDisplay: '1"',
    ),
    row(
      sku: '${_testSkuPrefix}04',
      materialType: 'uPVC',
      category: 'Elbow 90°',
      variant: 'SCH80',
      sizeMm: 15,
      sizeDisplay: '½"',
    ),
    row(
      sku: '${_testSkuPrefix}05',
      materialType: 'uPVC',
      category: 'Elbow 90°',
      variant: 'SCH80',
      sizeMm: 25,
      sizeDisplay: '1"',
    ),
    row(
      sku: '${_testSkuPrefix}06',
      materialType: 'uPVC',
      category: 'Tee',
      variant: 'SCH40',
      sizeMm: 20,
      sizeDisplay: '¾"',
    ),
    row(
      sku: '${_testSkuPrefix}07',
      materialType: 'uPVC',
      category: 'Tee',
      variant: 'SCH40',
      sizeMm: 25,
      sizeDisplay: '1"',
    ),
    row(
      sku: '${_testSkuPrefix}08',
      materialType: 'CPVC',
      category: 'Coupler',
      variant: 'Brass Threaded',
      sizeMm: 15,
      sizeDisplay: '½"',
    ),
    row(
      sku: '${_testSkuPrefix}09',
      materialType: 'CPVC',
      category: 'Coupler',
      variant: 'Brass Threaded',
      sizeMm: 20,
      sizeDisplay: '¾"',
    ),
    row(
      sku: '${_testSkuPrefix}10',
      materialType: 'CPVC',
      category: 'Elbow 90°',
      variant: 'SCH80',
      sizeMm: 32,
      sizeDisplay: '1¼"',
    ),
  ];
}

/// Inserts the fixed test set if none of it is present yet (checked by SKU
/// prefix) — safe to tap more than once, never duplicates. Returns how many
/// rows were actually inserted (0 if already seeded).
Future<int> seedCascadeTestData(
  SurveyRepository repository, {
  required String changedByRole,
}) async {
  final existing = await repository.getMaterialMasterItems();
  if (existing.any((i) => i.sku.startsWith(_testSkuPrefix))) return 0;

  final rows = _cascadeTestData();
  for (final row in rows) {
    await repository.addMaterialMasterItem(row, changedByRole: changedByRole);
  }
  return rows.length;
}

/// Removes every row this seed added (matched by SKU prefix). Returns how
/// many rows were removed.
Future<int> removeCascadeTestData(
  SurveyRepository repository, {
  required String changedByRole,
}) async {
  final existing = await repository.getMaterialMasterItems();
  final toRemove = existing
      .where((i) => i.sku.startsWith(_testSkuPrefix))
      .toList();
  for (final item in toRemove) {
    await repository.deleteMaterialMasterItem(
      item.id,
      changedByRole: changedByRole,
    );
  }
  return toRemove.length;
}
