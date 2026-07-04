import 'material_master_item.dart';

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
  final String item;
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
        unit: unit,
        qty: qty,
        group: group,
        source: source,
      );
}
