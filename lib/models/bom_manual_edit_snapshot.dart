/// A full BoM version created by Admin/Approver manually editing any field
/// (SKU, name, description, unit, qty) of a resolved version's line items.
/// Unlike a [BomRevision] (an additive delta, since it can't safely rename or
/// re-key a line), this is a complete, immutable replacement line list — the
/// new latest version. A survey can have any number of these interleaved with
/// revisions; [version] is drawn from the same counter both use, so numbers
/// never collide. Like a snapshot or revision, this row and its
/// [BomManualEditSnapshotLine]s never change after creation — a later
/// correction is a new manual edit, not an edit to this one.
class BomManualEditSnapshot {
  const BomManualEditSnapshot({
    required this.id,
    required this.surveyId,
    required this.version,
    required this.basedOnVersion,
    required this.editedBy,
    required this.editedAt,
    this.reason = '',
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;
  final String surveyId;

  /// 2, 3, 4, ... — shares its numbering with [BomRevision.version]; never 1
  /// (that's always the original [BomSnapshot]).
  final int version;

  /// The version this edit's starting line list was resolved from — recorded
  /// for traceability only; version resolution itself only needs [version].
  final int basedOnVersion;

  /// Label of the role that made this edit (e.g. "Approver") — shared-login
  /// roles for now, not a real per-user identity.
  final String editedBy;

  final DateTime editedAt;

  /// Why this manual edit was made (e.g. "corrected SKU on pump fitting").
  final String reason;

  BomManualEditSnapshot copyWithId(String newId) => BomManualEditSnapshot(
    id: newId,
    surveyId: surveyId,
    version: version,
    basedOnVersion: basedOnVersion,
    editedBy: editedBy,
    editedAt: editedAt,
    reason: reason,
  );
}
