// Smoke test: once signed in, the app shows the Sites home screen. Also
// covers the role-based filtering added in Slices C/D. Uses the in-memory
// repository and a fake AuthRepository (Slice 1b — real per-user Supabase
// Auth, so no shared-per-role password to sign in with here).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/auth_repository.dart';
import 'package:survey_app/data/in_memory_survey_repository.dart';
import 'package:survey_app/main.dart';
import 'package:survey_app/models/user_role.dart';
import 'package:survey_app/services/id_service.dart';
import 'package:survey_app/services/session_controller.dart';
import 'package:survey_app/services/supabase_service.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._users);

  final Map<String, AuthenticatedUser> _users;
  final _controller = StreamController<AuthenticatedUser?>.broadcast();
  AuthenticatedUser? _current;

  @override
  Future<AuthenticatedUser> signIn(String email, String password) async {
    final user = _users['$email:$password'];
    if (user == null) throw const AuthFailure('Incorrect email or password.');
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  @override
  Future<AuthenticatedUser?> currentUser() async => _current;

  @override
  Stream<AuthenticatedUser?> get authStateChanges => _controller.stream;
}


/// The home screen pops a modal "Built without credentials." dialog whenever
/// SupabaseService isn't configured, which it never is under test. It sits in
/// the Overlay absorbing pointers, so any tap-based test must clear it first —
/// assertions-only tests never noticed.
Future<void> _dismissCredentialsDialog(WidgetTester tester) async {
  if (find.text('Built without credentials.').evaluate().isEmpty) return;
  await tester.tap(find.widgetWithText(TextButton, 'OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows empty Sites home screen once signed in', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final auth = _FakeAuthRepository({
      'sam@co.com:pw': const AuthenticatedUser(
        userId: 'u1',
        fullName: 'Sam Sales',
        role: UserRole.sales,
      ),
    });
    final session = SessionController(auth);
    await session.login('sam@co.com', 'pw');

    await tester.pumpWidget(
      SurveyApp(
        supabaseService: supabaseService,
        session: session,
        repositoryFor: (_) async => repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sites'), findsOneWidget);
    expect(find.text('New survey'), findsOneWidget);
    expect(find.text('No sites yet'), findsOneWidget);
    expect(find.text('Sam Sales (Sales)'), findsOneWidget);
  });

  testWidgets(
    'Approver opens on Pending (submitted only), and All still shows every '
    'site — full visibility is grouped, never removed',
    (tester) async {
      final repository = InMemorySurveyRepository(IdService());
      final supabaseService = SupabaseService();
      final auth = _FakeAuthRepository({
        'anna@co.com:pw': const AuthenticatedUser(
          userId: 'u2',
          fullName: 'Anna Approver',
          role: UserRole.approver,
        ),
      });
      final session = SessionController(auth);
      await session.login('anna@co.com', 'pw');

      final ready = await repository.createSite(
        name: 'Ready for review',
        blocks: const [],
      );
      await repository.updateSite(
        ready.copyWith(assignedTo: 'Ravi Kumar', status: 'submitted'),
      );
      final notReady = await repository.createSite(
        name: 'Still in progress',
        blocks: const [],
      );
      await repository.updateSite(
        notReady.copyWith(assignedTo: 'Priya Sharma', status: 'in_progress'),
      );

      await tester.pumpWidget(
        SurveyApp(
          supabaseService: supabaseService,
          session: session,
          repositoryFor: (_) async => repository,
        ),
      );
      await tester.pumpAndSettle();

      // Lands on Pending: only the submitted survey, which is the one the
      // Approver can actually act on.
      expect(find.text('Ready for review'), findsOneWidget);
      expect(find.text('Still in progress'), findsNothing);

      await _dismissCredentialsDialog(tester);

      // The full list is one visible tap away — the Approver's RLS-granted
      // visibility is unchanged, only grouped.
      await tester.tap(find.widgetWithText(Tab, 'All'));
      await tester.pumpAndSettle();

      expect(find.text('Ready for review'), findsOneWidget);
      expect(find.text('Still in progress'), findsOneWidget);
    },
  );

  testWidgets(
    'Approver with nothing submitted sees an explanation, not a blank screen',
    (tester) async {
      final repository = InMemorySurveyRepository(IdService());
      final supabaseService = SupabaseService();
      final auth = _FakeAuthRepository({
        'anna@co.com:pw': const AuthenticatedUser(
          userId: 'u2',
          fullName: 'Anna Approver',
          role: UserRole.approver,
        ),
      });
      final session = SessionController(auth);
      await session.login('anna@co.com', 'pw');

      final site = await repository.createSite(
        name: 'Still in progress',
        blocks: const [],
      );
      await repository.updateSite(site.copyWith(status: 'in_progress'));

      await tester.pumpWidget(
        SurveyApp(
          supabaseService: supabaseService,
          session: session,
          repositoryFor: (_) async => repository,
        ),
      );
      await tester.pumpAndSettle();

      await _dismissCredentialsDialog(tester);
      expect(find.textContaining('Nothing waiting for approval'), findsOneWidget);
      expect(find.text('Still in progress'), findsNothing);

      await tester.tap(find.widgetWithText(Tab, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Still in progress'), findsOneWidget);
    },
  );

  testWidgets('Engineer sees only their assigned surveys', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final auth = _FakeAuthRepository({
      'ravi@co.com:pw': const AuthenticatedUser(
        userId: 'u3',
        fullName: 'Ravi Kumar',
        role: UserRole.engineer,
      ),
    });
    final session = SessionController(auth);
    await session.login('ravi@co.com', 'pw');

    final mine = await repository.createSite(name: 'Mine', blocks: const []);
    await repository.updateSite(
      mine.copyWith(
        assignedTo: 'Ravi Kumar',
        assignedToUserId: 'u3',
        status: 'assigned',
      ),
    );
    final theirs = await repository.createSite(
      name: 'Not mine',
      blocks: const [],
    );
    await repository.updateSite(
      theirs.copyWith(
        assignedTo: 'Priya Sharma',
        assignedToUserId: 'u-priya',
        status: 'assigned',
      ),
    );

    await tester.pumpWidget(
      SurveyApp(
        supabaseService: supabaseService,
        session: session,
        repositoryFor: (_) async => repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Not mine'), findsNothing);
    expect(find.text('Status: assigned'), findsOneWidget);
  });

  testWidgets('boots to the login screen when logged out', (tester) async {
    final repository = InMemorySurveyRepository(IdService());
    final supabaseService = SupabaseService();
    final session = SessionController(_FakeAuthRepository({}));

    await tester.pumpWidget(
      SurveyApp(
        supabaseService: supabaseService,
        session: session,
        repositoryFor: (_) async => repository,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Survey App'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
