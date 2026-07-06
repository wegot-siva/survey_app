/// One entry in the lightweight engineer roster Sales assigns/reassigns
/// surveys against (reassignment slice).
///
/// A roster, not an auth system: there is still only one shared Engineer
/// login (see `UserRole.engineer` / `SessionController.currentEngineerName`).
/// [name] is the plain string stored on `Site.assignedTo` — this table's only
/// job is listing valid choices for that field, not acting as a real
/// foreign-key target.
class Engineer {
  const Engineer({required this.id, required this.name});

  final String id;
  final String name;
}
