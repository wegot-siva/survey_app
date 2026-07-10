// Diagnostic/regression test for the create-site screen: name-only save
// (blocks are added later, during the survey, via Site Hub's "Blocks"
// section — not collected here anymore).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/ui/create_site_screen.dart';

void main() {
  testWidgets('Saving a name creates a site with no blocks', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    await tester.pumpWidget(
      MaterialApp(home: CreateSiteScreen(repository: repository)),
    );

    expect(find.text('Blocks'), findsNothing);
    expect(find.text('Add block'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Test Site');
    await tester.tap(find.text('Save site'));
    await tester.pumpAndSettle();

    final sites = await repository.getSites();
    expect(sites, hasLength(1));
    expect(sites.first.name, 'Test Site');
    expect(sites.first.blocks, isEmpty);
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
