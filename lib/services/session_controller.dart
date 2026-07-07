import 'package:flutter/foundation.dart';

import '../data/auth_repository.dart';
import '../models/user_role.dart';
import 'session_store.dart';

/// A [SessionStore] that persists nothing. The default when
/// [SessionController] is constructed without a real store (every existing
/// test does this), so those callers keep their exact prior in-memory-only
/// behavior with no shared_preferences access at all.
class _NoopSessionStore implements SessionStore {
  const _NoopSessionStore();

  @override
  Future<({UserRole role, String? engineerName})?> load() async => null;

  @override
  Future<void> save(UserRole role, String? engineerName) async {}

  @override
  Future<void> clear() async {}
}

/// Holds "who is logged in" as app state, so any screen can read the current
/// role. Delegates credential checks to an [AuthRepository] and persistence
/// (surviving an app close/reopen) to a [SessionStore].
///
/// [store] is optional and defaults to a no-op — pass a real store (e.g.
/// [SharedPreferencesSessionStore]) in production; leave it unset in tests
/// that only care about in-memory session state.
class SessionController extends ChangeNotifier {
  SessionController(this._auth, [SessionStore? store])
    : _store = store ?? const _NoopSessionStore();

  final AuthRepository _auth;
  final SessionStore _store;

  UserRole? _currentRole;
  String? _currentEngineerName;

  /// The role currently signed in, or null when logged out.
  UserRole? get currentRole => _currentRole;

  /// Which engineer the shared Engineer login is simulating (Slice C). Only
  /// meaningful when [currentRole] is [UserRole.engineer]; null otherwise.
  String? get currentEngineerName => _currentEngineerName;

  bool get isLoggedIn => _currentRole != null;

  /// Restores a persisted session (if any), so an app close/reopen while
  /// still "logged in" skips the login screen. Call once at startup, before
  /// anything reads [isLoggedIn] — a no-op if nothing was persisted (nobody
  /// had signed in yet, or the last session ended with an explicit
  /// [logout]).
  Future<void> restore() async {
    final persisted = await _store.load();
    if (persisted == null) return;
    _currentRole = persisted.role;
    _currentEngineerName = persisted.engineerName;
    notifyListeners();
  }

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
    await _store.save(role, _currentEngineerName);
    notifyListeners();
    return null;
  }

  /// Signs out, returning to the login screen. Clears the persisted session
  /// first, so a subsequent app close/reopen shows the login screen rather
  /// than restoring.
  Future<void> logout() async {
    _currentRole = null;
    _currentEngineerName = null;
    await _store.clear();
    notifyListeners();
  }
}
