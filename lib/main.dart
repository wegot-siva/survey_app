import 'package:flutter/material.dart';

import 'data/sqflite_survey_repository.dart';
import 'data/supabase_auth_repository.dart';
import 'data/supabase_survey_data_source.dart';
import 'data/survey_repository.dart';
import 'services/app_database.dart';
import 'services/id_service.dart';
import 'services/session_controller.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/theme/app_theme.dart';

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

  // Per-user login (Roles & Assignment — Slice 1b). Real Supabase Auth
  // accounts, one per person, each resolving to one of the 4 existing roles
  // via `profiles` — see SupabaseAuthRepository. Session persistence is
  // Supabase's own (not a custom store): restore() checks for an existing
  // session before the first frame, so the login screen only shows when
  // nothing was persisted (or the previous session ended with an explicit
  // logout).
  final session = SessionController(SupabaseAuthRepository(supabaseService));
  await session.restore();

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
      theme: AppTheme.light,
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
