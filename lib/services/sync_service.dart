import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_survey_data_source.dart';
import '../data/survey_repository.dart';
import 'supabase_service.dart';

/// Outcome of a sync run, surfaced to the UI.
class SyncResult {
  const SyncResult({
    required this.success,
    this.sites = 0,
    this.blocks = 0,
    this.clientInputs = 0,
    this.message,
  });

  final bool success;
  final int sites;
  final int blocks;
  final int clientInputs;
  final String? message;
}

/// Push-only sync (Phase 3): reads all local data via [SurveyRepository] and
/// upserts it to Supabase via [SupabaseSurveyDataSource].
///
/// "Push everything" each run — data volume is tiny and upserts are idempotent.
/// The UI never touches storage directly; it only calls [pushAll].
class SyncService {
  SyncService(this._repository, this._supabase, this._remote);

  final SurveyRepository _repository;
  final SupabaseService _supabase;
  final SupabaseSurveyDataSource _remote;

  Future<SyncResult> pushAll() async {
    if (!_supabase.isConfigured) {
      return const SyncResult(
        success: false,
        message: 'Supabase is not configured.\n\nRun with '
            '--dart-define-from-file=.env so credentials are available.',
      );
    }

    await _supabase.initIfConfigured();
    if (!_supabase.isInitialized) {
      return const SyncResult(
        success: false,
        message: 'Supabase failed to initialize. Check your keys in .env.',
      );
    }

    try {
      final sites = await _repository.getSites();
      var blocks = 0;
      var clientInputs = 0;
      for (final site in sites) {
        await _remote.pushSite(site);
        blocks += site.blocks.length;
        if (site.clientInputs != null) clientInputs++;
      }
      return SyncResult(
        success: true,
        sites: sites.length,
        blocks: blocks,
        clientInputs: clientInputs,
      );
    } on PostgrestException catch (e) {
      return SyncResult(
        success: false,
        message: 'Sync failed (database):\n\n'
            'message: ${e.message}\n'
            'code: ${e.code}\n'
            'details: ${e.details}\n'
            'hint: ${e.hint}',
      );
    } catch (e) {
      return SyncResult(success: false, message: 'Sync failed:\n\n$e');
    }
  }
}
