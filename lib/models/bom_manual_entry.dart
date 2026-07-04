import 'material_master_item.dart';

/// Groups the "Add materials" picker allows a manual entry to be filed under.
/// Only D (Plumbing rework), E (Electrical), and G (Labour) — the auto-computed
/// BoM already covers A/B/C/F from survey data; this picker is strictly for
/// hand-added extras in those three sections.
const List<MaterialGroup> kBomManualEntryGroups = [
  MaterialGroup.d,
  MaterialGroup.e,
  MaterialGroup.g,
];

/// A manually-added BoM line for one survey, filed under D/E/G via the "Add
/// materials" picker. Distinct from [BomLine] (the read-only, computed-only
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
    required this.unit,
    required this.qty,
    required this.group,
    required this.addedBy,
    required this.addedAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// The site/survey this entry belongs to.
  final String surveyId;

  final String materialName;
  final String sku;
  final String unit;
  final double qty;

  /// Always one of [kBomManualEntryGroups] — enforced by the picker UI, not
  /// this model.
  final MaterialGroup group;

  /// Label of the role that added this entry (e.g. "Engineer") — shared-login
  /// roles for now, not a real per-user identity. Preserved across edits.
  final String addedBy;

  /// When this entry was first added. Preserved across edits.
  final DateTime addedAt;

  /// Returns a copy with a different [id]. Used when the repository assigns
  /// an id to a freshly added entry.
  BomManualEntry copyWithId(String newId) => BomManualEntry(
    id: newId,
    surveyId: surveyId,
    materialName: materialName,
    sku: sku,
    unit: unit,
    qty: qty,
    group: group,
    addedBy: addedBy,
    addedAt: addedAt,
  );
}
