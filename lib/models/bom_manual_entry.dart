import 'material_master_item.dart';
import 'survey_options.dart';

/// Groups the "Add materials" picker allows a manual entry to be filed under.
/// B (DCU/Duct LoRa/cable), C (Plumbing accessories), D (Plumbing rework), E
/// (Electrical), F (Consumables), and G (Labour) — the auto-computed BoM only
/// covers A (WEGOTAqua sensors) from survey data; this picker covers
/// everything else.
const List<MaterialGroup> kBomManualEntryGroups = [
  MaterialGroup.b,
  MaterialGroup.c,
  MaterialGroup.d,
  MaterialGroup.e,
  MaterialGroup.f,
  MaterialGroup.g,
];

/// A manually-added BoM line for one survey, filed under one of
/// [kBomManualEntryGroups] via the "Add materials" picker. Distinct from
/// [BomLine] (the read-only, computed-only
/// output of [BomEngine]): this is a persisted, user-entered record, sourced
/// by name/SKU/unit from a Material Master row at the moment it was picked —
/// not linked back to that row's id, so it survives that row being edited or
/// removed later.
///
/// Mechanics only in this slice: not yet wired into any snapshot/finalize
/// flow, and never affects the computed [BomEngine] output.
class BomManualEntry {
  const BomManualEntry({
    required this.id,
    required this.surveyId,
    required this.materialName,
    this.sku = '',
    this.itemLabel = '',
    this.sensorSize,
    this.sensorType,
    required this.unit,
    required this.qty,
    required this.group,
    required this.addedBy,
    this.addedByUserId,
    required this.addedAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// The site/survey this entry belongs to.
  final String surveyId;

  final String materialName;
  final String sku;

  /// Copied from the picked catalog row's [MaterialMasterItem.itemLabel] at
  /// the moment of selection — same "copied, not linked by id" convention as
  /// [materialName]/[sku]/[unit].
  final String itemLabel;

  /// Copied from the picked catalog row, if it has one set. Most D/E/G
  /// catalog rows won't (they're general line items, not sensor-variant
  /// specific), so this is usually null.
  final SensorSize? sensorSize;
  final SensorType? sensorType;

  final String unit;
  final double qty;

  /// Always one of [kBomManualEntryGroups] — enforced by the picker UI, not
  /// this model.
  final MaterialGroup group;

  /// Display snapshot of who added this entry — the signed-in user's real
  /// name (Roles & Assignment Slice 1d) going forward; a bare role label
  /// (e.g. "Engineer") on any entry added before that slice. Preserved
  /// across edits.
  final String addedBy;

  /// The real account id (`profiles.id`) that added this entry. Null on any
  /// entry added before Slice 1d. Preserved across edits.
  final String? addedByUserId;

  /// When this entry was first added. Preserved across edits.
  final DateTime addedAt;

  /// Returns a copy with a different [id]. Used when the repository assigns
  /// an id to a freshly added entry.
  BomManualEntry copyWithId(String newId) => BomManualEntry(
    id: newId,
    surveyId: surveyId,
    materialName: materialName,
    sku: sku,
    itemLabel: itemLabel,
    sensorSize: sensorSize,
    sensorType: sensorType,
    unit: unit,
    qty: qty,
    group: group,
    addedBy: addedBy,
    addedByUserId: addedByUserId,
    addedAt: addedAt,
  );
}
