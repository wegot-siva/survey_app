/// One row of a survey's reassignment history.
///
/// Written every time `SurveyRepository.reassignSurvey` changes who a survey
/// is assigned to. Reassignment only ever fires while the survey's status is
/// `'assigned'` (enforced by the repository), so in practice [oldAssignee] is
/// always non-null by the time this is written — nullable defensively rather
/// than by design.
class SurveyAssignmentAuditEntry {
  const SurveyAssignmentAuditEntry({
    required this.id,
    required this.siteId,
    this.oldAssignee,
    required this.newAssignee,
    required this.changedByRole,
    required this.changedAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// The site (survey) this reassignment happened on.
  final String siteId;

  final String? oldAssignee;
  final String newAssignee;

  /// Label of the role that made the change (e.g. "Sales") — shared-login
  /// roles for now, not a real per-user identity.
  final String changedByRole;

  final DateTime changedAt;

  SurveyAssignmentAuditEntry copyWithId(String newId) =>
      SurveyAssignmentAuditEntry(
        id: newId,
        siteId: siteId,
        oldAssignee: oldAssignee,
        newAssignee: newAssignee,
        changedByRole: changedByRole,
        changedAt: changedAt,
      );
}
