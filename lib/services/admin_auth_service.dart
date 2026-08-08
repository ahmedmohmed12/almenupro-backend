import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/admin_role.dart';
import '../models/restaurant.dart';
import 'api_service.dart';

const _sessionKey = 'admin_auth_session';
const _cashierFlagKey = 'admin_cashier_logged_in';
const _cashierPermissionsKey = 'admin_cashier_permissions';

class AdminAuthService {
  AdminAuthService._();

  static final AdminAuthService instance = AdminAuthService._();

  AdminSession? _session;
  var _cashierLoggedIn = false;

  AdminSession? get session => _session;
  bool get isLoggedIn => _session != null && _session!.token.isNotEmpty;
  bool get isSuperAdmin => _session?.isSuperAdmin ?? false;
  bool get isRestaurantAdmin => _session?.isRestaurantAdmin ?? false;
  bool get isCashierSession => _session?.isCashier ?? false;
  String? get restaurantId => _session?.restaurantId;
  String? get restaurantName => _session?.restaurantName;
  String? get token => _session?.token;
  /// True when a POS cashier staff session is active (PIN / cashier login).
  bool get isCashier => _cashierLoggedIn || isCashierSession;

  Map<String, String> get authHeaders {
    if (_session == null) return const {};
    return {'Authorization': 'Bearer ${_session!.token}'};
  }

  Future<void> initialize() async {
    if (_session != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _session = AdminSession.fromJson(Map<String, dynamic>.from(decoded));
      _cashierLoggedIn = prefs.getBool(_cashierFlagKey) ?? false;
      // Re-persist if role was corrected from a legacy mis-parsed session.
      if (_session != null) {
        await _persist(_session!);
        if (_session!.isCashier) {
          _cashierLoggedIn = true;
          await prefs.setBool(_cashierFlagKey, true);
        }
      }
      final valid = await ApiService.instance.validateAuthSession();
      if (!valid) {
        await logout();
      }
    } catch (_) {
      _session = null;
    }
  }

  Future<AdminSession> loginSuperAdmin({
    required String username,
    required String password,
  }) async {
    final session = await ApiService.instance.loginAdmin(
      username: username,
      password: password,
    );
    await _persist(session);
    return session;
  }

  Future<AdminSession> loginRestaurantAdmin({
    required String restaurantSlug,
    required String password,
  }) async {
    final session = await ApiService.instance.loginAdmin(
      restaurantSlug: restaurantSlug,
      password: password,
    );
    await _persist(session);
    return session;
  }

  Future<CashierLoginResult> loginCashier({
    required String restaurantName,
    required String cashierName,
    required String password,
  }) async {
    final result = await ApiService.instance.loginCashier(
      restaurantName: restaurantName,
      cashierName: cashierName,
      password: password,
    );
    await _persist(result.session);
    await setCashierLoggedIn(true);
    await persistCashierPermissions(
      result.permissions,
      roleId: result.roleId,
    );
    return result;
  }

  Future<Map<String, dynamic>?> loadPersistedCashierPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cashierPermissionsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _session = null;
    _cashierLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    await prefs.remove(_cashierFlagKey);
    await prefs.remove(_cashierPermissionsKey);
  }

  Future<void> setCashierLoggedIn(bool value) async {
    _cashierLoggedIn = value;
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setBool(_cashierFlagKey, true);
    } else {
      await prefs.remove(_cashierFlagKey);
    }
  }

  Future<void> persistCashierPermissions(
    Map<String, bool> permissions, {
    String roleId = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cashierPermissionsKey,
      jsonEncode({
        'permissions': permissions,
        'roleId': roleId,
      }),
    );
  }

  Future<void> _persist(AdminSession session) async {
    _session = session;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sessionKey,
      jsonEncode({
        'token': session.token,
        'role': session.role.storageKey,
        'authRole': session.role.storageKey,
        'restaurantId': session.restaurantId,
        'restaurantName': session.restaurantName,
        if (session.staffId != null) 'staffId': session.staffId,
        if (session.staffName != null) 'staffName': session.staffName,
      }),
    );
  }
}
