// Pure-logic tests for the blocks positional-diff (Full sync Group 1's
// blocks-push fix) — no database involved, so this is the actual
// correctness surface for the stable-id rework, independent of whether
// sqlite executes the resulting ops correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/services/block_diff.dart';

void main() {
  test('empty existing, some new labels — all inserts', () {
    final ops = diffBlocks(const [], ['A', 'B']);
    expect(ops, hasLength(2));
    expect(ops[0], isA<InsertBlockOp>());
    expect((ops[0] as InsertBlockOp).position, 0);
    expect((ops[0] as InsertBlockOp).label, 'A');
    expect(ops[1], isA<InsertBlockOp>());
    expect((ops[1] as InsertBlockOp).position, 1);
    expect((ops[1] as InsertBlockOp).label, 'B');
  });

  test('identical labels produce zero ops (no spurious re-dirty)', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
      const ExistingBlock(id: 'x2', label: 'B'),
    ];
    final ops = diffBlocks(existing, ['A', 'B']);
    expect(ops, isEmpty);
  });

  test('appending a new block only inserts the new one, leaves the rest untouched', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
      const ExistingBlock(id: 'x2', label: 'B'),
    ];
    final ops = diffBlocks(existing, ['A', 'B', 'C']);
    expect(ops, hasLength(1));
    expect(ops.single, isA<InsertBlockOp>());
    expect((ops.single as InsertBlockOp).position, 2);
    expect((ops.single as InsertBlockOp).label, 'C');
  });

  test('deleting the last block only tombstones that one row', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
      const ExistingBlock(id: 'x2', label: 'B'),
    ];
    final ops = diffBlocks(existing, ['A']);
    expect(ops, hasLength(1));
    expect(ops.single, isA<TombstoneBlockOp>());
    expect((ops.single as TombstoneBlockOp).id, 'x2');
  });

  test('deleting every block tombstones every row', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
      const ExistingBlock(id: 'x2', label: 'B'),
    ];
    final ops = diffBlocks(existing, const []);
    expect(ops, hasLength(2));
    expect(ops.map((o) => (o as TombstoneBlockOp).id), ['x1', 'x2']);
  });

  test('editing one label in place produces exactly one update, same id', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
      const ExistingBlock(id: 'x2', label: 'B'),
      const ExistingBlock(id: 'x3', label: 'C'),
    ];
    final ops = diffBlocks(existing, ['A', 'B-edited', 'C']);
    expect(ops, hasLength(1));
    final op = ops.single as UpdateBlockOp;
    expect(op.id, 'x2');
    expect(op.position, 1);
    expect(op.label, 'B-edited');
  });

  test(
    'deleting a middle block: correctness over cosmetic id attribution — '
    'final content is right, nothing after the edit point is spuriously '
    'inserted, and the excess tail is tombstoned',
    () {
      final existing = [
        const ExistingBlock(id: 'x1', label: 'A'),
        const ExistingBlock(id: 'x2', label: 'B'),
        const ExistingBlock(id: 'x3', label: 'C'),
      ];
      // User deleted "B" — UI now shows [A, C].
      final ops = diffBlocks(existing, ['A', 'C']);
      // Position 0 unchanged (A==A) — no op.
      // Position 1: existing x2/'B' -> new 'C' — content differs -> update.
      // Position 2 (x3) has no corresponding new position -> tombstone.
      expect(ops, hasLength(2));
      final update = ops.whereType<UpdateBlockOp>().single;
      expect(update.id, 'x2');
      expect(update.label, 'C');
      final tombstone = ops.whereType<TombstoneBlockOp>().single;
      expect(tombstone.id, 'x3');
      // No insert ops — the middle deletion never needed a genuinely new row.
      expect(ops.whereType<InsertBlockOp>(), isEmpty);
    },
  );

  test('replacing the whole list (all different labels) updates every row, no inserts/tombstones', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
      const ExistingBlock(id: 'x2', label: 'B'),
    ];
    final ops = diffBlocks(existing, ['X', 'Y']);
    expect(ops, hasLength(2));
    expect(ops.every((o) => o is UpdateBlockOp), isTrue);
  });

  test('shrink and grow simultaneously handled correctly relative to old length', () {
    final existing = [
      const ExistingBlock(id: 'x1', label: 'A'),
    ];
    final ops = diffBlocks(existing, ['A', 'B', 'C']);
    expect(ops, hasLength(2));
    expect(ops.every((o) => o is InsertBlockOp), isTrue);
    expect((ops[0] as InsertBlockOp).position, 1);
    expect((ops[1] as InsertBlockOp).position, 2);
  });
}
