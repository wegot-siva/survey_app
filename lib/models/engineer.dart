/// One entry in the engineer roster Sales/Approver assigns/reassigns surveys
/// against (Roles & Assignment — Slice 1c).
///
/// [id] is a real account id (`profiles.id` / `auth.uid()`) — this is a thin
/// view over `profiles` rows with `role = 'engineer'`, fetched live via
/// [SyncService.fetchEngineerRoster], not a locally-cached roster. [name] is
/// `profiles.full_name`, snapshotted onto `Site.assignedTo` /
/// `SurveyAssignmentAuditEntry` at the moment of assignment so those stay
/// readable without a join even if the account is later renamed.
class Engineer {
  const Engineer({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is Engineer && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}
