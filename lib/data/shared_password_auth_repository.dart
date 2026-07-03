import '../models/user_role.dart';
import 'auth_repository.dart';

/// Local [AuthRepository] with one shared password per role (Slice A).
///
/// DEV PLACEHOLDER: passwords are bundled in the app and shared by everyone
/// signing in as that role. This is intentional for now — real per-user auth
/// replaces this in a later slice. No network dependency, so login works
/// offline like the rest of the app.
class SharedPasswordAuthRepository implements AuthRepository {
  const SharedPasswordAuthRepository();

  static const Map<UserRole, String> _passwords = {
    UserRole.sales: 'sales123',
    UserRole.engineer: 'engineer123',
    UserRole.approver: 'approver123',
    UserRole.admin: 'admin123',
  };

  @override
  Future<bool> authenticate(UserRole role, String password) async {
    return _passwords[role] == password.trim();
  }
}
