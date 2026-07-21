// Contract tests for session state: login must resolve a real user from the
// AuthRepository, restore() must pick up whatever the repository reports as
// the current session before any login call, logout() must clear both the
// in-memory state and delegate to the repository's signOut, and the
// repository's authStateChanges stream must keep the controller in sync.
// Exercised against a fake in-memory AuthRepository so these stay fast and
// don't need a real Supabase project.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/auth_repository.dart';
import 'package:survey_app/models/user_role.dart';
import 'package:survey_app/services/session_controller.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(this._users);

  /// Keyed by "email:password" — the credential pairs this fake accepts.
  final Map<String, AuthenticatedUser> _users;

  final _controller = StreamController<AuthenticatedUser?>.broadcast();
  AuthenticatedUser? _current;
  int signOutCalls = 0;

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
    signOutCalls++;
    _current = null;
    _controller.add(null);
  }

  @override
  Future<AuthenticatedUser?> currentUser() async => _current;

  @override
  Stream<AuthenticatedUser?> get authStateChanges => _controller.stream;

  void dispose() => _controller.close();
}

void main() {
  const sales = AuthenticatedUser(userId: 'u1', fullName: 'Sam Sales', role: UserRole.sales);
  const approver = AuthenticatedUser(
    userId: 'u2',
    fullName: 'Anna Approver',
    role: UserRole.approver,
  );
  const admin = AuthenticatedUser(userId: 'u3', fullName: 'Ada Admin', role: UserRole.admin);
  const engineer = AuthenticatedUser(
    userId: 'u4',
    fullName: 'Ravi Kumar',
    role: UserRole.engineer,
  );

  test('login resolves the user and role from the repository', () async {
    final auth = _FakeAuthRepository({'sam@co.com:pw': sales});
    final session = SessionController(auth);

    final error = await session.login('sam@co.com', 'pw');

    expect(error, isNull);
    expect(session.isLoggedIn, isTrue);
    expect(session.currentRole, UserRole.sales);
    expect(session.currentUserId, 'u1');
    expect(session.currentUserName, 'Sam Sales');
    auth.dispose();
  });

  test('login as Engineer resolves their role and real name', () async {
    final auth = _FakeAuthRepository({'ravi@co.com:pw': engineer});
    final session = SessionController(auth);

    await session.login('ravi@co.com', 'pw');

    expect(session.currentRole, UserRole.engineer);
    expect(session.currentUserName, 'Ravi Kumar');
    auth.dispose();
  });

  test('a failed login surfaces the repository\'s message and changes nothing', () async {
    final auth = _FakeAuthRepository({'sam@co.com:pw': sales});
    final session = SessionController(auth);

    final error = await session.login('sam@co.com', 'wrong-password');

    expect(error, 'Incorrect email or password.');
    expect(session.isLoggedIn, isFalse);
    auth.dispose();
  });

  test('restore() picks up whatever the repository reports as current, before any login', () async {
    final auth = _FakeAuthRepository({});
    auth._current = approver; // simulates an already-persisted Supabase session
    final session = SessionController(auth);

    expect(session.isLoggedIn, isFalse); // nothing until restore() runs
    await session.restore();

    expect(session.isLoggedIn, isTrue);
    expect(session.currentRole, UserRole.approver);
    auth.dispose();
  });

  test('restore() is a no-op when the repository reports no current session', () async {
    final auth = _FakeAuthRepository({});
    final session = SessionController(auth);

    await session.restore();

    expect(session.isLoggedIn, isFalse);
    expect(session.currentRole, isNull);
    auth.dispose();
  });

  test('logout clears in-memory state and delegates to the repository', () async {
    final auth = _FakeAuthRepository({'ada@co.com:pw': admin});
    final session = SessionController(auth);
    await session.login('ada@co.com', 'pw');

    await session.logout();

    expect(session.isLoggedIn, isFalse);
    expect(auth.signOutCalls, 1);
    auth.dispose();
  });

  test('a sign-out triggered elsewhere is reflected via authStateChanges', () async {
    final auth = _FakeAuthRepository({'ada@co.com:pw': admin});
    final session = SessionController(auth);
    await session.restore(); // subscribes to authStateChanges
    await session.login('ada@co.com', 'pw');
    expect(session.isLoggedIn, isTrue);

    // Simulate Supabase invalidating the session on its own (token expiry,
    // remote sign-out) — not through SessionController.logout().
    await auth.signOut();
    await Future<void>.delayed(Duration.zero); // let the stream event land

    expect(session.isLoggedIn, isFalse);
    auth.dispose();
  });
}
