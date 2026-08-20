// Invite-code status and code formatting.
//
// The security of this slice lives in the database — RLS grants SELECT to
// Admins alone, there is no INSERT/UPDATE/DELETE policy for anyone, and
// validation runs in a SECURITY DEFINER function that returns one
// indistinguishable failure for unknown / expired / revoked / exhausted
// codes. None of that is reachable from a unit test: it needs a live
// PostgREST, and this codebase has no seam to inject a fake Supabase client.
// Those properties are verified against the live database instead.
//
// What IS worth pinning here is the client-side derivation that decides what
// an Admin sees. `inactiveReason` re-implements, for display, the same four
// conditions validate_signup_invite() applies. If the two drift, the screen
// will cheerfully show a code as usable that the server refuses — or offer a
// "Revoke" button on a code that already expired. These tests fix each
// condition and its precedence.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/signup_invite_data_source.dart';

SignupInvite invite({
  DateTime? expiresAt,
  int maxUses = 1,
  int uses = 0,
  DateTime? revokedAt,
}) =>
    SignupInvite(
      id: 'i1',
      code: 'ABCDEFGHIJKLMNOPQRST',
      roleAllowed: 'engineer',
      createdAt: DateTime(2026, 1, 1),
      expiresAt: expiresAt,
      maxUses: maxUses,
      uses: uses,
      revokedAt: revokedAt,
    );

void main() {
  group('a code is usable only when every condition holds', () {
    test('fresh, unexpired, unused, unrevoked', () {
      final i = invite(expiresAt: DateTime.now().add(const Duration(days: 7)));
      expect(i.inactiveReason, isNull);
      expect(i.isUsable, isTrue);
    });

    test('no expiry set is not the same as expired', () {
      expect(invite().isUsable, isTrue);
    });
  });

  group('each condition independently makes it unusable', () {
    test('revoked', () {
      expect(invite(revokedAt: DateTime(2026, 2, 1)).inactiveReason, 'Revoked');
    });

    test('expired', () {
      final i = invite(
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      expect(i.inactiveReason, 'Expired');
    });

    test('exhausted — single use is the default', () {
      expect(invite(uses: 1).inactiveReason, 'Used');
    });

    test('exhausted — multi-use', () {
      expect(invite(maxUses: 3, uses: 3).inactiveReason, 'Used');
      expect(invite(maxUses: 3, uses: 2).inactiveReason, isNull);
    });
  });

  test('expiry is exclusive at the boundary, matching the SQL '
      '(expires_at > now)', () {
    // A code expiring exactly now is spent: the RPC uses `expires_at > now()`,
    // so a UI that showed it as usable would be lying.
    expect(invite(expiresAt: DateTime.now()).inactiveReason, 'Expired');
  });

  test('revocation takes precedence over expiry in the label', () {
    final i = invite(
      revokedAt: DateTime(2026, 2, 1),
      expiresAt: DateTime.now().subtract(const Duration(days: 1)),
    );
    // Both are true; "Revoked" is the deliberate act and the more useful
    // thing to show.
    expect(i.inactiveReason, 'Revoked');
  });

  group('fromRow parses what PostgREST actually returns', () {
    test('nullable columns come back as null, not as an error', () {
      final i = SignupInvite.fromRow({
        'id': 'i1',
        'code': 'ABCDE',
        'role_allowed': 'sales',
        'created_at': '2026-01-01T00:00:00Z',
        'expires_at': null,
        'max_uses': 1,
        'uses': 0,
        'revoked_at': null,
      });
      expect(i.expiresAt, isNull);
      expect(i.revokedAt, isNull);
      expect(i.roleAllowed, 'sales');
      expect(i.isUsable, isTrue);
    });

    test('timestamps and counts round-trip', () {
      final i = SignupInvite.fromRow({
        'id': 'i2',
        'code': 'ZZZZZ',
        'role_allowed': 'admin',
        'created_at': '2026-01-01T00:00:00Z',
        'expires_at': '2026-01-08T00:00:00Z',
        'max_uses': 5,
        'uses': 2,
        'revoked_at': '2026-01-05T00:00:00Z',
      });
      expect(i.maxUses, 5);
      expect(i.uses, 2);
      expect(i.expiresAt, DateTime.parse('2026-01-08T00:00:00Z'));
      expect(i.inactiveReason, 'Revoked');
    });
  });
}
