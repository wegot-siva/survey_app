import 'package:supabase_flutter/supabase_flutter.dart';

/// One invite code as an Admin sees it.
///
/// Mirrors `public.signup_invites`. The row is only ever readable by an
/// Admin — RLS grants SELECT to nobody else, and there is no policy at all
/// for anon — so this model never reaches an unauthenticated caller.
class SignupInvite {
  const SignupInvite({
    required this.id,
    required this.code,
    required this.roleAllowed,
    required this.createdAt,
    required this.expiresAt,
    required this.maxUses,
    required this.uses,
    required this.revokedAt,
  });

  factory SignupInvite.fromRow(Map<String, dynamic> r) => SignupInvite(
        id: r['id'] as String,
        code: r['code'] as String,
        roleAllowed: r['role_allowed'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        expiresAt: r['expires_at'] == null
            ? null
            : DateTime.parse(r['expires_at'] as String),
        maxUses: (r['max_uses'] as num).toInt(),
        uses: (r['uses'] as num).toInt(),
        revokedAt: r['revoked_at'] == null
            ? null
            : DateTime.parse(r['revoked_at'] as String),
      );

  final String id;
  final String code;
  final String roleAllowed;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int maxUses;
  final int uses;
  final DateTime? revokedAt;

  /// Why a code can no longer be used, or null while it still can.
  ///
  /// Derived here rather than stored, so it can never drift out of step with
  /// the conditions `validate_signup_invite` actually applies. The order
  /// matters only for display — a revoked code that also expired reads as
  /// "Revoked", which is the more deliberate of the two.
  String? get inactiveReason {
    if (revokedAt != null) return 'Revoked';
    if (expiresAt != null && !expiresAt!.isAfter(DateTime.now())) {
      return 'Expired';
    }
    if (uses >= maxUses) return 'Used';
    return null;
  }

  bool get isUsable => inactiveReason == null;
}

/// Admin-side invite code operations.
///
/// Deliberately its own data source rather than another method cluster on
/// [SupabaseSurveyDataSource]: none of this is survey data, none of it syncs,
/// and every call here is a privileged RPC rather than a table read/write.
///
/// Every mutation goes through a SECURITY DEFINER function. The table has no
/// INSERT/UPDATE/DELETE policy for ANY role, so a code cannot be minted or
/// edited by a direct write — not even by an Admin, who could otherwise reset
/// `uses` and defeat single-use. The functions re-check `is_admin()`
/// themselves, so the client is never the thing enforcing this.
class SignupInviteDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// Mints a new code and returns it. Admin only — the RPC raises
  /// `insufficient_privilege` for anyone else, regardless of what the UI
  /// allowed.
  ///
  /// Generated server-side on purpose: the APK is inspectable, so a
  /// client-side generator would hand an attacker the algorithm.
  Future<String> createInvite({
    required String roleAllowed,
    DateTime? expiresAt,
    int maxUses = 1,
  }) async {
    final code = await _client.rpc<dynamic>(
      'create_signup_invite',
      params: {
        'p_role_allowed': roleAllowed,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_max_uses': maxUses,
      },
    );
    return code as String;
  }

  /// Marks a code revoked. Returns false if it was already revoked, so the
  /// UI can stay quiet rather than claiming it did something.
  Future<bool> revokeInvite(String id) async {
    final ok = await _client.rpc<dynamic>(
      'revoke_signup_invite',
      params: {'p_id': id},
    );
    return ok == true;
  }

  /// Every code, newest first. Returns empty for a non-Admin — RLS filters
  /// the rows rather than raising, so this is not an error path.
  Future<List<SignupInvite>> fetchInvites() async {
    final rows = await _client
        .from('signup_invites')
        .select()
        .order('created_at', ascending: false);
    return rows
        .map((r) => SignupInvite.fromRow(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  /// Checks a code without consuming it. Callable without a session — this
  /// is what Slice 3's signup screen will use before any account exists.
  ///
  /// Returns the permitted role for a usable code, or null for anything
  /// else. Every failure looks identical by design: unknown, expired,
  /// revoked and exhausted all return null, so this cannot be used to probe
  /// which codes exist.
  Future<String?> validateInvite(String code) async {
    final rows = await _client.rpc<dynamic>(
      'validate_signup_invite',
      params: {'p_code': code},
    );
    if (rows is! List || rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    return row['valid'] == true ? row['role_allowed'] as String? : null;
  }
}
