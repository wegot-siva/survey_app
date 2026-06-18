import 'client_inputs.dart';

/// A surveyed site. Blocks are simple repeatable text entries for Phase 0.
/// [clientInputs] is the single Client inputs form for this site (null until saved).
class Site {
  const Site({
    required this.id,
    required this.name,
    this.blocks = const [],
    this.clientInputs,
  });

  final String id;
  final String name;
  final List<String> blocks;
  final ClientInputs? clientInputs;

  Site copyWith({
    String? name,
    List<String>? blocks,
    ClientInputs? clientInputs,
  }) {
    return Site(
      id: id,
      name: name ?? this.name,
      blocks: blocks ?? this.blocks,
      clientInputs: clientInputs ?? this.clientInputs,
    );
  }
}
