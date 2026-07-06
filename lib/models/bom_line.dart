import 'material_master_item.dart';
import 'survey_options.dart';

/// One computed line of a generated BoM — output of [BomEngine], never stored
/// (except when copied into a [BomSnapshotLine] at Finalize time).
class BomLine {
  const BomLine({
    required this.group,
    required this.materialName,
    this.sku = '',
    this.itemLabel = '',
    required this.variantLabel,
    this.sensorSize,
    this.sensorType,
    required this.quantity,
    required this.unit,
  });

  final MaterialGroup group;
  final String materialName;

  /// Copied straight from the source [MaterialMasterItem] row — not shown by
  /// the existing preview UI, but available so Finalize can carry it into a
  /// frozen snapshot line without a second lookup.
  final String sku;

  /// Copied straight from [MaterialMasterItem.itemLabel] — same reasoning
  /// as [sku]: not shown on-screen, only carried through for Finalize.
  final String itemLabel;

  /// e.g. "DN25 · Wired", or "—" for a row not tied to a specific variant.
  final String variantLabel;

  /// Copied straight from the source [MaterialMasterItem] row (the raw
  /// enums [variantLabel] is formatted from) — so Finalize can freeze the
  /// structured variant, not just its display string.
  final SensorSize? sensorSize;
  final SensorType? sensorType;

  final double quantity;
  final String unit;
}
