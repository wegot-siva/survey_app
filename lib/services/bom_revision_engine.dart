import '../models/bom_manual_edit_snapshot_line.dart';
import '../models/bom_revision_line.dart';
import '../models/bom_snapshot_line.dart';
import '../models/material_master_item.dart';
import '../models/survey_options.dart';

/// One (sku, item) pair's running total: a base version's quantity plus every
/// revision's delta for that same pair, on top of that base.
class BomRunningTotalLine {
  const BomRunningTotalLine({
    required this.sku,
    required this.item,
    this.materialName = '',
    this.itemLabel = '',
    this.description = '',
    this.sensorSize,
    this.sensorType,
    required this.unit,
    required this.group,
    required this.rawQty,
  });

  final String sku;
  final String item;

  /// The plain material name (no variant suffix) — for Lumax's "Materials"
  /// column. Sun_BOM keeps reading [item], unaffected.
  final String materialName;

  /// Set only via a manual edit (see [baseFromManualEditLines]) — blank for
  /// any line that's never been through one. Preserved across later
  /// revisions/manual edits on the same (sku, item) pair, same as every
  /// other identity field — not read by either exporter.
  final String description;

  /// For Lumax's "Item" column.
  final String itemLabel;

  /// For Lumax's sheet-per-variant grouping. Null for lines with no variant
  /// (most D/E/G manual/revision entries, and every manual-edit line — see
  /// [BomRevisionEngine.baseFromManualEditLines]) — those land on a
  /// catch-all sheet.
  final SensorSize? sensorSize;
  final SensorType? sensorType;

  final String unit;
  final MaterialGroup group;

  /// Base qty + all deltas on top of it, NOT floored — may be negative.
  final double rawQty;

  /// What to show: floored at 0, since a real quantity can't go negative.
  double get displayQty => rawQty < 0 ? 0 : rawQty;

  /// True when [rawQty] is negative — the floor above is hiding a deficit
  /// that a revision pushed below zero. Flag it rather than silently clamp.
  bool get isBelowZero => rawQty < 0;
}

/// Computes a locked survey's BoM at any version: a base full line list (the
/// frozen v1 [BomSnapshotLine]s, or a later [BomManualEditSnapshotLine] full
/// replacement — see [baseFromSnapshotLines] / [baseFromManualEditLines])
/// plus every [BomRevisionLine] that falls between that base's version and
/// the target version, summed per (sku, item). Pure, no I/O. Computed fresh
/// on every read; no per-version total is ever stored.
///
/// Callers are responsible for resolving *which* base and *which* revisions
/// apply to a given target version — see [BomPreviewScreen]'s
/// `_cumulativeTotalForVersion` for that resolution (nearest base at or
/// before the target version, then every revision strictly after that base
/// up to and including the target).
class BomRevisionEngine {
  const BomRevisionEngine();

  List<BomRunningTotalLine> computeRunningTotal({
    required List<BomRunningTotalLine> baseLines,
    required List<BomRevisionLine> revisionLines,
  }) {
    final totals = <String, BomRunningTotalLine>{
      for (final line in baseLines) _keyFor(line.sku, line.item): line,
    };

    for (final line in revisionLines) {
      final key = _keyFor(line.sku, line.item);
      final existing = totals[key];
      totals[key] = BomRunningTotalLine(
        sku: line.sku,
        item: line.item,
        materialName: existing?.materialName.isNotEmpty ?? false
            ? existing!.materialName
            : line.materialName,
        itemLabel: existing?.itemLabel.isNotEmpty ?? false
            ? existing!.itemLabel
            : line.itemLabel,
        description: existing?.description ?? '',
        sensorSize: existing?.sensorSize ?? line.sensorSize,
        sensorType: existing?.sensorType ?? line.sensorType,
        unit: existing?.unit ?? line.unit,
        group: existing?.group ?? line.group,
        rawQty: (existing?.rawQty ?? 0) + line.qtyDelta,
      );
    }

    return totals.values.toList(growable: false);
  }

  /// Normalizes the frozen v1 snapshot's lines into a [BomRunningTotalLine]
  /// base, summed per (sku, item) — the same shape [computeRunningTotal]
  /// expects as its starting point.
  List<BomRunningTotalLine> baseFromSnapshotLines(
    List<BomSnapshotLine> lines,
  ) {
    final totals = <String, BomRunningTotalLine>{};
    for (final line in lines) {
      final key = _keyFor(line.sku, line.item);
      final existing = totals[key];
      totals[key] = BomRunningTotalLine(
        sku: line.sku,
        item: line.item,
        materialName: existing?.materialName.isNotEmpty ?? false
            ? existing!.materialName
            : line.materialName,
        itemLabel: existing?.itemLabel.isNotEmpty ?? false
            ? existing!.itemLabel
            : line.itemLabel,
        sensorSize: existing?.sensorSize ?? line.sensorSize,
        sensorType: existing?.sensorType ?? line.sensorType,
        unit: line.unit,
        group: line.group,
        rawQty: (existing?.rawQty ?? 0) + line.qty,
      );
    }
    return totals.values.toList(growable: false);
  }

  /// Normalizes a manual-edit snapshot's lines into the same base shape.
  /// Manual-edit lines have no separate materialName/itemLabel/sensor-variant
  /// concept (every field is directly hand-typed, not sourced from a
  /// catalog) — [BomRunningTotalLine.item], `.materialName`, and `.itemLabel`
  /// all collapse to the same [BomManualEditSnapshotLine.itemName], and
  /// sensorSize/sensorType are left null (same "no variant" catch-all
  /// treatment as ordinary D/E/G manual entries).
  List<BomRunningTotalLine> baseFromManualEditLines(
    List<BomManualEditSnapshotLine> lines,
  ) {
    final totals = <String, BomRunningTotalLine>{};
    for (final line in lines) {
      final key = _keyFor(line.sku, line.itemName);
      final existing = totals[key];
      totals[key] = BomRunningTotalLine(
        sku: line.sku,
        item: line.itemName,
        materialName: line.itemName,
        itemLabel: line.itemName,
        description: line.description,
        unit: line.unit,
        group: line.group,
        rawQty: (existing?.rawQty ?? 0) + line.qty,
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
