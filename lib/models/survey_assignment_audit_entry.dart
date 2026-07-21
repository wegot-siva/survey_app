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
    this.oldAssigneeUserId,
    required this.newAssignee,
    required this.newAssigneeUserId,
    required this.changedByRole,
    this.changedByUserId,
    required this.changedAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;

  /// The site (survey) this reassignment happened on.
  final String siteId;

  /// Name snapshots at the time of the change — kept alongside the user-id
  /// columns below so history reads correctly even if an account is later
  /// renamed or deactivated. See [Site.assignedTo] for the same pattern.
  final String? oldAssignee;
  final String newAssignee;

  /// Real account ids (`profiles.id`). [oldAssigneeUserId] is null exactly
  /// when [oldAssignee] is (no prior assignee), or for a pre-Slice-1c
  /// assignment made before real accounts existed.
  final String? oldAssigneeUserId;
  final String? newAssigneeUserId;

  /// Display snapshot of who made the change (not who it was assigned
  /// to/from — see [newAssignee] for that) — the signed-in user's real name
  /// (Roles & Assignment Slice 1d) going forward; a bare role label (e.g.
  /// "Sales") on any row written before that slice.
  final String changedByRole;

  /// The real account id (`profiles.id`) of whoever made the change. Null on
  /// any row written before Slice 1d.
  final String? changedByUserId;

  final DateTime changedAt;

  SurveyAssignmentAuditEntry copyWithId(String newId) =>
      SurveyAssignmentAuditEntry(
        id: newId,
        siteId: siteId,
        oldAssignee: oldAssignee,
        oldAssigneeUserId: oldAssigneeUserId,
        newAssignee: newAssignee,
        newAssigneeUserId: newAssigneeUserId,
        changedByRole: changedByRole,
        changedByUserId: changedByUserId,
        changedAt: changedAt,
      );
}
