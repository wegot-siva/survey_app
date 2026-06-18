import 'package:flutter/material.dart';

import 'data/in_memory_survey_repository.dart';
import 'data/survey_repository.dart';
import 'services/id_service.dart';
import 'ui/home_screen.dart';

void main() {
  // Phase 0: in-memory repository. Swapped for a real DB later behind the
  // same SurveyRepository interface — UI never depends on the implementation.
  final SurveyRepository repository = InMemorySurveyRepository(IdService());
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
