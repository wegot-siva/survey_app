import 'package:flutter/foundation.dart';

import '../data/auth_repository.dart';
import '../models/user_role.dart';

/// Holds "who is logged in" as app state, so any screen can read the current
/// role. Delegates credential checks to an [AuthRepository].
///
/// In-memory only for Slice A — the session is not persisted, so the app shows
/// the login screen on every launch.
class SessionController extends ChangeNotifier {
  SessionController(this._auth);

  final AuthRepository _auth;

  UserRole? _currentRole;
  String? _currentEngineerName;

  /// The role currently signed in, or null when logged out.
  UserRole? get currentRole => _currentRole;

  /// Which engineer the shared Engineer login is simulating (Slice C). Only
  /// meaningful when [currentRole] is [UserRole.engineer]; null otherwise.
  String? get currentEngineerName => _currentEngineerName;

  bool get isLoggedIn => _currentRole != null;

  /// Attempts to sign in as [role]. [engineerName] is required to mean
  /// anything when [role] is [UserRole.engineer] — it's how the shared
  /// Engineer login simulates "being" a specific engineer until per-user
  /// accounts exist. Returns null on success, or a human-readable error
  /// message on failure.
  Future<String?> login(
    UserRole role,
    String password, {
    String? engineerName,
  }) async {
    final ok = await _auth.authenticate(role, password);
    if (!ok) return 'Incorrect password for ${role.label}.';
    _currentRole = role;
    _currentEngineerName = role == UserRole.engineer ? engineerName : null;
    notifyListeners();
    return null;
  }

  /// Signs out, returning to the login screen.
  void logout() {
    _currentRole = null;
    _currentEngineerName = null;
    notifyListeners();
  }
}
