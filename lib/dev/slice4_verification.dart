// TEMPORARY, debug-only. Verifies Slice 4 (the review-signup Edge Function
// and its RPCs) against the live, DEPLOYED function — no mock, no manual
// token handling. Delete this file and its two menu entries in
// home_screen.dart once verification is done; it is not meant to ship.
//
// HOW AUTHENTICATION WORKS HERE, and why nothing below ever touches a JWT:
// every call through Supabase.instance.client (.functions.invoke, .from,
// .rpc) is routed through the SDK's own AuthHttpClient, which reads
// auth.currentSession fresh on EVERY request and attaches it as
// `Authorization: Bearer <token>`, refreshing it if it's expiring. That
// happens inside the supabase-dart package, never in this file. So running a
// check here always acts as whichever account is currently logged into the
// app — there is nothing to extract, print, or pass around.
//
// TWO PASSES, not one, because RLS itself limits what each role can even
// observe: signup_invites has no SELECT policy for Approver at all (by
// design — see schema.sql's Slice 2 comment), so "was the invite consumed
// exactly once" can only be checked from an Admin session.
//
//   1. Log in as Admin, call Slice4VerificationRunner().runAdminPass().
//      This seeds ALL the fixtures both passes need (Admin is the only role
//      that can create invite codes) and runs every Admin-observable check.
//   2. Log out, log in as Approver, call runApproverPass(). It finds the
//      fixtures the Admin pass left behind (marked by a full_name prefix)
//      and runs the Approver-observable checks against them.
//
// Each run stamps its fixtures with a fresh timestamp, so re-running the
// Admin pass never collides with a previous run's rows or codes.
//
// Output is PASS/FAIL lines with HTTP status + response body only — never a
// token, never a password.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/signup_invite_data_source.dart';
import '../data/signup_request_data_source.dart';
import '../data/signup_review_data_source.dart';

/// Marks every row this harness creates, so a pass can find its own fixtures
/// (and so a human eyeballing signup_requests can tell test data apart from
/// a real applicant).
const _kMarkerPrefix = 'Slice4Seed';

/// One recorded check. Kept in memory so the on-screen report does not depend
/// on logcat — this device (ColorOS) suppresses app-level logcat output, so
/// debugPrint alone produced nothing retrievable.
class _Result {
  const _Result(this.ok, this.label, this.detail);
  final bool ok;
  final String label;
  final Object? detail;

  @override
  String toString() =>
      '${ok ? 'PASS' : 'FAIL'} — $label${detail == null ? '' : ' ($detail)'}';
}

class Slice4VerificationRunner {
  Slice4VerificationRunner()
      : _invites = SignupInviteDataSource(),
        _requests = SignupRequestDataSource(),
        _review = SignupReviewDataSource(),
        _db = Supabase.instance.client;

  final SignupInviteDataSource _invites;
  final SignupRequestDataSource _requests;
  final SignupReviewDataSource _review;
  final SupabaseClient _db;

  int _pass = 0;
  int _fail = 0;

  /// Every check, in order. This — not logcat — is the authoritative record.
  final List<_Result> _results = [];

  void _ok(String label, [Object? detail]) {
    _pass++;
    _results.add(_Result(true, label, detail));
    debugPrint('[Slice4] PASS — $label${detail == null ? '' : ' ($detail)'}');
  }

  void _bad(String label, Object? detail) {
    _fail++;
    _results.add(_Result(false, label, detail));
    debugPrint('[Slice4] FAIL — $label ($detail)');
  }

  void _check(String label, bool condition, {Object? detail}) {
    if (condition) {
      _ok(label, detail);
    } else {
      _bad(label, detail);
    }
  }

  void _summary(String passName) {
    debugPrint('[Slice4] ===== $passName complete: $_pass passed, $_fail failed =====');
  }

  // ---------------------------------------------------------------------
  // On-screen reporting
  //
  // The runner presents its own dialog rather than returning a string for
  // home_screen.dart to show, because that file is production code and is
  // deliberately not modified for this harness. Finding the Navigator from
  // the widget tree root is the only way to reach a BuildContext from here
  // without one being passed in.
  // ---------------------------------------------------------------------

  NavigatorState? _findNavigator() {
    NavigatorState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        found = element.state as NavigatorState;
        return;
      }
      element.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }

  /// Failures first — that is what a reader needs — then the full pass list.
  String _reportText(String passName) {
    final failures = _results.where((r) => !r.ok).toList();
    final passes = _results.where((r) => r.ok).toList();
    final b = StringBuffer()
      ..writeln('SLICE4 ${passName.toUpperCase()}')
      ..writeln('')
      ..writeln('Total passed: $_pass')
      ..writeln('Total failed: $_fail')
      ..writeln('');

    if (failures.isEmpty) {
      b.writeln('--- NO FAILURES ---');
    } else {
      b.writeln('--- FAILED (${failures.length}) ---');
      for (final f in failures) {
        b.writeln(f.toString());
      }
    }
    b
      ..writeln('')
      ..writeln('--- PASSED (${passes.length}) ---');
    for (final p in passes) {
      b.writeln(p.toString());
    }
    return b.toString();
  }

  Future<void> _showReport(String passName) async {
    final text = _reportText(passName);
    final context = _findNavigator()?.overlay?.context;
    if (context == null) {
      debugPrint('[Slice4] could not find a Navigator — report follows:\n$text');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Slice4 $passName — $_pass passed, $_fail failed'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Resets counters, runs [body], captures a mid-pass throw as a recorded
  /// failure rather than losing every result gathered so far, then reports.
  Future<void> _runPass(String passName, Future<void> Function() body) async {
    _pass = 0;
    _fail = 0;
    _results.clear();
    try {
      await body();
    } catch (e, st) {
      _fail++;
      _results.add(_Result(false, 'HARNESS ABORTED (no further checks ran)', e));
      debugPrint('[Slice4] ABORTED — $e\n$st');
    }
    _summary(passName);
    await _showReport(passName);
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  /// The CURRENTLY logged-in account's actual role, read straight from
  /// `profiles` — the same table and column SupabaseAuthRepository's
  /// _resolveProfile reads after every sign-in. Never assumed from which
  /// harness button was pressed or which account the caller THINKS is
  /// logged in: a run always checks the live account, every time.
  Future<String> _ownRole() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No signed-in user — log in before running this pass.');
    }
    final row = await _db.from('profiles').select('full_name, role').eq('id', userId).single();
    debugPrint("[Slice4] detected account: '${row['full_name']}', role='${row['role']}'");
    return row['role'] as String;
  }

  /// Whatever the CURRENT account's role may grant, per the live
  /// may_approve_role(p_reviewer_role, p_target_role) RPC — grantable_roles()
  /// was never deployed (confirmed: PGRST202 against the live project), so
  /// this calls the real authority function directly instead, once per
  /// candidate role, rather than depending on a wrapper that doesn't exist.
  Future<bool> _mayApprove(String ownRole, String targetRole) async {
    final result = await _db.rpc<dynamic>('may_approve_role', params: {
      'p_reviewer_role': ownRole,
      'p_target_role': targetRole,
    });
    return result == true;
  }

  /// NOTE: does NOT select created_user_id. schema.sql (line ~2699) adds that
  /// column, but it was never applied to the live database (confirmed:
  /// `column signup_requests.created_user_id does not exist`), so selecting
  /// it here would fail before any check ran. Every "was an account
  /// created" question this harness needs is answered instead by `status`
  /// (approved/rejected/still-pending) — see the call sites.
  Future<Map<String, dynamic>> _requestRow(String id) async {
    final row = await _db
        .from('signup_requests')
        .select('id, status, requested_role, invite_code_used, rejection_reason')
        .eq('id', id)
        .single();
    return Map<String, dynamic>.from(row);
  }

  /// Admin-only: signup_invites has no SELECT policy for Approver.
  Future<int> _invitesUses(String code) async {
    final row = await _db
        .from('signup_invites')
        .select('uses')
        .eq('code', code)
        .single();
    return (row['uses'] as num).toInt();
  }

  /// Submits a request and returns its row id, by re-reading the pending
  /// queue for the marker+email — request_signup() returns a bare bool, not
  /// the new row's id.
  Future<String> _submit({
    required String namePart,
    required String email,
    required String role,
    required String code,
  }) async {
    final ok = await _requests.submit(
      fullName: '$_kMarkerPrefix-$namePart',
      email: email,
      requestedRole: role,
      inviteCode: code,
    );
    if (!ok) {
      throw StateError('request_signup returned false for $namePart ($email, $role, $code)');
    }
    final rows = await _db
        .from('signup_requests')
        .select('id')
        .eq('email', email.toLowerCase().trim())
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) {
      throw StateError('submitted $namePart but no pending row was found for $email');
    }
    return rows.first['id'] as String;
  }

  // ---------------------------------------------------------------------
  // PASS 1 — run while logged in as Admin.
  // ---------------------------------------------------------------------
  Future<void> runAdminPass() => _runPass('Admin pass', _adminPassBody);

  Future<void> _adminPassBody() async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[Slice4] ===== Admin pass starting (stamp=$stamp) =====');

    // ---- sanity: existing login/session unaffected -----------------------
    final session = _db.auth.currentSession;
    _check('a live session exists', session != null && !session.isExpired);

    // ---- verify the ACTUAL logged-in role, never assumed ------------------
    final ownRole = await _ownRole();
    if (ownRole != 'admin') {
      throw StateError(
        "runAdminPass() requires an Admin account, but the account currently "
        "logged in has role='$ownRole'. Log in as Admin and try again.",
      );
    }
    _check("detected account's role is admin", true, detail: ownRole);

    for (final target in ['admin', 'approver', 'engineer', 'sales']) {
      final may = await _mayApprove('admin', target);
      _check('may_approve_role(admin, $target) is true', may);
    }

    // ---- seed everything both passes need ---------------------------------
    Future<String> mint(String role) =>
        _invites.createInvite(roleAllowed: role, expiresAt: DateTime.now().add(const Duration(days: 1)));

    final codeEngineer = await mint('engineer'); // Admin approves this one
    final codeSalesGrantedAdmin = await mint('sales'); // Admin approves with a DIFFERENT granted role
    final codeDouble = await mint('engineer'); // double-approval test
    final codeRevoked = await mint('engineer'); // will be revoked before approval
    final codeReject = await mint('engineer'); // Admin rejects this one

    // Fixtures for the Approver pass — Approver cannot mint codes itself.
    final codeForApproverEngineer = await mint('engineer');
    final codeForApproverSales = await mint('sales');
    final codeForApproverAdmin = await mint('admin');
    final codeForApproverApprover = await mint('approver');
    final codeForApproverReject = await mint('engineer');

    final reqEngineer = await _submit(
      namePart: 'AdminEngineer',
      email: 's4a-engineer-$stamp@example.com',
      role: 'engineer',
      code: codeEngineer,
    );
    final reqSales = await _submit(
      // Stamped (unlike the other fixtures' namePart) because this one's
      // resulting profile is looked up BY full_name below, in place of the
      // created_user_id FK the live database doesn't have.
      namePart: 'AdminSalesGrantedAdmin-$stamp',
      email: 's4a-sales-$stamp@example.com',
      role: 'sales',
      code: codeSalesGrantedAdmin,
    );
    final reqDouble = await _submit(
      namePart: 'AdminDouble',
      email: 's4a-double-$stamp@example.com',
      role: 'engineer',
      code: codeDouble,
    );
    final reqRevoked = await _submit(
      namePart: 'AdminRevoked',
      email: 's4a-revoked-$stamp@example.com',
      role: 'engineer',
      code: codeRevoked,
    );
    final reqReject = await _submit(
      namePart: 'AdminReject',
      email: 's4a-reject-$stamp@example.com',
      role: 'engineer',
      code: codeReject,
    );

    await _submit(
      namePart: 'ForApproverEngineer',
      email: 's4a-fa-engineer-$stamp@example.com',
      role: 'engineer',
      code: codeForApproverEngineer,
    );
    await _submit(
      namePart: 'ForApproverSales',
      email: 's4a-fa-sales-$stamp@example.com',
      role: 'sales',
      code: codeForApproverSales,
    );
    await _submit(
      namePart: 'ForApproverAdmin',
      email: 's4a-fa-admin-$stamp@example.com',
      role: 'admin',
      code: codeForApproverAdmin,
    );
    await _submit(
      namePart: 'ForApproverApprover',
      email: 's4a-fa-approver-$stamp@example.com',
      role: 'approver',
      code: codeForApproverApprover,
    );
    await _submit(
      namePart: 'ForApproverReject',
      email: 's4a-fa-reject-$stamp@example.com',
      role: 'engineer',
      code: codeForApproverReject,
    );

    debugPrint('[Slice4] seeded fixtures for stamp=$stamp');

    // ---- Admin approves per the authority matrix ---------------------------
    final approveEngineer = await _review.approve(requestId: reqEngineer, grantedRole: 'engineer');
    _check('admin approves an engineer request', approveEngineer.ok, detail: approveEngineer.reason);

    var row = await _requestRow(reqEngineer);
    _check('pending -> approved transition (engineer)', row['status'] == 'approved');

    // Granted role different from requested role — proves the grant comes
    // from the approver's decision, not from requested_role.
    //
    // Can't look this up via created_user_id (column doesn't exist live).
    // Instead: the Edge Function passes request.full_name as the new
    // account's user_metadata.full_name, and handle_new_user copies THAT
    // into profiles.full_name — so a marker full_name that's unique to this
    // run finds the same profile the created_user_id FK would have. The
    // fixture name below carries the run's stamp specifically so this
    // lookup stays unique across repeated runs.
    final salesGrantedAdminMarker = '$_kMarkerPrefix-AdminSalesGrantedAdmin-$stamp';
    final approveSalesAsAdmin =
        await _review.approve(requestId: reqSales, grantedRole: 'admin');
    _check(
      'admin approves a sales request but GRANTS admin',
      approveSalesAsAdmin.ok,
      detail: approveSalesAsAdmin.reason,
    );
    row = await _requestRow(reqSales);
    _check('pending -> approved transition (granted-role-diff)', row['status'] == 'approved');
    if (approveSalesAsAdmin.ok) {
      final matches = await _db
          .from('profiles')
          .select('role')
          .eq('full_name', salesGrantedAdminMarker);
      _check(
        'exactly one profile was created for the granted-role-diff account',
        matches.length == 1,
        detail: 'found ${matches.length} profile(s) named $salesGrantedAdminMarker',
      );
      if (matches.length == 1) {
        _check(
          'profiles.role reflects the GRANTED role, not requested_role',
          matches.first['role'] == 'admin',
          detail: 'profiles.role=${matches.first['role']}, requested_role=${row['requested_role']}',
        );
      }
    }

    // ---- revoked invite: fails, creates nothing, consumes nothing ---------
    final revokedOk = await _invites.revokeInvite(
      (await _db.from('signup_invites').select('id').eq('code', codeRevoked).single())['id'] as String,
    );
    _check('revoke succeeded (setup)', revokedOk);

    final usesBeforeRevokedAttempt = await _invitesUses(codeRevoked);
    final approveRevoked = await _review.approve(requestId: reqRevoked, grantedRole: 'engineer');
    _check(
      'approving a request whose code is now revoked fails',
      !approveRevoked.ok && approveRevoked.reason == 'invite_unusable',
      detail: approveRevoked.reason,
    );
    row = await _requestRow(reqRevoked);
    _check('revoked-code approval left the request pending', row['status'] == 'pending');
    final usesAfterRevokedAttempt = await _invitesUses(codeRevoked);
    _check(
      'revoked-code approval consumed nothing',
      usesAfterRevokedAttempt == usesBeforeRevokedAttempt,
      detail: 'uses before=$usesBeforeRevokedAttempt after=$usesAfterRevokedAttempt',
    );

    // ---- consumes the invite exactly once, and double-approval is a no-op --
    final usesBefore = await _invitesUses(codeDouble);
    _check('fresh code starts at uses=0', usesBefore == 0, detail: usesBefore);

    final firstApproval = await _review.approve(requestId: reqDouble, grantedRole: 'engineer');
    _check('first approval of the double-test request succeeds', firstApproval.ok, detail: firstApproval.reason);
    final usesAfterFirst = await _invitesUses(codeDouble);
    _check('invite uses goes 0 -> 1 on approval', usesAfterFirst == 1, detail: usesAfterFirst);

    final secondApproval = await _review.approve(requestId: reqDouble, grantedRole: 'engineer');
    _check(
      'approving the SAME request again is a no-op (already_reviewed)',
      !secondApproval.ok && secondApproval.reason == 'already_reviewed',
      detail: secondApproval.reason,
    );
    final usesAfterSecond = await _invitesUses(codeDouble);
    _check(
      'double-approval attempt did not consume the invite again',
      usesAfterSecond == 1,
      detail: usesAfterSecond,
    );

    // ---- rejection works ----------------------------------------------------
    final usesBeforeReject = await _invitesUses(codeReject);
    final rejectOutcome = await _review.reject(requestId: reqReject, reason: 'slice4 harness test');
    _check('admin rejects a request', rejectOutcome.ok, detail: rejectOutcome.reason);
    row = await _requestRow(reqReject);
    _check('pending -> rejected transition', row['status'] == 'rejected');
    _check('rejection_reason recorded', row['rejection_reason'] == 'slice4 harness test');
    final usesAfterReject = await _invitesUses(codeReject);
    _check(
      'rejection did not consume the invite',
      usesAfterReject == usesBeforeReject,
      detail: 'before=$usesBeforeReject after=$usesAfterReject',
    );

    debugPrint(
      '[Slice4] Approver-pass fixtures ready under stamp=$stamp — log in as '
      'Approver and call runApproverPass().',
    );
  }

  // ---------------------------------------------------------------------
  // PASS 2 — run while logged in as Approver, AFTER runAdminPass().
  // ---------------------------------------------------------------------
  Future<void> runApproverPass() => _runPass('Approver pass', _approverPassBody);

  Future<void> _approverPassBody() async {
    debugPrint('[Slice4] ===== Approver pass starting =====');

    final session = _db.auth.currentSession;
    _check('a live session exists', session != null && !session.isExpired);

    // ---- verify the ACTUAL logged-in role, never assumed ------------------
    final ownRole = await _ownRole();
    if (ownRole != 'approver') {
      throw StateError(
        "runApproverPass() requires an Approver account, but the account "
        "currently logged in has role='$ownRole'. Log in as Approver and "
        "try again.",
      );
    }
    _check("detected account's role is approver", true, detail: ownRole);

    // All four, not just engineer/sales: the authority matrix was widened
    // deliberately so an Approver grants exactly what an Admin grants. The
    // two 'is false' assertions that used to sit here (approver -> admin,
    // approver -> approver) encoded the OLD rule and would now fail against
    // correct behaviour.
    for (final target in ['admin', 'approver', 'engineer', 'sales']) {
      final may = await _mayApprove('approver', target);
      _check('may_approve_role(approver, $target) is true', may);
    }

    Future<Map<String, dynamic>> findFixture(String namePart) async {
      final rows = await _db
          .from('signup_requests')
          .select('id, requested_role')
          .ilike('full_name', '$_kMarkerPrefix-$namePart')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) {
        throw StateError(
          "No pending '$namePart' fixture found. Run runAdminPass() first "
          '(as Admin), then switch to Approver and run this again.',
        );
      }
      return Map<String, dynamic>.from(rows.first);
    }

    final fEngineer = await findFixture('ForApproverEngineer');
    final fSales = await findFixture('ForApproverSales');
    final fAdmin = await findFixture('ForApproverAdmin');
    final fApprover = await findFixture('ForApproverApprover');
    final fReject = await findFixture('ForApproverReject');

    // ---- Approver CAN review Engineer/Sales --------------------------------
    final approveEngineer =
        await _review.approve(requestId: fEngineer['id'] as String, grantedRole: 'engineer');
    _check('approver approves an engineer request', approveEngineer.ok, detail: approveEngineer.reason);
    var row = await _requestRow(fEngineer['id'] as String);
    _check('pending -> approved (engineer, by approver)', row['status'] == 'approved');

    final approveSales =
        await _review.approve(requestId: fSales['id'] as String, grantedRole: 'sales');
    _check('approver approves a sales request', approveSales.ok, detail: approveSales.reason);
    row = await _requestRow(fSales['id'] as String);
    _check('pending -> approved (sales, by approver)', row['status'] == 'approved');

    // ---- Approver CAN now approve Admin/Approver requests too ---------------
    // These four assertions previously expected refusal with
    // 'role_above_reviewer'. The authority matrix was widened deliberately,
    // so refusal is no longer correct behaviour and asserting it would fail
    // against a working system. An Approver now has the same granting
    // authority as an Admin.
    final approveAdminReq =
        await _review.approve(requestId: fAdmin['id'] as String, grantedRole: 'admin');
    _check(
      'approver CAN approve an admin request',
      approveAdminReq.ok,
      detail: approveAdminReq.reason,
    );
    row = await _requestRow(fAdmin['id'] as String);
    _check('pending -> approved (admin request, by approver)', row['status'] == 'approved');

    final approveApproverReq =
        await _review.approve(requestId: fApprover['id'] as String, grantedRole: 'approver');
    _check(
      'approver CAN approve an approver request',
      approveApproverReq.ok,
      detail: approveApproverReq.reason,
    );
    row = await _requestRow(fApprover['id'] as String);
    _check('pending -> approved (approver request, by approver)', row['status'] == 'approved');

    // ---- rejection works as Approver too ------------------------------------
    final rejectOutcome =
        await _review.reject(requestId: fReject['id'] as String, reason: 'approver harness test');
    _check('approver rejects a request', rejectOutcome.ok, detail: rejectOutcome.reason);
    row = await _requestRow(fReject['id'] as String);
    _check('pending -> rejected (by approver)', row['status'] == 'rejected');
    _check('rejection_reason recorded (by approver)', row['rejection_reason'] == 'approver harness test');

    debugPrint(
      '[Slice4] Note: signup_invites has no SELECT policy for Approver, so '
      "consumption counts for THIS pass's codes can only be spot-checked "
      'from an Admin session — the generic consume-once mechanism was '
      'already proven in the Admin pass.',
    );
  }
}
