import 'package:flutter/material.dart';

import 'data/sqflite_survey_repository.dart';
import 'data/survey_repository.dart';
import 'services/app_database.dart';
import 'services/id_service.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  // Needed before any platform-channel call (path_provider / sqflite).
  WidgetsFlutterBinding.ensureInitialized();

  // Phase 1: local SQLite persistence. The UI only ever sees the
  // SurveyRepository interface, so swapping the implementation changed nothing
  // in the screens. Supabase / sync still to come.
  final db = await openAppDatabase();
  final SurveyRepository repository = SqfliteSurveyRepository(db, IdService());

  runApp(SurveyApp(repository: repository));
}

class SurveyApp extends StatelessWidget {
  const SurveyApp({super.key, required this.repository});

  final SurveyRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Survey App',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: HomeScreen(repository: repository),
    );
  }
}
