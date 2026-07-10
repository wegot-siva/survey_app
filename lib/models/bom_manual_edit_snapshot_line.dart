import 'material_master_item.dart';

/// One full line of a [BomManualEditSnapshot] — every field an Admin/Approver
/// can hand-edit (SKU, item name, description, unit, qty). [group] is copied
/// over unchanged from whatever line this replaces; it isn't one of the
/// editable fields.
class BomManualEditSnapshotLine {
  const BomManualEditSnapshotLine({
    required this.id,
    required this.snapshotId,
    this.sku = '',
    required this.itemName,
    this.description = '',
    required this.unit,
    required this.qty,
    required this.group,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// Empty string until the parent [BomManualEditSnapshot] itself is
  /// created — the repository assigns this alongside [id] in the same
  /// write. See [copyWithIds].
  final String snapshotId;

  final String sku;
  final String itemName;
  final String description;
  final String unit;
  final double qty;
  final MaterialGroup group;

  /// Returns a copy with both ids filled in. Used when the repository
  /// persists a freshly-built line as part of creating a manual-edit
  /// snapshot — [id] and [snapshotId] are both unknown to the caller until
  /// that moment.
  BomManualEditSnapshotLine copyWithIds({
    required String id,
    required String snapshotId,
  }) => BomManualEditSnapshotLine(
    id: id,
    snapshotId: snapshotId,
    sku: sku,
    itemName: itemName,
    description: description,
    unit: unit,
    qty: qty,
    group: group,
  );
}
