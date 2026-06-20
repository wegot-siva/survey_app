/// Survey lifecycle stages (Roles & Assignment).
///
/// Stored as plain text in `sites.status` (column added in Phase 2, used
/// starting Slice B). Kept as string constants rather than an enum so the
/// raw value written to SQLite/Supabase is always the constant itself — no
/// `.name` mapping to keep in sync across two stores.
class SurveyStatus {
  const SurveyStatus._();

  static const assigned = 'assigned';
  static const inProgress = 'in_progress';
  static const submitted = 'submitted';
  static const approved = 'approved';
  static const released = 'released';

  /// The order surveys move through. Sales sets [assigned]; later slices move
  /// a survey through the rest.
  static const order = [assigned, inProgress, submitted, approved, released];

  static String label(String? status) {
    switch (status) {
      case assigned:
        return 'Assigned';
      case inProgress:
        return 'In progress';
      case submitted:
        return 'Submitted';
      case approved:
        return 'Approved';
      case released:
        return 'Released';
      default:
        return 'Not assigned';
    }
  }
}
