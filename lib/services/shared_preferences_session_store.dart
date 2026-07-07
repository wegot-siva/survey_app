import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_role.dart';
import 'session_store.dart';

/// [SessionStore] backed by `shared_preferences` — plain key/value device
/// storage, not a database table, since this is just two small strings.
class SharedPreferencesSessionStore implements SessionStore {
  const SharedPreferencesSessionStore();

  static const _roleKey = 'session_role';
  static const _engineerNameKey = 'session_engineer_name';

  @override
  Future<({UserRole role, String? engineerName})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final roleName = prefs.getString(_roleKey);
    if (roleName == null) return null;

    final role = _roleByName(roleName);
    if (role == null) return null;

    return (role: role, engineerName: prefs.getString(_engineerNameKey));
  }

  @override
  Future<void> save(UserRole role, String? engineerName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_roleKey, role.name);
    if (engineerName == null) {
      await prefs.remove(_engineerNameKey);
    } else {
      await prefs.setString(_engineerNameKey, engineerName);
    }
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_roleKey);
    await prefs.remove(_engineerNameKey);
  }

  UserRole? _roleByName(String name) {
    for (final role in UserRole.values) {
      if (role.name == name) return role;
    }
    return null;
  }
}
