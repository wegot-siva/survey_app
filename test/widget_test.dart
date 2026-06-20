// Smoke test: once signed in, the app shows the Sites home screen with an
// empty state and a "New site" button. Uses the in-memory repository.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/data/shared_password_auth_repository.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';
import 'package:survey_app/main.dart';
import 'package:survey_app/models/user_role.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/session_controller.dart';
import 'package:survey_app/services/supabase_service.dart';
import 'package:survey_app/services/sync_service.dart';

void main() {
  testWidgets('shows empty Sites home screen once signed in', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final session = SessionController(const SharedPasswordAuthRepository());
    // Pre-authenticate so the auth gate shows the home screen.
    await session.login(UserRole.engineer, 'engineer123');

    await tester.pumpWidget(
      SurveyApp(
        repository: repository,
        supabaseService: supabaseService,
        syncService: SyncService(
          repository,
          supabaseService,
          SupabaseSurveyDataSource(),
        ),
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sites'), findsOneWidget);
    expect(find.text('New site'), findsOneWidget);
    expect(find.text('No sites yet'), findsOneWidget);
    expect(find.text('Signed in as Engineer'), findsOneWidget);
  });

  testWidgets('boots to the login screen when logged out', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final session = SessionController(const SharedPasswordAuthRepository());

    await tester.pumpWidget(
      SurveyApp(
        repository: repository,
        supabaseService: supabaseService,
        syncService: SyncService(
          repository,
          supabaseService,
          SupabaseSurveyDataSource(),
        ),
        session: session,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Choose your role'), findsOneWidget);
  });
}
