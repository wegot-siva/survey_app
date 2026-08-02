// Regression test for the sync-failure SnackBar's dismiss control (Issue 2):
// the banner must be explicitly dismissible without touching the underlying
// SyncController.status that the AppBar indicator reads, and a later failure
// must show a fresh banner regardless of whether an earlier one was
// dismissed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/auth_repository.dart';
import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/data/supabase_survey_data_source.dart';
import 'package:survey_app/models/engineer.dart';
import 'package:survey_app/models/user_role.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/session_controller.dart';
import 'package:survey_app/services/supabase_service.dart';
import 'package:survey_app/services/sync_controller.dart';
import 'package:survey_app/services/sync_service.dart';
import 'package:survey_app/ui/home_screen.dart';
import 'package:survey_app/ui/sync_scope.dart';

/// Same shape as the fake in sync_controller_concurrency_test.dart: lets a
/// test flip [pushSucceeds] to force a deterministic failure/success without
/// touching real Supabase.
class _FakeSyncService implements SyncService {
  bool pushSucceeds = true;

  @override
  Future<SyncResult> pushAll() async => pushSucceeds
      ? const SyncResult(success: true)
      : const SyncResult(success: false, message: 'boom');

  @override
  Future<SyncResult> pullMaterialMasterItems() async =>
      const SyncResult(success: true);

  @override
  Future<SyncResult> pullCoreSurveyData() async =>
      const SyncResult(success: true);

  @override
  Future<List<Engineer>> fetchEngineerRoster() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Signed in as Admin from the start, no auth server involved — matches how
/// [SessionController.restore] would resolve a persisted session.
class _FakeAuthRepository implements AuthRepository {
  @override
  Future<AuthenticatedUser?> currentUser() async => const AuthenticatedUser(
    userId: 'admin-1',
    fullName: 'Test Admin',
    role: UserRole.admin,
  );

  @override
  Stream<AuthenticatedUser?> get authStateChanges => const Stream.empty();

  @override
  Future<AuthenticatedUser> signIn(String email, String password) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets(
    'failure SnackBar has a close icon that hides it without clearing '
    'SyncController.status, and a later failure shows a fresh one',
    (tester) async {
      final syncService = _FakeSyncService();
      // Debounce/cooldown irrelevant here — every request in this test is
      // manual, which always bypasses both.
      final controller = SyncController(syncService);
      final session = SessionController(_FakeAuthRepository());
      await session.restore();

      final repository = InMemorySurveyRepository(IdService());
      final realSyncService = SyncService(
        repository,
        SupabaseService(),
        SupabaseSurveyDataSource(),
      );

      await tester.pumpWidget(
        SyncScope(
          controller: controller,
          child: MaterialApp(
            home: HomeScreen(
              repository: repository,
              supabaseService: SupabaseService(),
              syncService: realSyncService,
              session: session,
            ),
          ),
        ),
      );
      // Settles the auto-sync-on-login run (manual: false, unconfigured
      // Supabase makes it a safe no-op) and the initial site load.
      await tester.pumpAndSettle();

      // An unconfigured SupabaseService (no test credentials, same as
      // create_site_screen_test.dart) makes HomeScreen pop its "Built
      // without credentials" dialog on first frame — dismiss it before
      // interacting with the AppBar underneath.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      syncService.pushSucceeds = false;
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();

      expect(controller.status, SyncStatus.failure);
      expect(
        find.text(
          "Couldn't finish syncing. Some changes are still only on this device.",
        ),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      final closeIcon = find.byIcon(Icons.close);
      expect(closeIcon, findsOneWidget);

      // Dismiss — must hide the SnackBar only.
      await tester.tap(closeIcon);
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsNothing);
      expect(controller.status, SyncStatus.failure);
      expect(find.text('Sync failed — tap to retry'), findsOneWidget);

      // Retry is still fully available after dismissal — tap the AppBar
      // indicator itself (not the now-gone SnackBar action).
      syncService.pushSucceeds = true;
      await tester.tap(find.text('Sync failed — tap to retry'));
      await tester.pumpAndSettle();
      expect(controller.status, SyncStatus.success);

      // The success SnackBar's auto-dismiss is a plain Timer, not a
      // Ticker/animation — pumpAndSettle stops as soon as the entrance
      // animation finishes and doesn't wait out a bare Timer, so it's still
      // showing at this point. Advance past its (default 4s) duration
      // explicitly so it's fully gone before the next failure is triggered.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // A subsequent failure re-shows the banner (dismissal wasn't
      // permanent).
      syncService.pushSucceeds = false;
      await tester.tap(find.textContaining('Synced'));
      await tester.pumpAndSettle();

      expect(controller.status, SyncStatus.failure);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      controller.dispose();
    },
  );
}
