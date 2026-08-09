// Regression tests for the load-failure state (UI audit P1, item 7).
//
// These screens read local SQLite with no `catch`, so a thrown read used to
// leave `_loading` stuck at true: a spinner forever, with nothing to read
// and nothing to tap. The tests below drive a repository that throws, so
// they fail against that old behaviour rather than merely describing the
// new one.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/models/site.dart';
import 'package:survey_app/models/source_point.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/ui/source_points_list_screen.dart';

/// Fails [getSourcePoints] until [failing] is cleared, so one test can cover
/// both "the error is surfaced" and "retry recovers".
class _FlakyRepository extends InMemorySurveyRepository {
  _FlakyRepository(super.idService);

  bool failing = true;
  int calls = 0;

  @override
  Future<List<SourcePoint>> getSourcePoints(
    String siteId, {
    bool dirtyOnly = false,
  }) async {
    calls++;
    if (failing) throw StateError('database is locked');
    return super.getSourcePoints(siteId, dirtyOnly: dirtyOnly);
  }
}

Widget _screen(_FlakyRepository repo, Site site) => MaterialApp(
  home: SourcePointsListScreen(repository: repo, site: site),
);

void main() {
  late _FlakyRepository repo;
  late Site site;

  setUp(() async {
    repo = _FlakyRepository(IdService());
    site = await repo.createSite(name: 'Test Site');
  });

  testWidgets('a failed first load shows an error and a retry, not a '
      'permanent spinner', (tester) async {
    await tester.pumpWidget(_screen(repo, site));
    await tester.pumpAndSettle();

    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'the spinner must not outlive the failed read',
    );
    expect(find.text("Couldn't open this section."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The underlying cause is quotable by the user reporting it.
    expect(find.textContaining('database is locked'), findsOneWidget);
  });

  testWidgets('Try again recovers once the underlying failure clears', (
    tester,
  ) async {
    await tester.pumpWidget(_screen(repo, site));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);

    repo.failing = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't open this section."), findsNothing);
    // Back to the normal empty state for a site with no points recorded.
    expect(find.textContaining('No source points yet'), findsOneWidget);
  });

  testWidgets('a failed REFRESH keeps the content already on screen', (
    tester,
  ) async {
    repo.failing = false;
    await tester.pumpWidget(_screen(repo, site));
    await tester.pumpAndSettle();
    expect(find.textContaining('No source points yet'), findsOneWidget);

    // Break the repository, then reload exactly the way the app does it:
    // open the add-point form and come back, which calls _load() on return.
    repo.failing = true;
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't open this section."),
      findsNothing,
      reason: 'replacing readable content with an error page loses context '
          'the user can still act on',
    );
    expect(find.textContaining('No source points yet'), findsOneWidget);
    expect(find.textContaining("Couldn't refresh"), findsOneWidget);
  });
}
