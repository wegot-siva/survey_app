// Phase 0 smoke test: the app boots to the Sites home screen with an empty
// state and a "New site" button. Uses the in-memory repository.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/main.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/supabase_service.dart';

void main() {
  testWidgets('boots to empty Sites home screen', (tester) async {
    await tester.pumpWidget(
      SurveyApp(
        repository: InMemorySurveyRepository(IdService()),
        supabaseService: SupabaseService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sites'), findsOneWidget);
    expect(find.text('New site'), findsOneWidget);
    expect(find.text('No sites yet'), findsOneWidget);
  });
}
