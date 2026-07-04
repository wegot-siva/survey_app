import '../models/bom_revision_line.dart';
import '../models/bom_snapshot_line.dart';
import '../models/material_master_item.dart';

/// One (sku, item) pair's running total: the locked v1 snapshot quantity plus
/// every revision's delta for that same pair.
class BomRunningTotalLine {
  const BomRunningTotalLine({
    required this.sku,
    required this.item,
    required this.unit,
    required this.group,
    required this.rawQty,
  });

  final String sku;
  final String item;
  final String unit;
  final MaterialGroup group;

  /// v1 qty + all deltas, NOT floored — may be negative.
  final double rawQty;

  /// What to show: floored at 0, since a real quantity can't go negative.
  double get displayQty => rawQty < 0 ? 0 : rawQty;

  /// True when [rawQty] is negative — the floor above is hiding a deficit
  /// that a revision pushed below zero. Flag it rather than silently clamp.
  bool get isBelowZero => rawQty < 0;
}

/// Computes the running total for a locked survey's BoM: the frozen v1
/// [BomSnapshotLine]s plus every [BomRevisionLine] on top, summed per
/// (sku, item). Pure, no I/O — mirrors [BomEngine]'s style. Computed fresh on
/// every read; no per-version total is ever stored.
class BomRevisionEngine {
  const BomRevisionEngine();

  List<BomRunningTotalLine> computeRunningTotal({
    required List<BomSnapshotLine> snapshotLines,
    required List<BomRevisionLine> revisionLines,
  }) {
    final totals = <String, BomRunningTotalLine>{};

    for (final line in snapshotLines) {
      final key = _keyFor(line.sku, line.item);
      final existing = totals[key];
      totals[key] = BomRunningTotalLine(
        sku: line.sku,
        item: line.item,
        unit: line.unit,
        group: line.group,
        rawQty: (existing?.rawQty ?? 0) + line.qty,
      );
    }

    for (final line in revisionLines) {
      final key = _keyFor(line.sku, line.item);
      final existing = totals[key];
      totals[key] = BomRunningTotalLine(
        sku: line.sku,
        item: line.item,
        unit: existing?.unit ?? line.unit,
        group: existing?.group ?? line.group,
        rawQty: (existing?.rawQty ?? 0) + line.qtyDelta,
      );
    }

    return totals.values.toList(growable: false);
  }

  /// Keyed by the literal (sku, item) pair, joined with a separator that
  /// can't appear in either field — matches the spec's "summed per
  /// (sku/item)" wording exactly, so two different items that happen to
  /// share a blank sku don't collide.
  String _keyFor(String sku, String item) => '$sku|$item';
}
