import 'package:supabase_flutter/supabase_flutter.dart';

/// One signup request as a reviewer sees it.
///
/// Mirrors `public.signup_requests`. Only an active Admin or Approver can
/// read a row — RLS grants SELECT to `is_signup_reviewer()` and to nobody
/// else, and anon has no policy at all — so this model never reaches an
/// unauthenticated caller.
class SignupRequest {
  const SignupRequest({
    required this.id,
    required this.fullName,
    required this.email,
    required this.requestedRole,
    required this.inviteCodeUsed,
    required this.status,
    required this.createdAt,
    required this.reviewedAt,
    required this.rejectionReason,
    required this.createdUserId,
  });

  factory SignupRequest.fromRow(Map<String, dynamic> r) => SignupRequest(
        id: r['id'] as String,
        fullName: r['full_name'] as String,
        email: r['email'] as String,
        requestedRole: r['requested_role'] as String,
        inviteCodeUsed: r['invite_code_used'] as String,
        status: r['status'] as String,
        createdAt: DateTime.parse(r['created_at'] as String),
        reviewedAt: r['reviewed_at'] == null
            ? null
            : DateTime.parse(r['reviewed_at'] as String),
        rejectionReason: r['rejection_reason'] as String?,
        createdUserId: r['created_user_id'] as String?,
      );

  final String id;
  final String fullName;
  final String email;

  /// What the applicant's invite code permitted. **A request, not a grant.**
  /// Nothing about this value gives anyone anything — the approver decides
  /// the role that is actually issued, and it can differ from this.
  final String requestedRole;

  final String inviteCodeUsed;
  final String status;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String? rejectionReason;

  /// The account this request produced, once approved. The audit trail that
  /// answers "which account came from which request" without needing the
  /// person who ran the approval.
  final String? createdUserId;

  bool get isPending => status == 'pending';
}

/// The result of an approve/reject attempt.
///
/// A failure here is not necessarily an error: `already_reviewed` means
/// somebody else got there first and **nothing was written**, which the UI
/// should report calmly rather than as a fault.
class ReviewOutcome {
  const ReviewOutcome({
    required this.ok,
    this.reason,
    this.actionLink,
    this.delivery,
  });

  final bool ok;

  /// Machine-readable cause when [ok] is false. Comes from the Edge Function
  /// or, underneath it, from the RPC that raised.
  final String? reason;

  /// The password-set link, when the function is running in link-delivery
  /// mode. Null when GoTrue was asked to send the email itself.
  final String? actionLink;

  /// How the link reached (or failed to reach) the applicant.
  final String? delivery;

  /// Whether re-running the same approval is expected to fix things.
  ///
  /// True for every failure that rolls the database transaction back: the
  /// account created beforehand is left inert — no role, no access — and the
  /// request stays pending, so approving again resumes exactly where it
  /// stopped.
  bool get isRecoverable =>
      reason == 'invite_unusable' || reason == 'server_error';

  /// Human wording. Deliberately explicit: unlike the signup screen, this one
  /// is seen only by an Admin or Approver, who needs to know what actually
  /// went wrong in order to act on it.
  String get message => switch (reason) {
        'already_reviewed' => 'Somebody else already reviewed this request. '
            'Nothing was changed.',
        'invite_unusable' =>
          "That request's invite code has been revoked, has expired, or has "
              'already been used for another account. Issue a new code, then '
              'approve again.',
        'role_above_reviewer' =>
          'Your account cannot grant that role. An Admin has to approve this '
              'one.',
        'not_a_reviewer' => 'Your account cannot review signup requests.',
        'email_in_use' => 'An account already exists for that email address. '
            'This request needs looking at by hand.',
        'account_not_inert' || 'account_email_mismatch' =>
          'That request does not match the account it would activate. Nothing '
              'was changed. Please report this.',
        'account_create_failed' => "Couldn't create the account. Nothing was "
            'changed — try again.',
        _ => 'Something went wrong. Nothing was changed — try again.',
      };
}

/// Reviewer-side operations on the signup queue.
///
/// Reads go straight to the table (RLS does the gating). **Writes do not**:
/// approve and reject both go through the `review-signup` Edge Function, and
/// the underlying RPCs are granted to `service_role` alone, so there is no
/// client-reachable path to either.
///
/// That indirection is not ceremony. Approving has to create a GoTrue user,
/// which SECURITY DEFINER cannot do — it confers Postgres privileges, not
/// Auth ones — and it has to set `profiles.role`/`active`, which
/// `prevent_self_role_escalation` refuses for anyone who is not an admin. An
/// Approver is not an admin, so the write can only happen under the
/// service_role key, which exists only inside the deployed function. The
/// service_role key is not in this repo and not in the APK.
///
/// Rejection needs none of that privilege, but goes the same way anyway: one
/// authority boundary and one audit path is worth more than saving a round
/// trip on the rarer of the two actions.
class SignupReviewDataSource {
  SupabaseClient get _client => Supabase.instance.client;

  static const _function = 'review-signup';

  /// Requests awaiting review, oldest first — a queue, not a feed, so the
  /// person who has been waiting longest is at the top.
  Future<List<SignupRequest>> fetchPending() => _fetch(status: 'pending');

  /// Everything already dealt with, newest first. This is the audit view.
  Future<List<SignupRequest>> fetchReviewed() async {
    final rows = await _client
        .from('signup_requests')
        .select()
        .neq('status', 'pending')
        .order('reviewed_at', ascending: false);
    return rows
        .map((r) => SignupRequest.fromRow(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  Future<List<SignupRequest>> _fetch({required String status}) async {
    final rows = await _client
        .from('signup_requests')
        .select()
        .eq('status', status)
        .order('created_at', ascending: true);
    return rows
        .map((r) => SignupRequest.fromRow(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  /// The roles this reviewer is allowed to grant.
  ///
  /// Server-derived from the caller's own session — the RPC takes no
  /// argument, so the client cannot ask what somebody else could grant. Used
  /// only to avoid offering a choice the server would refuse; the approval
  /// RPC re-checks the same matrix and is the actual authority.
  Future<List<String>> grantableRoles() async {
    final roles = await _client.rpc<dynamic>('grantable_roles');
    if (roles is! List) return const [];
    return roles.cast<String>().toList(growable: false);
  }

  /// Approves [requestId], granting [grantedRole].
  ///
  /// [grantedRole] is the approver's decision. It defaults on the server to
  /// the requested role purely for convenience — the request itself never
  /// grants anything.
  Future<ReviewOutcome> approve({
    required String requestId,
    required String grantedRole,
  }) =>
      _invoke({
        'action': 'approve',
        'request_id': requestId,
        'granted_role': grantedRole,
      });

  /// Rejects [requestId]. No account is created and the invite code is not
  /// consumed, so the same code can still be used for a genuine applicant.
  Future<ReviewOutcome> reject({
    required String requestId,
    String? reason,
  }) =>
      _invoke({
        'action': 'reject',
        'request_id': requestId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

  Future<ReviewOutcome> _invoke(Map<String, dynamic> body) async {
    try {
      final res = await _client.functions.invoke(_function, body: body);
      return _outcome(res.data);
    } on FunctionException catch (e) {
      // Non-2xx. The body still carries the machine-readable cause, which is
      // more useful than the status code on its own.
      return _outcome(e.details, fallback: 'server_error');
    }
  }

  static ReviewOutcome _outcome(Object? data, {String fallback = 'server_error'}) {
    if (data is! Map) return ReviewOutcome(ok: false, reason: fallback);
    final map = Map<String, dynamic>.from(data);
    if (map['ok'] == true) {
      return ReviewOutcome(
        ok: true,
        actionLink: map['action_link'] as String?,
        delivery: map['delivery'] as String?,
      );
    }
    return ReviewOutcome(
      ok: false,
      reason: (map['error'] ?? map['reason'] ?? fallback) as String?,
    );
  }
}
