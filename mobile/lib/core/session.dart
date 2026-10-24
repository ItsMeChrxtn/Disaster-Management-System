import 'package:flutter/foundation.dart';

import 'api.dart';

/// Authenticated user state shared across the app (replaces sessionStorage
/// `dm_user` / `dm_token` / `dm_force_password_change`).
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  Map<String, dynamic>? get user => Api.instance.user;
  bool get isAuthenticated => Api.instance.token != null && user != null;

  String get role => (user?['role'] ?? '').toString();
  bool get isAdmin => role == 'admin';
  bool get isSubadmin => role == 'subadmin';
  bool get isResident => role == 'resident';
  bool get isManager => isAdmin || isSubadmin;

  int? get municipalityId {
    final value = user?['municipality_id'];
    if (value == null) return null;
    return int.tryParse(value.toString());
  }

  String get municipalityName => (user?['municipality_name'] ?? '').toString();
  String get fullname => (user?['fullname'] ?? '').toString();

  /// Municipal DRRM office of a sub-admin: CDRRMO for cities, MDRRMO for municipalities.
  String get lguOffice => municipalityName.toLowerCase().contains('city') ? 'CDRRMO' : 'MDRRMO';
  String get roleLabel => isSubadmin ? lguOffice : (isAdmin ? 'PDRRMO · Admin' : (role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1)));

  bool get mustChangePassword => (user?['password_must_change'] ?? '0').toString() == '1';

  Future<void> init() async {
    await Api.instance.load();
    Api.instance.onUnauthorized = () => notifyListeners();
    notifyListeners();
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await Api.instance.post('/auth/login', {'email': email, 'password': password});
    final user = Map<String, dynamic>.from(result['user'] as Map);
    await Api.instance.saveSession(result['access_token'].toString(), user);
    notifyListeners();
    return user;
  }

  Future<void> logout() async {
    try {
      await Api.instance.post('/auth/logout', {});
    } catch (_) {
      // The local session is cleared regardless of the server response.
    }
    await Api.instance.clearSession();
    notifyListeners();
  }

  Future<void> updateUser(Map<String, dynamic> updated) async {
    await Api.instance.saveUser(updated);
    notifyListeners();
  }

  Future<void> clearPasswordMustChange() async {
    final current = Map<String, dynamic>.from(user ?? {});
    current['password_must_change'] = 0;
    await Api.instance.saveUser(current);
    notifyListeners();
  }
}
