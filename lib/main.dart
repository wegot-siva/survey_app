import 'package:flutter/material.dart';

import 'data/sqflite_survey_repository.dart';
import 'data/survey_repository.dart';
import 'services/app_database.dart';
import 'services/id_service.dart';
import 'services/supabase_service.dart';
import 'ui/home_screen.dart';

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

  runApp(SurveyApp(repository: repository, supabaseService: supabaseService));
}

class SurveyApp extends StatelessWidget {
  const SurveyApp({
    super.key,
    required this.repository,
    required this.supabaseService,
  });

  final SurveyRepository repository;
  final SupabaseService supabaseService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Survey App',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: HomeScreen(
        repository: repository,
        supabaseService: supabaseService,
      ),
    );
  }
}
