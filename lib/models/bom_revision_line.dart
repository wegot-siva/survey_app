import 'material_master_item.dart';
import 'survey_options.dart';

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
    this.materialName = '',
    this.itemLabel = '',
    this.sensorSize,
    this.sensorType,
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

  /// Display string — the picked material's name, plus its variant in
  /// parens if it has one (see [BomRevisionLineFormScreen._itemLabelFor]).
  /// Unchanged by the Lumax-format fields below: Sun_BOM's "Item" column
  /// keeps reading this exactly as before.
  final String item;

  /// The plain picked material name, without any variant suffix — unlike
  /// [item], which may have "(DN25 · Wired)" appended. Needed as a genuinely
  /// separate field for Lumax's "Materials" column; recovering it by
  /// stripping [item]'s suffix would be a string-splitting guess.
  final String materialName;

  /// Copied from the picked catalog row's [MaterialMasterItem.itemLabel].
  final String itemLabel;

  /// Copied from the picked catalog row, if it has one set. Most D/E/G
  /// catalog rows won't (they're general line items, not sensor-variant
  /// specific), so this is usually null.
  final SensorSize? sensorSize;
  final SensorType? sensorType;

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
    materialName: materialName,
    itemLabel: itemLabel,
    sensorSize: sensorSize,
    sensorType: sensorType,
    unit: unit,
    qtyDelta: qtyDelta,
    group: group,
  );
}
