// Contract tests for session persistence: login must save to the store,
// restore() must read it back before any login call, and logout() must clear
// it — exercised against a fake in-memory SessionStore so these stay fast and
// don't need real shared_preferences plumbing.

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/data/shared_password_auth_repository.dart';
import 'package:survey_app/models/user_role.dart';
import 'package:survey_app/services/session_controller.dart';
import 'package:survey_app/services/session_store.dart';

class _FakeSessionStore implements SessionStore {
  ({UserRole role, String? engineerName})? saved;
  int clearCalls = 0;

  @override
  Future<({UserRole role, String? engineerName})?> load() async => saved;

  @override
  Future<void> save(UserRole role, String? engineerName) async {
    saved = (role: role, engineerName: engineerName);
  }

  @override
  Future<void> clear() async {
    saved = null;
    clearCalls++;
  }
}

void main() {
  const auth = SharedPasswordAuthRepository();

  test('login persists the role to the store', () async {
    final store = _FakeSessionStore();
    final session = SessionController(auth, store);

    await session.login(UserRole.sales, 'sales123');

    expect(store.saved?.role, UserRole.sales);
    expect(store.saved?.engineerName, isNull);
  });

  test('login as Engineer persists the engineer name too', () async {
    final store = _FakeSessionStore();
    final session = SessionController(auth, store);

    await session.login(
      UserRole.engineer,
      'engineer123',
      engineerName: 'Ravi Kumar',
    );

    expect(store.saved?.role, UserRole.engineer);
    expect(store.saved?.engineerName, 'Ravi Kumar');
  });

  test('a failed login does not persist anything', () async {
    final store = _FakeSessionStore();
    final session = SessionController(auth, store);

    final error = await session.login(UserRole.sales, 'wrong-password');

    expect(error, isNotNull);
    expect(store.saved, isNull);
    expect(session.isLoggedIn, isFalse);
  });

  test('restore() picks up a persisted session before any login', () async {
    final store = _FakeSessionStore()
      ..saved = (role: UserRole.approver, engineerName: null);
    final session = SessionController(auth, store);

    expect(session.isLoggedIn, isFalse); // nothing until restore() runs
    await session.restore();

    expect(session.isLoggedIn, isTrue);
    expect(session.currentRole, UserRole.approver);
  });

  test('restore() is a no-op when nothing was persisted', () async {
    final session = SessionController(auth, _FakeSessionStore());

    await session.restore();

    expect(session.isLoggedIn, isFalse);
    expect(session.currentRole, isNull);
  });

  test('logout clears both in-memory state and the store', () async {
    final store = _FakeSessionStore();
    final session = SessionController(auth, store);
    await session.login(UserRole.admin, 'admin123');
    expect(store.saved, isNotNull);

    await session.logout();

    expect(session.isLoggedIn, isFalse);
    expect(store.saved, isNull);
    expect(store.clearCalls, 1);
  });

  test(
    'after logout, restore() finds nothing (does not persist across explicit logout)',
    () async {
      final store = _FakeSessionStore();
      final session = SessionController(auth, store);
      await session.login(UserRole.sales, 'sales123');
      await session.logout();

      // Simulate a fresh app start with a brand-new SessionController reading
      // from the same (now-cleared) store.
      final restarted = SessionController(auth, store);
      await restarted.restore();

      expect(restarted.isLoggedIn, isFalse);
    },
  );

  test('SessionController without a store behaves exactly as before (no persistence)', () async {
    final session = SessionController(auth); // no store passed — existing usage

    await session.login(UserRole.sales, 'sales123');
    expect(session.isLoggedIn, isTrue);

    final freshInstance = SessionController(auth);
    await freshInstance.restore();
    expect(freshInstance.isLoggedIn, isFalse); // nothing to restore, ever
  });
}
