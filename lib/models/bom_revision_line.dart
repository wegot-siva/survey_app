import 'material_master_item.dart';

/// One delta line of a [BomRevision] — adds to (or, with a negative
/// [qtyDelta], subtracts from) the running total for its (sku, item) pair.
/// Unlike [BomManualEntry], [group] is not restricted to D/E/G — a revision
/// can adjust any group A-G.
class BomRevisionLine {
  const BomRevisionLine({
    required this.id,
    required this.revisionId,
    this.sku = '',
    required this.item,
    required this.unit,
    required this.qtyDelta,
    required this.group,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// Empty string until the parent [BomRevision] itself is created — the
  /// repository assigns this alongside [id] in the same write. See
  /// [copyWithIds].
  final String revisionId;

  final String sku;
  final String item;
  final String unit;

  /// May be negative (reduces the running total for this sku/item).
  final double qtyDelta;

  final MaterialGroup group;

  /// Returns a copy with both ids filled in. Used when the repository
  /// persists a freshly-built line as part of creating a revision — [id] and
  /// [revisionId] are both unknown to the caller until that moment.
  BomRevisionLine copyWithIds({
    required String id,
    required String revisionId,
  }) => BomRevisionLine(
    id: id,
    revisionId: revisionId,
    sku: sku,
    item: item,
    unit: unit,
    qtyDelta: qtyDelta,
    group: group,
  );
}
