/// Supabase credentials, injected at build time via:
///   flutter run --dart-define-from-file=.env
///
/// Values are read with [String.fromEnvironment] so they are never hardcoded
/// in source and never committed. Empty when not provided.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
