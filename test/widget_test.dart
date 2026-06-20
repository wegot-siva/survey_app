// Smoke test: once signed in, the app shows the Sites home screen. Also
// covers the role-based filtering added in Slices C/D. Uses the in-memory
// repository.

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
    await session.login(UserRole.sales, 'sales123');

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
    expect(find.text('New survey'), findsOneWidget);
    expect(find.text('No sites yet'), findsOneWidget);
    expect(find.text('Signed in as Sales'), findsOneWidget);
  });

  testWidgets('Approver sees only submitted surveys', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final session = SessionController(const SharedPasswordAuthRepository());
    await session.login(UserRole.approver, 'approver123');

    final ready = await repository.createSite(
      name: 'Ready for review',
      blocks: const [],
    );
    await repository.updateSite(
      ready.copyWith(assignedTo: 'Ravi Kumar', status: 'submitted'),
    );
    final notReady = await repository.createSite(
      name: 'Still in progress',
      blocks: const [],
    );
    await repository.updateSite(
      notReady.copyWith(assignedTo: 'Priya Sharma', status: 'in_progress'),
    );

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

    expect(find.text('Ready for review'), findsOneWidget);
    expect(find.text('Still in progress'), findsNothing);
  });

  testWidgets('Engineer sees only their assigned surveys', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final session = SessionController(const SharedPasswordAuthRepository());
    await session.login(
      UserRole.engineer,
      'engineer123',
      engineerName: 'Ravi Kumar',
    );

    final mine = await repository.createSite(name: 'Mine', blocks: const []);
    await repository.updateSite(
      mine.copyWith(assignedTo: 'Ravi Kumar', status: 'assigned'),
    );
    final theirs = await repository.createSite(
      name: 'Not mine',
      blocks: const [],
    );
    await repository.updateSite(
      theirs.copyWith(assignedTo: 'Priya Sharma', status: 'assigned'),
    );

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

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Not mine'), findsNothing);
    expect(find.text('Status: assigned'), findsOneWidget);
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
