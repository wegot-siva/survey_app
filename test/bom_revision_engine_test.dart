// Unit tests for BomRevisionEngine's running-total math: v1 snapshot lines
// plus every revision's deltas, summed per (sku, item); floored display at 0
// with a below-zero flag when a delta would otherwise push it negative.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/models/bom_revision_line.dart';
import 'package:survey_app/models/bom_snapshot_line.dart';
import 'package:survey_app/models/material_master_item.dart';
import 'package:survey_app/services/bom_revision_engine.dart';

void main() {
  const engine = BomRevisionEngine();

  BomSnapshotLine snapshotLine({
    String sku = 'SEN-1',
    String item = 'Sensor',
    double qty = 10,
    MaterialGroup group = MaterialGroup.a,
    BomSnapshotSource source = BomSnapshotSource.auto,
  }) => BomSnapshotLine(
    id: 'sl1',
    snapshotId: 'snap1',
    sku: sku,
    item: item,
    unit: 'pcs',
    qty: qty,
    group: group,
    source: source,
  );

  BomRevisionLine revisionLine({
    String sku = 'SEN-1',
    String item = 'Sensor',
    double qtyDelta = 1,
    MaterialGroup group = MaterialGroup.a,
  }) => BomRevisionLine(
    id: 'rl1',
    revisionId: 'rev1',
    sku: sku,
    item: item,
    unit: 'pcs',
    qtyDelta: qtyDelta,
    group: group,
  );

  test('with no revisions, running total equals v1 exactly', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(qty: 10)],
      revisionLines: const [],
    );
    expect(result, hasLength(1));
    expect(result.single.rawQty, 10);
    expect(result.single.displayQty, 10);
    expect(result.single.isBelowZero, isFalse);
  });

  test('a positive delta on the same sku/item adds to the v1 quantity', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(qty: 10)],
      revisionLines: [revisionLine(qtyDelta: 5)],
    );
    expect(result.single.rawQty, 15);
    expect(result.single.displayQty, 15);
  });

  test('a negative delta subtracts from the v1 quantity', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(qty: 10)],
      revisionLines: [revisionLine(qtyDelta: -4)],
    );
    expect(result.single.rawQty, 6);
    expect(result.single.displayQty, 6);
    expect(result.single.isBelowZero, isFalse);
  });

  test('a delta that pushes the total below zero floors the display at 0 '
      'and sets the below-zero flag', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(qty: 3)],
      revisionLines: [revisionLine(qtyDelta: -10)],
    );
    expect(result.single.rawQty, -7);
    expect(result.single.displayQty, 0);
    expect(result.single.isBelowZero, isTrue);
  });

  test('multiple revisions on the same sku/item all accumulate', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(qty: 10)],
      revisionLines: [
        revisionLine(qtyDelta: 5),
        revisionLine(qtyDelta: -2),
        revisionLine(qtyDelta: 3),
      ],
    );
    expect(result.single.rawQty, 16); // 10 + 5 - 2 + 3
  });

  test('a delta for a brand-new sku/item (no matching v1 line) becomes its '
      'own running-total line', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(sku: 'SEN-1', item: 'Sensor', qty: 10)],
      revisionLines: [
        revisionLine(sku: 'NEW-1', item: 'Extra elbow', qtyDelta: 3),
      ],
    );
    expect(result, hasLength(2));
    final extra = result.firstWhere((l) => l.sku == 'NEW-1');
    expect(extra.item, 'Extra elbow');
    expect(extra.rawQty, 3);
  });

  test('different sku/item pairs never collide', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [
        snapshotLine(sku: 'A', item: 'One', qty: 5),
        snapshotLine(sku: 'B', item: 'Two', qty: 7),
      ],
      revisionLines: const [],
    );
    expect(result, hasLength(2));
    expect(result.firstWhere((l) => l.sku == 'A').rawQty, 5);
    expect(result.firstWhere((l) => l.sku == 'B').rawQty, 7);
  });

  test('every MaterialGroup value is usable as a running-total group', () {
    final result = engine.computeRunningTotal(
      snapshotLines: [snapshotLine(group: MaterialGroup.g, qty: 1)],
      revisionLines: const [],
    );
    expect(result.single.group, MaterialGroup.g);
  });
}
