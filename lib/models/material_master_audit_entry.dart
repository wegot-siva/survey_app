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

  /// Label of the role that made the change (e.g. "Admin") — shared-login
  /// roles for now, not a real per-user identity.
  final String changedByRole;

  final DateTime changedAt;

  MaterialMasterAuditEntry copyWithId(String newId) => MaterialMasterAuditEntry(
    id: newId,
    materialRowId: materialRowId,
    fieldChanged: fieldChanged,
    oldValue: oldValue,
    newValue: newValue,
    changedByRole: changedByRole,
    changedAt: changedAt,
  );
}
