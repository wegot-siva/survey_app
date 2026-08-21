// The review queue's half of the Slice 4 contract.
//
// The load-bearing guarantees are all server-side and unreachable from a
// widget test: the approval RPC re-derives the reviewer's role from
// `profiles`, re-checks the authority matrix, consumes the invite code under
// a row lock, and refuses to activate an account that is not already inert.
// None of that can be exercised here, and pretending otherwise would be worse
// than not testing it — it is verified against the live project instead.
//
// What IS worth pinning is the screen's own behaviour, because every one of
// these is a place where a UI mistake would quietly undo a server guarantee
// or mislead the person doing the approving:
//
//   * an Approver is never OFFERED a role they cannot grant,
//   * a request they cannot grant is blocked outright rather than silently
//     downgraded to something the applicant did not ask for,
//   * the role that gets sent is the one the approver chose, and
//   * "somebody else already did this" reads as a non-event, not a fault,
//     because nothing was written.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/signup_review_data_source.dart';
import 'package:survey_app/ui/signup_requests_screen.dart';

SignupRequest _request({
  String id = 'r1',
  String fullName = 'Ravi Kumar',
  String email = 'ravi@example.com',
  String requestedRole = 'engineer',
  String status = 'pending',
}) =>
    SignupRequest(
      id: id,
      fullName: fullName,
      email: email,
      requestedRole: requestedRole,
      inviteCodeUsed: 'ABCDEFGHIJKLMNOPQRST',
      status: status,
      createdAt: DateTime(2026, 8, 1),
      reviewedAt: null,
      rejectionReason: null,
      reviewedBy: null,
      grantedRole: null,
    );

/// Records what the screen sent, and answers however the test needs.
class _FakeReview extends SignupReviewDataSource {
  _FakeReview({
    List<SignupRequest>? pending,
    this.grantable = const ['admin', 'approver', 'engineer', 'sales'],
    this.outcome = const ReviewOutcome(ok: true),
  }) : pending = pending ?? [_request()];

  final List<SignupRequest> pending;
  final List<String> grantable;
  final ReviewOutcome outcome;

  final List<Map<String, String?>> approvals = [];
  final List<Map<String, String?>> rejections = [];

  @override
  Future<List<SignupRequest>> fetchPending() async => pending;

  @override
  Future<List<SignupRequest>> fetchReviewed() async => const [];

  @override
  Future<List<String>> grantableRoles() async => grantable;

  @override
  Future<ReviewOutcome> approve({
    required String requestId,
    required String grantedRole,
  }) async {
    approvals.add({'requestId': requestId, 'grantedRole': grantedRole});
    return outcome;
  }

  @override
  Future<ReviewOutcome> reject({
    required String requestId,
    String? reason,
  }) async {
    rejections.add({'requestId': requestId, 'reason': reason});
    return outcome;
  }
}

Future<void> _pumpScreen(WidgetTester tester, _FakeReview fake) async {
  await tester.pumpWidget(
    MaterialApp(home: SignupRequestsScreen(review: fake)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an Approver is never offered a role they cannot grant',
      (tester) async {
    // What grantable_roles() returns for an approver.
    final fake = _FakeReview(grantable: const ['engineer', 'sales']);
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('admin'), findsNothing);
    expect(find.text('approver'), findsNothing);
    expect(find.text('sales'), findsWidgets);
  });

  testWidgets('a request above the reviewer is blocked, not downgraded',
      (tester) async {
    final fake = _FakeReview(
      pending: [_request(requestedRole: 'admin')],
      grantable: const ['engineer', 'sales'],
    );
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    expect(find.textContaining('An Admin has to approve it'), findsOneWidget);
    // The dialog's own Approve button is disabled — approving here must not
    // be possible at all, rather than quietly granting 'engineer' to someone
    // who asked to be an admin.
    final approve = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Approve').last,
    );
    expect(approve.onPressed, isNull);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('the granted role is the one chosen, not the one requested',
      (tester) async {
    final fake = _FakeReview(pending: [_request(requestedRole: 'engineer')]);
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sales').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(fake.approvals.single['grantedRole'], 'sales');
    expect(fake.approvals.single['requestId'], 'r1');
  });

  testWidgets('the default is the requested role', (tester) async {
    final fake = _FakeReview(pending: [_request(requestedRole: 'sales')]);
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(fake.approvals.single['grantedRole'], 'sales');
  });

  testWidgets('the password link is shown once, and can be copied',
      (tester) async {
    final fake = _FakeReview(
      outcome: const ReviewOutcome(
        ok: true,
        actionLink: 'https://example.supabase.co/auth/v1/verify?token=abc',
        delivery: 'link_generated',
      ),
    );
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('token=abc'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Copy link'), findsOneWidget);
    // The single-recovery-token caveat must reach the person holding the
    // link, or they will regenerate it and silently break the one they sent.
    expect(find.textContaining('generating another one cancels this'),
        findsOneWidget);
  });

  testWidgets('"already reviewed" reads as a non-event, not a fault',
      (tester) async {
    final fake = _FakeReview(
      outcome: const ReviewOutcome(ok: false, reason: 'already_reviewed'),
    );
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(find.text('Already reviewed'), findsOneWidget);
    expect(find.textContaining('Nothing was changed'), findsOneWidget);
  });

  testWidgets('a consumed invite code tells the reviewer what to do next',
      (tester) async {
    final fake = _FakeReview(
      outcome: const ReviewOutcome(ok: false, reason: 'invite_unusable'),
    );
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('Issue a new code, then approve again'),
        findsOneWidget);
  });

  testWidgets('rejecting with no reason still rejects', (tester) async {
    final fake = _FakeReview();
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(fake.rejections.single['requestId'], 'r1');
    // Empty reason must arrive as null, not '' — the column is nullable and
    // an empty string would read as "a reason was given" in the audit view.
    expect(fake.rejections.single['reason'], isNull);
  });

  testWidgets('cancelling the reject dialog sends nothing', (tester) async {
    final fake = _FakeReview();
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fake.rejections, isEmpty);
  });

  testWidgets('the reject dialog says the invite code survives',
      (tester) async {
    // Reviewers need to know this: a rejection does NOT burn the code, so
    // the same one can go to a genuine applicant.
    final fake = _FakeReview();
    await _pumpScreen(tester, fake);

    await tester.tap(find.widgetWithText(TextButton, 'Reject'));
    await tester.pumpAndSettle();

    expect(find.textContaining('invite code is not used up'), findsOneWidget);
  });

  testWidgets('an empty queue says so rather than showing a blank screen',
      (tester) async {
    await _pumpScreen(tester, _FakeReview(pending: []));
    expect(find.text('Nothing waiting for review.'), findsOneWidget);
    expect(find.text('Pending (0)'), findsOneWidget);
  });
}
