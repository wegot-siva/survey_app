import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'data/sqflite_survey_repository.dart';
import 'data/supabase_auth_repository.dart';
import 'data/supabase_survey_data_source.dart';
import 'data/survey_repository.dart';
import 'services/app_database.dart';
import 'services/id_service.dart';
import 'services/session_controller.dart';
import 'services/supabase_service.dart';
import 'services/sync_controller.dart';
import 'services/sync_service.dart';
import 'ui/home_screen.dart';
import 'ui/login_screen.dart';
import 'ui/sync_scope.dart';
import 'ui/theme/app_theme.dart';

/// Builds the [SurveyRepository] for a signed-in user id. Production wires
/// this to a real, account-scoped SQLite file (see [openAppDatabaseForUser]);
/// tests wire it to a fixed in-memory instance regardless of which id is
/// passed, preserving the exact single-shared-repository behavior tests
/// relied on before account-scoped databases existed.
typedef RepositoryProvider = Future<SurveyRepository> Function(String userId);

Future<void> main() async {
  // Needed before any platform-channel call (path_provider / sqflite).
  WidgetsFlutterBinding.ensureInitialized();

  // Supabase connect-only (Phase 2). Credentials come from
  // --dart-define-from-file=.env; nothing is hardcoded and no data is synced.
  // initIfConfigured is a safe no-op when keys are absent, so the app still
  // runs fully on the local database.
  final supabaseService = SupabaseService();
  await supabaseService.initIfConfigured();

  // Per-user login (Roles & Assignment — Slice 1b). Real Supabase Auth
  // accounts, one per person, each resolving to one of the 4 existing roles
  // via `profiles` — see SupabaseAuthRepository. Session persistence is
  // Supabase's own (not a custom store): restore() checks for an existing
  // session before the first frame, so the login screen only shows when
  // nothing was persisted (or the previous session ended with an explicit
  // logout).
  final session = SessionController(SupabaseAuthRepository(supabaseService));
  await session.restore();

  // Local persistence is deliberately NOT opened here — it's account-scoped
  // (see openAppDatabaseForUser's doc) and opened lazily by _AuthGate once a
  // signed-in user id is known. Nothing before login needs it: LoginScreen
  // never touches the repository.
  runApp(
    SurveyApp(
      supabaseService: supabaseService,
      session: session,
      repositoryFor: (userId) async {
        final db = await openAppDatabaseForUser(userId);
        return SqfliteSurveyRepository(db, IdService());
      },
    ),
  );
}

/// Shows the login screen until a role is signed in, then the home screen —
/// and owns the account-scoped repository's lifecycle in between. Listens
/// to [SessionController] so login / logout swap the root screen; on top of
/// that, whenever the *signed-in user id* changes, opens a fresh repository
/// scoped to that id (via [repositoryFor]) before ever showing [HomeScreen],
/// so one account's screens can never read or write another account's local
/// data — see [openAppDatabaseForUser]'s doc for the full rationale.
///
/// Stateful (rather than a thin [MaterialApp] wrapper over a separate gate
/// widget) specifically so [SyncScope] can sit *above* [MaterialApp], and
/// therefore above its [Navigator] — see [build].
class SurveyApp extends StatefulWidget {
  const SurveyApp({
    super.key,
    required this.supabaseService,
    required this.session,
    required this.repositoryFor,
  });

  final SupabaseService supabaseService;
  final SessionController session;
  final RepositoryProvider repositoryFor;

  @override
  State<SurveyApp> createState() => _SurveyAppState();
}

class _SurveyAppState extends State<SurveyApp> with WidgetsBindingObserver {
  // The user id the currently-loaded repository/syncService belong to, or
  // null when nothing is loaded (logged out, or a load is still in flight).
  String? _loadedForUserId;
  SurveyRepository? _repository;
  SyncService? _syncService;
  SyncController? _syncController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.session.addListener(_onSessionChanged);
    // Handles a session already restored (main() awaits session.restore()
    // before runApp) before this widget's first build.
    _onSessionChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.session.removeListener(_onSessionChanged);
    _syncController?.dispose();
    super.dispose();
  }

  /// Lifecycle sync triggers. Observed here rather than on a screen because
  /// this is app-level: an engineer backgrounding the app mid-form should
  /// still get their saved work pushed, and HomeScreen isn't even built when
  /// they're deep in a section form.
  ///
  /// Both routes go through the same [SyncController] as the Sync button and
  /// the after-save trigger, so they inherit single-flight and (for resume)
  /// the debounce/cooldown gates — no parallel concurrency handling.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final controller = _syncController;
    if (controller == null) return; // logged out — nothing to sync

    switch (state) {
      case AppLifecycleState.resumed:
        // Full sync: coming back is exactly when data from other devices is
        // most likely to be stale, so this pulls as well as pushes. Gated
        // normally — a quick app-switch round trip inside the cooldown is
        // correctly skipped.
        unawaited(controller.requestSync(manual: false));
      case AppLifecycleState.paused:
        // Push-only, immediately, best-effort — see requestBackgroundPush.
        unawaited(controller.requestBackgroundPush());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Deliberately ignored. `inactive` in particular is transient and
        // noisy — it fires for the app switcher, the notification shade, an
        // incoming call — none of which mean the user left. `paused` is the
        // real "went to background" signal on Android and always follows
        // `inactive` when they actually do, so nothing is missed by not
        // acting here. `detached` is too late to start network work.
        break;
    }
  }

  void _onSessionChanged() {
    final userId = widget.session.currentUserId;
    if (userId == _loadedForUserId) return; // no real change, or already loading it
    if (userId == null) {
      // Logged out — LoginScreen needs no repository; drop the reference so
      // it can't be read stale, but the underlying file is left alone
      // (that account's data is still there for their next login).
      _syncController?.dispose();
      setState(() {
        _loadedForUserId = null;
        _repository = null;
        _syncService = null;
        _syncController = null;
      });
      return;
    }
    unawaited(_loadForUser(userId));
  }

  Future<void> _loadForUser(String userId) async {
    // Clear the previously-loaded repository immediately so HomeScreen can
    // never render with the outgoing account's data while the new one
    // loads — the build() below falls back to a loading spinner whenever
    // _loadedForUserId doesn't match the session's current id.
    _syncController?.dispose();
    setState(() {
      _repository = null;
      _syncService = null;
      _syncController = null;
    });
    final repository = await widget.repositoryFor(userId);
    // The session may have moved on again (rapid logout/login, or switched
    // to a third account) while this await was in flight — only commit if
    // we're still building for the user this load was actually for.
    if (!mounted || widget.session.currentUserId != userId) return;
    final syncService = SyncService(
      repository,
      widget.supabaseService,
      SupabaseSurveyDataSource(),
    );
    setState(() {
      _loadedForUserId = userId;
      _repository = repository;
      _syncService = syncService;
      // Same per-account lifecycle as the repository/service it wraps, so
      // sync status can never leak across an account switch.
      _syncController = SyncController(syncService);
    });
  }

  @override
  Widget build(BuildContext context) {
    // SyncScope wraps MaterialApp deliberately, putting it *above* the
    // Navigator: routes pushed with Navigator.push are siblings of the home
    // route, not descendants of it, so a SyncScope placed below MaterialApp
    // (e.g. around HomeScreen) would be invisible to every pushed screen —
    // which is exactly the set of screens that needs it. Null while logged
    // out; nothing below reads it before login.
    return SyncScope(
      controller: _syncController,
      child: MaterialApp(
        title: 'Survey App',
        theme: AppTheme.light,
        home: _buildHome(),
      ),
    );
  }

  Widget _buildHome() {
    if (!widget.session.isLoggedIn) {
      return LoginScreen(session: widget.session);
    }
    final repository = _repository;
    final syncService = _syncService;
    if (repository == null ||
        syncService == null ||
        _loadedForUserId != widget.session.currentUserId) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return HomeScreen(
      repository: repository,
      supabaseService: widget.supabaseService,
      syncService: syncService,
      session: widget.session,
    );
  }
}
