# Only sanctioned way to build a debug APK for this project.
#
# `flutter build apk --debug` on its own compiles SUPABASE_URL/SUPABASE_ANON_KEY
# as empty String.fromEnvironment constants (see lib/services/supabase_config.dart)
# — the app still builds and runs, it just silently can't reach Supabase. This
# wrapper makes the --dart-define-from-file=.env flag impossible to forget.
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

if (-not (Test-Path '.env')) {
    Write-Error "Missing .env file. Copy .env.example to .env and fill in SUPABASE_URL / SUPABASE_ANON_KEY, then re-run this script."
    exit 1
}

flutter build apk --debug --dart-define-from-file=.env
exit $LASTEXITCODE
