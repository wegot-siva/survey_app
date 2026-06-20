import '../models/user_role.dart';

/// The single seam for authentication. Slice A uses a local shared-password
/// implementation; a later slice can swap in real per-user auth (e.g. Supabase
/// Auth) without touching the UI or [SessionController].
///
/// PROJECT RULE: UI never authenticates directly — it goes through a
/// [SessionController] which delegates here.
abstract class AuthRepository {
  /// Returns true if [password] is valid for the shared [role] account.
  Future<bool> authenticate(UserRole role, String password);
}
