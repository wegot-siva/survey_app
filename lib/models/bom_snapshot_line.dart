import 'material_master_item.dart';
import 'survey_options.dart';

/// Whether a frozen [BomSnapshotLine] came from the auto-computed BoM
/// (A/B/C/F, via [BomEngine]) or a hand-added D/E/G [BomManualEntry]. `.name`
/// is the literal 'auto' / 'manual' stored in the DB.
enum BomSnapshotSource {
  auto('Auto-computed'),
  manual('Manual entry');

  const BomSnapshotSource(this.label);
  final String label;
}

/// One frozen line of a [BomSnapshot]. Values are copied in at finalize
/// time — never re-derived from Material Master or bom_manual_entries
/// afterward, so editing either later cannot alter an existing snapshot.
class BomSnapshotLine {
  const BomSnapshotLine({
    required this.id,
    required this.snapshotId,
    this.sku = '',
    required this.item,
    this.materialName = '',
    this.itemLabel = '',
    this.sensorSize,
    this.sensorType,
    required this.unit,
    required this.qty,
    required this.group,
    required this.source,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// Empty string until the parent [BomSnapshot] itself is created — the
  /// repository assigns this alongside [id] in the same write. See
  /// [copyWithIds].
  final String snapshotId;

  final String sku;

  /// Display string — unchanged by the Lumax-format fields below: Sun_BOM's
  /// "Item" column keeps reading this exactly as before.
  final String item;

  /// The plain material name, without any variant suffix — needed as a
  /// genuinely separate field for Lumax's "Materials" column; recovering it
  /// by stripping [item]'s suffix would be a string-splitting guess.
  final String materialName;

  /// Copied from the source [MaterialMasterItem.itemLabel] (auto lines) or
  /// the picked catalog row (manual entries) at finalize time.
  final String itemLabel;

  /// Frozen from the source at finalize time — null for manual entries whose
  /// catalog row had no variant set (the common case for D/E/G items).
  final SensorSize? sensorSize;
  final SensorType? sensorType;

  final String unit;
  final double qty;
  final MaterialGroup group;
  final BomSnapshotSource source;

  /// Returns a copy with both ids filled in. Used when the repository
  /// persists a freshly-built line as part of finalizing a snapshot — [id]
  /// and [snapshotId] are both unknown to the caller until that moment.
  BomSnapshotLine copyWithIds({required String id, required String snapshotId}) =>
      BomSnapshotLine(
        id: id,
        snapshotId: snapshotId,
        sku: sku,
        item: item,
        materialName: materialName,
        itemLabel: itemLabel,
        sensorSize: sensorSize,
        sensorType: sensorType,
        unit: unit,
        qty: qty,
        group: group,
        source: source,
      );
}
