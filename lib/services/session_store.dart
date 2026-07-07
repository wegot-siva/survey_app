import '../models/user_role.dart';

/// Persists "who is logged in" across app restarts.
///
/// Not per-user auth — this only remembers which shared-per-role login (see
/// [UserRole]) was last active, so the app can skip the login screen after a
/// simple app close/reopen. Kept behind a seam, like [AuthRepository], so
/// [SessionController] stays testable without touching real storage: the
/// production app uses [SharedPreferencesSessionStore]; tests get a no-op by
/// simply not passing a store to [SessionController]'s constructor.
abstract class SessionStore {
  /// The persisted session, or null if none (never logged in yet, or logged
  /// out explicitly since the last one).
  Future<({UserRole role, String? engineerName})?> load();

  /// Persists [role] (and [engineerName], meaningful only for
  /// [UserRole.engineer]) as the active session.
  Future<void> save(UserRole role, String? engineerName);

  /// Clears any persisted session. Called on explicit logout — after this,
  /// the next app start shows the login screen rather than restoring.
  Future<void> clear();
}
