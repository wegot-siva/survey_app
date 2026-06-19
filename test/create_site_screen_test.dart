// Diagnostic/regression test for block management on the create-site screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/ui/create_site_screen.dart';

void main() {
  testWidgets('Add block lets you add multiple block fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CreateSiteScreen(repository: InMemorySurveyRepository(IdService())),
      ),
    );

    expect(find.text('No blocks added.'), findsOneWidget);

    await tester.tap(find.text('Add block'));
    await tester.pump();
    await tester.tap(find.text('Add block'));
    await tester.pump();
    await tester.tap(find.text('Add block'));
    await tester.pump();

    // Each row's label is "Block N". If only one can be added, this fails.
    expect(find.text('Block 1'), findsOneWidget);
    expect(find.text('Block 2'), findsOneWidget);
    expect(find.text('Block 3'), findsOneWidget);
  });
}
