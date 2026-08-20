import 'package:supabase_flutter/supabase_flutter.dart';

/// Submits signup requests.
///
/// Its own data source rather than more methods on an existing one: this is
/// the only call in the app made with **no session at all**, by someone who
/// is not yet a user, and keeping it separate makes that unmistakable.
///
/// There is deliberately no password anywhere in this flow. Supabase's Admin
/// API takes a plaintext password and has no parameter for a pre-computed
/// hash, so a hash stored here could only be used by hand-writing bcrypt into
/// GoTrue's own table — and would in any case just be an offline-crackable
/// credential store guarded by RLS. Approval (Slice 4) issues an invite link
/// instead, so the password only ever exists inside GoTrue.
class SignupRequestDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  /// Submits a request for review. Returns false only when the invite code
  /// itself is unusable, or does not permit the requested role.
  ///
  /// Everything else — including an email that already has an account or an
  /// outstanding request — returns true and writes nothing. That is
  /// deliberate: returning false for those would let anyone holding a single
  /// valid code discover which email addresses are registered. With a valid
  /// code, every email answers identically.
  ///
  /// So `true` means "submitted, or there was nothing to do", never "an
  /// account now exists". No account is created anywhere in this flow.
  Future<bool> submit({
    required String fullName,
    required String email,
    required String requestedRole,
    required String inviteCode,
  }) async {
    final ok = await _client.rpc<dynamic>(
      'request_signup',
      params: {
        'p_full_name': fullName,
        'p_email': email,
        'p_requested_role': requestedRole,
        'p_code': inviteCode,
      },
    );
    return ok == true;
  }

  /// Checks an invite code before submission so the form can reveal the role
  /// it grants — the applicant never picks a role freely, they see the one
  /// their code allows.
  ///
  /// Returns the permitted role, or null for any unusable code. Every failure
  /// looks identical (Slice 2), so this cannot be used to probe which codes
  /// exist. Read-only: checking does not consume the code.
  Future<String?> roleForCode(String code) async {
    final rows = await _client.rpc<dynamic>(
      'validate_signup_invite',
      params: {'p_code': code},
    );
    if (rows is! List || rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first as Map);
    return row['valid'] == true ? row['role_allowed'] as String? : null;
  }
}
