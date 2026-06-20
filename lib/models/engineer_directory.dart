/// Hardcoded engineer directory (Roles & Assignment — Slice B placeholder).
///
/// There are no real per-user accounts yet (see [UserRole] — Engineer is a
/// shared login), so Sales picks an engineer by name from this fixed list
/// rather than a real assignee lookup. Replace with a repository-backed
/// directory once per-user accounts exist.
const List<String> kEngineerDirectory = [
  'Ravi Kumar',
  'Priya Sharma',
  'Arjun Mehta',
  'Sneha Iyer',
];
