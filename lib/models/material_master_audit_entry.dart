/// One row of the Material Master change log.
///
/// A create or delete writes a single summary row (field_changed = '(created)'
/// / '(deleted)', with the other side of the change left null). An edit writes
/// one row per field that actually changed, so the log reads as a literal
/// field-level diff — see `material_master_diff.dart`.
class MaterialMasterAuditEntry {
  const MaterialMasterAuditEntry({
    required this.id,
    required this.materialRowId,
    required this.fieldChanged,
    this.oldValue,
    this.newValue,
    required this.changedByRole,
    this.changedByUserId,
    required this.changedAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// The Material Master row this entry is about. Kept even after that row is
  /// deleted, so the delete's own audit row (and any earlier edits) survive.
  final String materialRowId;

  final String fieldChanged;
  final String? oldValue;
  final String? newValue;

  /// Display snapshot of who made the change — the signed-in user's real
  /// name (Roles & Assignment Slice 1d) going forward; a bare role label
  /// (e.g. "Admin") on any row written before that slice. [changedByUserId]
  /// is the real source of truth for new rows; null on old ones.
  final String changedByRole;

  /// The real account id (`profiles.id`) that made the change. Null on any
  /// row written before Slice 1d.
  final String? changedByUserId;

  final DateTime changedAt;

  MaterialMasterAuditEntry copyWithId(String newId) => MaterialMasterAuditEntry(
    id: newId,
    materialRowId: materialRowId,
    fieldChanged: fieldChanged,
    oldValue: oldValue,
    newValue: newValue,
    changedByRole: changedByRole,
    changedByUserId: changedByUserId,
    changedAt: changedAt,
  );
}
