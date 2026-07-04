/// Only status this slice ever writes — no revisions/re-finalize flow yet, so
/// there's nothing else a snapshot could be.
const String kBomSnapshotStatusFinal = 'final';

/// An immutable, frozen BoM for one survey (Finalize phase). Version is
/// always 1 in this slice — a later slice adds revisions (version 2+).
///
/// A snapshot's own row never changes after creation; its [BomSnapshotLine]s
/// are the frozen values, copied in at finalize time and never re-derived
/// from Material Master or bom_manual_entries afterward.
class BomSnapshot {
  const BomSnapshot({
    required this.id,
    required this.surveyId,
    this.version = 1,
    this.status = kBomSnapshotStatusFinal,
    required this.finalizedBy,
    required this.finalizedAt,
  });

  /// Empty string means "not yet persisted" (the repository assigns an id).
  final String id;
  final String surveyId;
  final int version;
  final String status;

  /// Label of the role that finalized this BoM (e.g. "Engineer") — shared-login
  /// roles for now, not a real per-user identity.
  final String finalizedBy;

  final DateTime finalizedAt;

  BomSnapshot copyWithId(String newId) => BomSnapshot(
    id: newId,
    surveyId: surveyId,
    version: version,
    status: status,
    finalizedBy: finalizedBy,
    finalizedAt: finalizedAt,
  );
}
