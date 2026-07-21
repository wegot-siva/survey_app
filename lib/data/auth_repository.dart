import '../models/user_role.dart';

/// One successful sign-in: the authenticated user's real identity plus the
/// role resolved from their `profiles` row.
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.userId,
    required this.fullName,
    required this.role,
  });

  /// The Supabase Auth user's id (`auth.uid()` — also `profiles.id`).
  final String userId;
  final String fullName;
  final UserRole role;
}

/// Thrown by [AuthRepository] on any sign-in failure — wrong credentials, no
/// matching/active `profiles` row, or no network on a first sign-in. Always
/// carries a [message] safe to show directly to the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The single seam for authentication (Slice 1b: real per-user Supabase
/// Auth, replacing Slice A's shared-per-role password check).
///
/// PROJECT RULE: UI never authenticates directly — it goes through a
/// [SessionController] which delegates here.
abstract class AuthRepository {
  /// Signs in with [email]/[password], then resolves the signed-in user's
  /// role from `profiles`. Throws [AuthFailure] with a human-readable
  /// message on any failure — never returns null or a sentinel value.
  Future<AuthenticatedUser> signIn(String email, String password);

  Future<void> signOut();

  /// The currently-authenticated user, resolved from Supabase's own
  /// persisted session — null if nothing is signed in (including when
  /// Supabase isn't configured at all). Used by [SessionController.restore]
  /// so an app close/reopen while still signed in skips the login screen.
  Future<AuthenticatedUser?> currentUser();

  /// Fires whenever Supabase's own auth state changes after startup — a
  /// token refresh, a session expiring, or a sign-out triggered elsewhere.
  /// [SessionController] listens to this so the app's session state never
  /// drifts from what Supabase actually has.
  Stream<AuthenticatedUser?> get authStateChanges;
}
