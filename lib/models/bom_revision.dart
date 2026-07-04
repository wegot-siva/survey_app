/// One additive delta layer on top of a survey's locked v1 [BomSnapshot].
/// Version starts at 2 (v1 is the snapshot itself, not a row in this table)
/// and increases by 1 each time [SurveyRepository.addBomRevision] is called.
/// Like a snapshot, a revision's own row and its [BomRevisionLine]s never
/// change after creation — a later correction is a NEW revision, not an edit
/// to this one.
class BomRevision {
  const BomRevision({
    required this.id,
    required this.surveyId,
    required this.version,
    required this.reason,
    required this.createdBy,
    required this.createdAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;
  final String surveyId;

  /// 2, 3, 4, ... — v1 is the [BomSnapshot], not a row in this table.
  final int version;

  /// Required: why this change was made (e.g. "wall broken, extra elbows").
  final String reason;

  /// Label of the role that created this revision (e.g. "Engineer") —
  /// shared-login roles for now, not a real per-user identity.
  final String createdBy;

  final DateTime createdAt;

  BomRevision copyWithId(String newId) => BomRevision(
    id: newId,
    surveyId: surveyId,
    version: version,
    reason: reason,
    createdBy: createdBy,
    createdAt: createdAt,
  );
}
