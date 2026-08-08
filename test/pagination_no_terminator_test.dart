// Paginating a pulled table must fetch the whole table without ending on a
// wasted empty request.
//
// The old walk could only recognise the end of a table by asking for one
// more page and getting nothing back, so EVERY table cost one entirely empty
// round-trip. With 17 tables per sync that was 17 requests returning zero
// rows — measured at ~4.8s of a ~9.6s pull on device.
//
// Asking PostgREST for count=exact on the first request removes that: the
// total is known up front, so the exact number of remaining pages is known
// too. The arithmetic has three edge cases that are easy to get subtly wrong
// and, welded to a Supabase client, impossible to observe:
//
//   * a total that divides EXACTLY by the page size — the case where a naive
//     implementation still fetches one page too many, i.e. reintroduces the
//     very request this removed;
//   * a server returning fewer rows than asked for (PostgREST caps at a
//     configured max-rows) — stepping by the REQUESTED size would skip every
//     row in the gap, silently handing back a partial table;
//   * an empty table, which must not divide by zero or loop forever.
//
// "Partial table" is not a cosmetic problem: sites' and blocks' pulls
// reconcile deletes by absence, so a row missing from the fetch is treated as
// deleted remotely and removed locally. Under-fetching here deletes real
// data, which is why these tests assert completeness and not just speed.

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';

/// A fake table of [total] rows that hands out pages, recording every request
/// so the tests can assert how many were made and that none was wasted.
class _FakeTable {
  _FakeTable(this.total, {this.serverCap});

  final int total;

  /// Simulates PostgREST's max-rows: the server never returns more than this
  /// many rows however many were asked for.
  final int? serverCap;

  final List<(int, int)> requests = [];
  int peakInFlight = 0;
  int _inFlight = 0;

  List<Map<String, dynamic>> _rows(int offset, int limit) {
    final cap = serverCap == null ? limit : (limit < serverCap! ? limit : serverCap!);
    final end = (offset + cap) < total ? (offset + cap) : total;
    if (offset >= total) return const [];
    return [for (var i = offset; i < end; i++) {'id': 'row-$i'}];
  }

  /// The first page, as _fetchAllRows obtains it (data + full-table count).
  List<Map<String, dynamic>> firstPage(int pageSize) {
    requests.add((0, pageSize));
    return _rows(0, pageSize);
  }

  Future<List<Map<String, dynamic>>> fetchPage(int offset, int limit) async {
    requests.add((offset, limit));
    _inFlight++;
    peakInFlight = _inFlight > peakInFlight ? _inFlight : peakInFlight;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _inFlight--;
    return _rows(offset, limit);
  }
}

Future<List<Map<String, dynamic>>> _walk(
  _FakeTable table, {
  int pageSize = 500,
  int pageConcurrency = 4,
}) {
  return paginateRemainingPages(
    total: table.total,
    firstPage: table.firstPage(pageSize),
    fetchPage: table.fetchPage,
    pageConcurrency: pageConcurrency,
  );
}

void main() {
  test('a table that fits in one page costs exactly one request', () async {
    final table = _FakeTable(230);

    final rows = await _walk(table);

    expect(rows.length, 230);
    expect(table.requests.length, 1,
        reason: 'the empty terminator request is what this change removed');
  });

  test('an empty table costs one request and returns nothing', () async {
    final table = _FakeTable(0);

    final rows = await _walk(table);

    expect(rows, isEmpty);
    expect(table.requests.length, 1);
  });

  test('a total that divides EXACTLY by the page size fetches no extra page',
      () async {
    // 1000 rows / 500 per page = 2 pages precisely. This is the case a naive
    // "keep going until a short page" implementation gets wrong, because
    // page 2 is full and looks like there might be more.
    final table = _FakeTable(1000);

    final rows = await _walk(table);

    expect(rows.length, 1000);
    expect(table.requests.length, 2,
        reason: 'exactly two full pages — a third would be the wasted request');
    expect(rows.map((r) => r['id']).toSet().length, 1000,
        reason: 'no duplicates across page boundaries');
  });

  test('every row is fetched exactly once across many pages', () async {
    final table = _FakeTable(1234);

    final rows = await _walk(table);

    expect(rows.length, 1234);
    expect(rows.map((r) => r['id']).toSet().length, 1234);
    expect(rows.first['id'], 'row-0');
    expect(rows.map((r) => r['id']), contains('row-1233'));
  });

  test('a server capping pages below the requested size still yields the '
      'complete table', () async {
    // Asked for 500, server returns at most 100. Stepping by 500 would fetch
    // rows 0-99, then 500-599, silently dropping 400 rows — and for sites or
    // blocks, deleting them locally as "absent remotely".
    final table = _FakeTable(450, serverCap: 100);

    final rows = await _walk(table);

    expect(rows.length, 450,
        reason: 'must step by what the server actually returned, not what '
            'was requested');
    expect(rows.map((r) => r['id']).toSet().length, 450);
  });

  test('page concurrency stays within its cap', () async {
    // 20 pages' worth, which must not become 20 simultaneous connections —
    // this multiplies with the caller fetching several tables at once.
    final table = _FakeTable(10000);

    final rows = await _walk(table, pageConcurrency: 4);

    expect(rows.length, 10000);
    expect(table.peakInFlight, lessThanOrEqualTo(4));
  });

  test('a single-page table never calls the page fetcher at all', () async {
    final table = _FakeTable(10);

    await _walk(table);

    // requests holds only the firstPage entry; fetchPage was never invoked.
    expect(table.requests, [(0, 500)]);
    expect(table.peakInFlight, 0);
  });
}
