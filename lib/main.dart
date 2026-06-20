import 'package:flutter/material.dart';

import 'data/shared_password_auth_repository.dart';
import 'data/sqflite_survey_repository.dart';
import 'data/supabase_survey_data_source.dart';
import 'data/survey_repository.dart';
import 'services/app_database.dart';
import 'services/id_service.dart';
import 'services/session_controller.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';

Future<void> main() async {
  // Needed before any platform-channel call (path_provider / sqflite).
  WidgetsFlutterBinding.ensureInitialized();

  // Local persistence (Phase 1).
  final db = await openAppDatabase();
  final SurveyRepository repository = SqfliteSurveyRepository(db, IdService());

  // Supabase connect-only (Phase 2). Credentials come from
  // --dart-define-from-file=.env; nothing is hardcoded and no data is synced.
  // initIfConfigured is a safe no-op when keys are absent, so the app still
  // runs fully on the local database.
  final supabaseService = SupabaseService();
  await supabaseService.initIfConfigured();

  // Push-only sync (Phase 3). Reads local data via the repository and upserts
  // to Supabase. No-op-safe when Supabase isn't configured.
  final syncService = SyncService(
    repository,
    supabaseService,
    SupabaseSurveyDataSource(),
  );

  // Role-based login (Roles & Assignment — Slice A). Shared-per-role login,
  // behind the AuthRepository seam so real per-user auth can replace it later.
  final session = SessionController(const SharedPasswordAuthRepository());

  runApp(
    SurveyApp(
      repository: repository,
      supabaseService: supabaseService,
      syncService: syncService,
      session: session,
    ),
  );
}

class SurveyApp extends StatelessWidget {
  const SurveyApp({
    super.key,
    required this.repository,
    required this.supabaseService,
    required this.syncService,
    required this.session,
  });

  final SurveyRepository repository;
  final SupabaseService supabaseService;
  final SyncService syncService;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Survey App',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: _AuthGate(
        repository: repository,
        supabaseService: supabaseService,
        syncService: syncService,
        session: session,
      ),
    );
  }
}

/// Shows the login screen until a role is signed in, then the home screen.
/// Listens to [SessionController] so login / logout swap the root screen.
class _AuthGate extends StatelessWidget {
  const _AuthGate({
    required this.repository,
    required this.supabaseService,
    required this.syncService,
    required this.session,
  });

  final SurveyRepository repository;
  final SupabaseService supabaseService;
  final SyncService syncService;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.isLoggedIn) {
          return LoginScreen(session: session);
        }
        return HomeScreen(
          repository: repository,
          supabaseService: supabaseService,
          syncService: syncService,
          session: session,
        );
      },
    );
  }
}
