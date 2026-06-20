import 'material_master_item.dart';

/// One computed line of a generated BoM — output of [BomEngine], never stored.
class BomLine {
  const BomLine({
    required this.group,
    required this.materialName,
    required this.variantLabel,
    required this.quantity,
    required this.unit,
  });

  final MaterialGroup group;
  final String materialName;

  /// e.g. "DN25 · Wired", or "—" for a row not tied to a specific variant.
  final String variantLabel;

  final double quantity;
  final String unit;
}
