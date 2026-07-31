// Diagnostic/regression test for the create-site screen: name-only save
// (blocks are added later, during the survey, via Site Hub's "Blocks"
// section — not collected here anymore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/supabase_service.dart';
import 'package:survey_app/services/sync_controller.dart';
import 'package:survey_app/services/sync_service.dart';
import 'package:survey_app/ui/create_site_screen.dart';
import 'package:survey_app/ui/sync_scope.dart';

/// [CreateSiteScreen] fires an auto-sync (SyncScope.read) after saving, so
/// every pump here needs a real ancestor to read — an unconfigured
/// SupabaseService (no test credentials) makes every pull/push a safe no-op,
/// exactly like a real build with no `.env`, rather than needing a separate
/// fake just for this widget test.
///
/// Returns the controller alongside the widget so the test can [dispose] it
/// itself before finishing — `addTearDown` runs too late relative to the
/// test framework's own "no Timer left pending" check, so the debounce timer
/// this triggers needs to be cancelled synchronously within the test body,
/// not queued as a teardown.
(Widget, SyncController) _wrapped(Widget child) {
  final syncService = SyncService(
    InMemorySurveyRepository(IdService()),
    SupabaseService(),
    SupabaseSurveyDataSource(),
  );
  final controller = SyncController(syncService);
  return (
    SyncScope(controller: controller, child: MaterialApp(home: child)),
    controller,
  );
}

void main() {
  testWidgets('Saving a name creates a site with no blocks', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final (widget, syncController) = _wrapped(
      CreateSiteScreen(repository: repository),
    );
    await tester.pumpWidget(widget);

    expect(find.text('Blocks'), findsNothing);
    expect(find.text('Add block'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Test Site');
    await tester.tap(find.text('Save site'));
    await tester.pumpAndSettle();

    final sites = await repository.getSites();
    expect(sites, hasLength(1));
    expect(sites.first.name, 'Test Site');
    expect(sites.first.blocks, isEmpty);

    syncController.dispose();
  });

  testWidgets('Empty name is rejected', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    await tester.pumpWidget(
      MaterialApp(home: CreateSiteScreen(repository: repository)),
    );

    await tester.tap(find.text('Save site'));
    await tester.pump();

    expect(find.text('Please enter a site name.'), findsOneWidget);
    expect(await repository.getSites(), isEmpty);
  });
}
