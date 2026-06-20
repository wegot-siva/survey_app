/// The roles a user can sign in as (Roles & Assignment — Slice A).
///
/// Shared-per-role login for now: one shared account per role, not real
/// per-user auth. The enum `.name` is the stable key used for storage / lookup.
enum UserRole {
  sales('Sales'),
  engineer('Engineer'),
  approver('Approver');

  const UserRole(this.label);

  /// Human-readable label shown in the UI.
  final String label;
}
