import 'client_inputs.dart';

/// A surveyed site. Blocks are simple repeatable text entries for Phase 0.
/// [clientInputs] is the single Client inputs form for this site (null until saved).
class Site {
  const Site({
    required this.id,
    required this.name,
    this.blocks = const [],
    this.clientInputs,
    this.status,
    this.assignedTo,
    this.bomLocked = false,
    this.archived = false,
    this.address = '',
    this.clientName = '',
    this.clientContact = '',
  });

  final String id;
  final String name;
  final List<String> blocks;
  final ClientInputs? clientInputs;

  /// Lifecycle stage set by the assignment workflow (see [SurveyStatus]).
  /// Null until Sales assigns the survey.
  final String? status;

  /// The engineer this survey is assigned to (a name from the hardcoded
  /// engineer directory — see Roles & Assignment Slice B). Null until assigned.
  final String? assignedTo;

  /// Whether this survey's BoM has been finalized (Finalize phase). Set by
  /// [SurveyRepository.finalizeBom] alongside writing the [BomSnapshot] —
  /// never toggled by [copyWith]/[SurveyRepository.updateSite] directly, since
  /// there is no unlock/re-finalize flow yet.
  final bool bomLocked;

  /// Soft-delete flag — Sales' "Delete site" sets this instead of removing
  /// the row, so no FK'd survey/BoM/photo data is ever destroyed. See
  /// [SurveyRepository.getSites].
  final bool archived;

  /// Site-level metadata Sales can edit post-creation via "Edit site
  /// details" — distinct from [clientInputs], which is the field engineer's
  /// own Client Inputs survey section filled in during the visit.
  final String address;
  final String clientName;
  final String clientContact;

  Site copyWith({
    String? name,
    List<String>? blocks,
    ClientInputs? clientInputs,
    String? status,
    String? assignedTo,
    bool? archived,
    String? address,
    String? clientName,
    String? clientContact,
  }) {
    return Site(
      id: id,
      name: name ?? this.name,
      blocks: blocks ?? this.blocks,
      clientInputs: clientInputs ?? this.clientInputs,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      bomLocked: bomLocked,
      archived: archived ?? this.archived,
      address: address ?? this.address,
      clientName: clientName ?? this.clientName,
      clientContact: clientContact ?? this.clientContact,
    );
  }
}
