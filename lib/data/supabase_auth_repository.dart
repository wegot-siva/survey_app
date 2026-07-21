import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_role.dart';
import '../services/supabase_service.dart';
import 'auth_repository.dart';

/// [AuthRepository] backed by real per-user Supabase Auth accounts (Slice
/// 1b). Every user signs in with their own email/password; their role is
/// never chosen by them — it's looked up from `profiles` after sign-in.
class SupabaseAuthRepository implements AuthRepository {
  const SupabaseAuthRepository(this._supabase);

  final SupabaseService _supabase;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Same configured/initialized guard [SyncService] and [SupabaseService]
  /// already use — surfaces the missing-.env landmine with the same message
  /// rather than letting `Supabase.instance` throw a raw assertion error.
  Future<void> _ensureReady() async {
    if (!_supabase.isConfigured) {
      throw const AuthFailure(
        'Supabase is not configured.\n\n'
        'SUPABASE_URL and SUPABASE_ANON_KEY are empty. Copy .env.example to '
        '.env, fill in your values, and run:\n\n'
        '    flutter run --dart-define-from-file=.env',
      );
    }
    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      throw const AuthFailure('Supabase failed to initialize. Check your keys in .env.');
    }
  }

  @override
  Future<AuthenticatedUser> signIn(String email, String password) async {
    await _ensureReady();

    final User? user;
    try {
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      user = response.user;
    } on AuthRetryableFetchException {
      throw const AuthFailure(
        'Could not reach the sign-in server. Check your internet connection '
        'and try again — a first sign-in needs a network connection.',
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }

    if (user == null) {
      throw const AuthFailure('Sign-in failed. Please try again.');
    }
    return _resolveProfile(user.id);
  }

  @override
  Future<void> signOut() async {
    if (!_supabase.isConfigured || !_supabase.isInitialized) return;
    await _auth.signOut();
  }

  @override
  Future<AuthenticatedUser?> currentUser() async {
    if (!_supabase.isConfigured) return null;
    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) return null;

    final userId = _auth.currentSession?.user.id;
    if (userId == null) return null;
    try {
      return await _resolveProfile(userId);
    } on AuthFailure {
      // A session exists but its profile can't be resolved (deleted/
      // deactivated account, or a transient network hiccup on restore) —
      // treat as logged out rather than surface an error before the user
      // has done anything.
      return null;
    }
  }

  @override
  Stream<AuthenticatedUser?> get authStateChanges {
    if (!_supabase.isConfigured || !_supabase.isInitialized) {
      return const Stream.empty();
    }
    return _auth.onAuthStateChange.asyncMap((state) async {
      final userId = state.session?.user.id;
      if (userId == null) return null;
      try {
        return await _resolveProfile(userId);
      } on AuthFailure {
        return null;
      }
    });
  }

  /// Looks up [userId]'s role/name in `profiles`. Throws [AuthFailure] if
  /// there's no matching row, the account is deactivated, or `role` isn't
  /// one of the 4 recognized values — each with its own clear message,
  /// since every one of these means the signed-in account isn't usable yet
  /// (e.g. an Auth user created without ever setting up their profile row).
  Future<AuthenticatedUser> _resolveProfile(String userId) async {
    final Map<String, dynamic> row;
    try {
      row = await Supabase.instance.client
          .from('profiles')
          .select('full_name, role, active')
          .eq('id', userId)
          .single();
    } on PostgrestException {
      throw const AuthFailure(
        'Signed in, but no profile was found for this account. '
        'Contact your admin to finish setting up your account.',
      );
    }

    if (row['active'] != true) {
      await _auth.signOut();
      throw const AuthFailure('This account has been deactivated. Contact your admin.');
    }

    final roleName = row['role'] as String?;
    UserRole? role;
    for (final r in UserRole.values) {
      if (r.name == roleName) {
        role = r;
        break;
      }
    }
    if (role == null) {
      throw AuthFailure(
        'This account has an unrecognized role ("$roleName"). Contact your admin.',
      );
    }

    return AuthenticatedUser(
      userId: userId,
      fullName: (row['full_name'] as String?) ?? '',
      role: role,
    );
  }
}
