import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Outcome of a connection test, surfaced to the UI.
class ConnectionTestResult {
  const ConnectionTestResult(this.success, this.message);

  final bool success;
  final String message;
}

/// Owns the Supabase client lifecycle.
///
/// Phase 2: CONNECT ONLY. This initializes the client from env-injected
/// credentials and can verify reachability. It deliberately does NOT sync any
/// data — that comes in a later slice.
class SupabaseService {
  bool _initialized = false;
  String? _initError;

  bool get isConfigured => SupabaseConfig.isConfigured;
  bool get isInitialized => _initialized;

  /// Initializes Supabase if credentials are present. Safe no-op otherwise,
  /// so the app still boots and runs fully on the local database.
  Future<void> initIfConfigured() async {
    if (!isConfigured || _initialized) return;
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        // The env var is SUPABASE_ANON_KEY; recent supabase_flutter renamed the
        // "anon" key to "publishable" — same value, non-deprecated parameter.
        publishableKey: SupabaseConfig.anonKey,
      );
      _initialized = true;
    } catch (e) {
      _initError = e.toString();
    }
  }

  /// Confirms the app can reach Supabase. Returns success, or the exact error
  /// so it can be shown verbatim. Does a tiny read against `sites`, which also
  /// validates that the schema has been applied.
  Future<ConnectionTestResult> testConnection() async {
    if (!isConfigured) {
      return const ConnectionTestResult(
        false,
        'Supabase is not configured.\n\n'
        'SUPABASE_URL and SUPABASE_ANON_KEY are empty. Copy .env.example to '
        '.env, fill in your values, and run:\n\n'
        '    flutter run --dart-define-from-file=.env',
      );
    }

    await initIfConfigured();
    if (_initError != null) {
      return ConnectionTestResult(false, 'Supabase init failed:\n\n$_initError');
    }

    try {
      await Supabase.instance.client.from('sites').select('id').limit(1);
      return const ConnectionTestResult(
        true,
        'Connected to Supabase.\n\nThe "sites" table is reachable. '
        '(No data was synced — connection check only.)',
      );
    } on PostgrestException catch (e) {
      return ConnectionTestResult(
        false,
        'Reached Supabase, but the query failed:\n\n'
        'message: ${e.message}\n'
        'code: ${e.code}\n'
        'details: ${e.details}\n'
        'hint: ${e.hint}\n\n'
        'If this says the "sites" table is missing, run supabase/schema.sql '
        'in the Supabase SQL editor.',
      );
    } catch (e) {
      return ConnectionTestResult(false, 'Could not reach Supabase:\n\n$e');
    }
  }
}
