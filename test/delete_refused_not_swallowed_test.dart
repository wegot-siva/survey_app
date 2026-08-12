// A delete that RLS refused must NOT be mistaken for a successful one.
//
// PostgREST answers an UPDATE or DELETE that row-level security refused with
// HTTP 200 and ZERO affected rows — not an error. Verified against this
// project's Supabase as an engineer tombstoning a source point on a site
// reassigned away:
//
//     HTTP status : 200
//     rows changed: 0
//     remote deleted_at afterwards (read back as admin): None
//
// Unverified, that looked exactly like success, so pushAll hard-deleted the
// local tombstone — destroying the only record that a delete was ever wanted
// — while the remote row stayed live and the next pull reinserted it. The
// user's deletion silently undid itself. This is the third instance of that
// resurrection class in this project.
//
// The subtlety, and why the fix is not a blanket "zero rows => throw":
// zero rows is ambiguous. The same 200/0 comes back when the row never
// reached Supabase at all — an engineer adding a point and removing it again
// before the first sync, which is ordinary and must succeed. Both cases were
// measured and are byte-identical over the wire. Throwing on both would wedge
// that workflow into a permanent, unclearable sync failure over a row nobody
// can even see.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';

void main() {
  group('deleteWasRefused — site-scoped tables (every survey table)', () {
    test('rows affected means it applied, whatever the probe says', () {
      expect(
        deleteWasRefused(rowsAffected: 1, probeFound: true, siteScoped: true),
        isFalse,
      );
      expect(
        deleteWasRefused(rowsAffected: 1, probeFound: false, siteScoped: true),
        isFalse,
      );
    });

    test('zero rows + site still visible == the row was never there', () {
      // We could see the site, so we were entitled to write it. Nothing was
      // updated because there is nothing to update: created and deleted
      // offline before the first sync. Must succeed, or the local tombstone
      // retries forever.
      expect(
        deleteWasRefused(rowsAffected: 0, probeFound: true, siteScoped: true),
        isFalse,
      );
    });

    test('zero rows + site NOT visible == REFUSED (the reported bug)', () {
      expect(
        deleteWasRefused(rowsAffected: 0, probeFound: false, siteScoped: true),
        isTrue,
      );
    });
  });

  group('deleteWasRefused — global catalog (material_master_items)', () {
    test('the sense is INVERTED: SELECT is universal, so the row is the probe',
        () {
      // Still visible => it exists and our delete was refused.
      expect(
        deleteWasRefused(rowsAffected: 0, probeFound: true, siteScoped: false),
        isTrue,
      );
      // Absent => already gone; deleting it again is a no-op, not a failure.
      expect(
        deleteWasRefused(rowsAffected: 0, probeFound: false, siteScoped: false),
        isFalse,
      );
    });

    test('rows affected still means it applied', () {
      expect(
        deleteWasRefused(rowsAffected: 1, probeFound: true, siteScoped: false),
        isFalse,
      );
    });
  });

  test(
    'the two scopes disagree on the same inputs — that inversion is the '
    'whole reason this is a named function',
    () {
      // Identical wire result, opposite verdicts. Collapsing these into one
      // rule breaks one caller or the other, silently.
      const args = (rows: 0, found: true);
      expect(
        deleteWasRefused(
          rowsAffected: args.rows,
          probeFound: args.found,
          siteScoped: true,
        ),
        isFalse,
      );
      expect(
        deleteWasRefused(
          rowsAffected: args.rows,
          probeFound: args.found,
          siteScoped: false,
        ),
        isTrue,
      );
    },
  );

  test('DeleteRefusedException names the row and site, for the sync report',
      () {
    final e = DeleteRefusedException('source_points', 'sp-1', siteId: 'site-9');
    expect(e.toString(), contains('source_points/sp-1'));
    expect(e.toString(), contains('site-9'));
    expect(e.toString(), contains('kept for retry'));
  });
}
