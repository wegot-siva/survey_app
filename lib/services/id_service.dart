import 'package:uuid/uuid.dart';

/// Generates unique ids. Wrapping [Uuid] here keeps id generation out of the
/// repository internals and makes it trivial to stub in tests.
class IdService {
  IdService([Uuid? uuid]) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;

  String newId() => _uuid.v4();
}
