import 'material_master_item.dart';

/// One computed line of a generated BoM — output of [BomEngine], never stored
/// (except when copied into a [BomSnapshotLine] at Finalize time).
class BomLine {
  const BomLine({
    required this.group,
    required this.materialName,
    this.sku = '',
    required this.variantLabel,
    required this.quantity,
    required this.unit,
  });

  final MaterialGroup group;
  final String materialName;

  /// Copied straight from the source [MaterialMasterItem] row — not shown by
  /// the existing preview UI, but available so Finalize can carry it into a
  /// frozen snapshot line without a second lookup.
  final String sku;

  /// e.g. "DN25 · Wired", or "—" for a row not tied to a specific variant.
  final String variantLabel;

  final double quantity;
  final String unit;
}
