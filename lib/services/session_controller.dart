import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_repository.dart';
import '../models/user_role.dart';

/// Holds "who is logged in" as app state, so any screen can read the current
/// user/role. Delegates every credential check, and session persistence, to
/// an [AuthRepository] — persistence is Supabase's own (see
/// [AuthRepository.currentUser] / [AuthRepository.authStateChanges]), not a
/// custom store, since a real Auth SDK already does this correctly.
class SessionController extends ChangeNotifier {
  SessionController(this._auth);

  final AuthRepository _auth;
  StreamSubscription<AuthenticatedUser?>? _authSub;

  AuthenticatedUser? _currentUser;

  /// The role currently signed in, or null when logged out. Kept as its own
  /// getter (derived from [_currentUser]) so every existing role-gate check
  /// across the app (`session.currentRole == UserRole.x`) keeps working
  /// unchanged.
  UserRole? get currentRole => _currentUser?.role;

  /// The signed-in user's id (`auth.uid()` / `profiles.id`), or null when
  /// logged out. Not yet read anywhere — Slice 1c (assignment) and Slice 1d
  /// (attribution) are what wire this in.
  String? get currentUserId => _currentUser?.userId;

  /// The signed-in user's real name, or null when logged out.
  String? get currentUserName => _currentUser?.fullName;

  bool get isLoggedIn => _currentUser != null;

  /// Restores a persisted session (if any) from Supabase's own session
  /// storage, so an app close/reopen while still signed in skips the login
  /// screen. Call once at startup, before anything reads [isLoggedIn].
  ///
  /// Also subscribes to [AuthRepository.authStateChanges] so a token
  /// refresh/expiry or a sign-out triggered elsewhere (not through this
  /// [logout]) is reflected here too, not just at startup.
  Future<void> restore() async {
    _currentUser = await _auth.currentUser();
    notifyListeners();

    _authSub ??= _auth.authStateChanges.listen((user) {
      _currentUser = user;
      notifyListeners();
    });
  }

  /// Attempts to sign in with [email]/[password]. Returns null on success,
  /// or a human-readable error message on failure (wrong credentials, no
  /// profile, no network on a first sign-in).
  Future<String?> login(String email, String password) async {
    try {
      _currentUser = await _auth.signIn(email, password);
      notifyListeners();
      return null;
    } on AuthFailure catch (e) {
      return e.message;
    } catch (e) {
      return 'Something went wrong signing in: $e';
    }
  }

  /// Signs out, returning to the login screen.
  Future<void> logout() async {
    await _auth.signOut();
    _currentUser = null;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_authSub?.cancel());
    super.dispose();
  }
}
