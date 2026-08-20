// The signup screen must never leak WHY a submission failed, and must never
// ask for a password.
//
// Everything genuinely security-critical here lives in the database — the RPC
// collapses unknown / expired / revoked / exhausted codes and a
// role-not-permitted into one `false`, and collapses "email already
// registered" and "already has a pending request" into the SAME response as
// success, so that a valid code cannot be used to enumerate email addresses.
// None of that is reachable from a widget test.
//
// What IS worth pinning is the screen's half of the contract: that it asks
// for no password, that it shows the applicant only the role their code
// permits rather than letting them choose, and that its failure text is the
// same regardless of what went wrong.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/signup_request_data_source.dart';
import 'package:survey_app/ui/signup_request_screen.dart';

const _code = 'ABCDEFGHIJKLMNOPQRST'; // 20 chars — the real length

/// Records what the screen sent, and answers however the test needs.
class _FakeRequests extends SignupRequestDataSource {
  _FakeRequests({this.role, this.submitResult = true});

  final String? role;
  final bool submitResult;

  final List<Map<String, String>> submitted = [];
  int roleLookups = 0;

  @override
  Future<String?> roleForCode(String code) async {
    roleLookups++;
    return role;
  }

  @override
  Future<bool> submit({
    required String fullName,
    required String email,
    required String requestedRole,
    required String inviteCode,
  }) async {
    submitted.add({
      'fullName': fullName,
      'email': email,
      'requestedRole': requestedRole,
      'inviteCode': inviteCode,
    });
    return submitResult;
  }
}

Future<void> _pumpScreen(WidgetTester tester, _FakeRequests fake) async {
  await tester.pumpWidget(
    MaterialApp(home: SignupRequestScreen(requests: fake)),
  );
  await tester.pump();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String name = 'Ravi Kumar',
  String email = 'ravi@example.com',
  String code = _code,
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Full name'), name);
  await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
  await tester.enterText(find.widgetWithText(TextField, 'Invite code'), code);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('asks for no password, in any form', (tester) async {
    await _pumpScreen(tester, _FakeRequests(role: 'engineer'));

    expect(find.widgetWithText(TextField, 'Password'), findsNothing);
    expect(find.widgetWithText(TextField, 'Confirm password'), findsNothing);
    // Nothing obscured anywhere — the strongest form of the check, since it
    // would catch a password field under any label.
    final obscured = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.obscureText);
    expect(obscured, isEmpty);
  });

  testWidgets('reveals the role the code permits — the applicant does not '
      'choose it', (tester) async {
    final fake = _FakeRequests(role: 'sales');
    await _pumpScreen(tester, fake);
    await _fillForm(tester);

    expect(find.text('This code is for a sales account.'), findsOneWidget);
    // No role picker exists at all.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('an unusable code shows no reason, and submits nothing',
      (tester) async {
    final fake = _FakeRequests(role: null); // unknown/expired/revoked/exhausted
    await _pumpScreen(tester, fake);
    await _fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(find.text("That invite code can't be used."), findsOneWidget);
    for (final leak in [
      'expired', 'revoked', 'already used', 'not found', 'unknown'
    ]) {
      expect(find.textContaining(leak), findsNothing,
          reason: 'must not hint at WHY the code failed');
    }
    expect(fake.submitted, isEmpty,
        reason: 'nothing should reach the server without a usable code');
  });

  testWidgets('a server rejection reads exactly like an unusable code',
      (tester) async {
    // The RPC returned false — the client cannot know whether that was the
    // code or the role, and must not guess.
    final fake = _FakeRequests(role: 'engineer', submitResult: false);
    await _pumpScreen(tester, fake);
    await _fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(find.text("That invite code can't be used."), findsOneWidget);
  });

  testWidgets('a successful submission sends the code-derived role and '
      'confirms without claiming an account exists', (tester) async {
    final fake = _FakeRequests(role: 'engineer');
    await _pumpScreen(tester, fake);
    await _fillForm(tester, name: '  Ravi Kumar  ', email: ' ravi@example.com ');
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(fake.submitted, hasLength(1));
    expect(fake.submitted.single['requestedRole'], 'engineer',
        reason: 'the role must come from the code, never from user input');
    expect(fake.submitted.single['fullName'], 'Ravi Kumar');
    expect(fake.submitted.single['email'], 'ravi@example.com');

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('waiting for review'), findsOneWidget);
    // Must not imply an account now exists — approval creates it, not this.
    expect(find.textContaining('Account created'), findsNothing);
  });

  testWidgets('the confirmation is worded to cover an already-registered '
      'email, since the server will not say', (tester) async {
    // The RPC returns true and writes nothing for an email that already has
    // an account. The screen sees success, so its wording must remain true.
    final fake = _FakeRequests(role: 'engineer');
    await _pumpScreen(tester, fake);
    await _fillForm(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(find.textContaining('If you already have an account'),
        findsOneWidget);
  });

  testWidgets('a short code is not sent to the server on every keystroke',
      (tester) async {
    final fake = _FakeRequests(role: 'engineer');
    await _pumpScreen(tester, fake);
    await tester.enterText(
        find.widgetWithText(TextField, 'Invite code'), 'ABC');
    await tester.pumpAndSettle();

    expect(fake.roleLookups, 0);
  });

  testWidgets('missing name or email is caught before any request',
      (tester) async {
    final fake = _FakeRequests(role: 'engineer');
    await _pumpScreen(tester, fake);
    await _fillForm(tester, name: '');
    await tester.tap(find.widgetWithText(FilledButton, 'Send request'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name and email.'), findsOneWidget);
    expect(fake.submitted, isEmpty);
  });
}
