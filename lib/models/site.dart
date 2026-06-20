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

  Site copyWith({
    String? name,
    List<String>? blocks,
    ClientInputs? clientInputs,
    String? status,
    String? assignedTo,
  }) {
    return Site(
      id: id,
      name: name ?? this.name,
      blocks: blocks ?? this.blocks,
      clientInputs: clientInputs ?? this.clientInputs,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
    );
  }
}
