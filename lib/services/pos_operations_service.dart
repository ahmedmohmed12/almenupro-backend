import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/pos_permission_catalog.dart';
import '../models/shift_session.dart';
import '../models/staff_user.dart';
import 'admin_auth_service.dart';
import 'api_service.dart';
import 'super_admin_scope_service.dart';

class PosOperationsService extends ChangeNotifier {
  PosOperationsService._();

  static final PosOperationsService instance = PosOperationsService._();

  PosCashierSession? _cashierSession;
  ShiftSession? _activeShift;

  PosCashierSession? get cashierSession => _cashierSession;
  ShiftSession? get activeShift => _activeShift;

  Map<String, bool> get effectivePermissions {
    final session = _cashierSession;
    if (session != null) {
      return PosPermissionCatalog.normalizePermissions(session.permissions);
    }
    if (AdminAuthService.instance.isRestaurantAdmin ||
        AdminAuthService.instance.isSuperAdmin) {
      return PosPermissionCatalog.fullAccessMap();
    }
    return const {};
  }

  bool allows(String permission) {
    return PosPermissionCatalog.roleAllows(effectivePermissions, permission);
  }

  void _notifySessionChanged() => notifyListeners();

  void setCashierSession(PosCashierSession? session) {
    _cashierSession = session;
    _notifySessionChanged();
  }

  void applyCashierSession(PosCashierSession session) {
    _cashierSession = session;
    _notifySessionChanged();
  }

  void clearCashierSession() {
    _cashierSession = null;
    _activeShift = null;
    AdminAuthService.instance.setCashierLoggedIn(false);
    _notifySessionChanged();
  }

  void setActiveShift(ShiftSession? shift) {
    _activeShift = shift;
    _notifySessionChanged();
  }

  Map<String, String> get _headers {
    final auth = AdminAuthService.instance.authHeaders;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...auth,
      ...SuperAdminScopeService.instance.scopeHeaders,
    };
  }

  Uri _posUri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final params = {...?query};
    final authRestaurantId = AdminAuthService.instance.restaurantId;
    final restaurantId = (authRestaurantId != null && authRestaurantId.isNotEmpty)
        ? authRestaurantId
        : SuperAdminScopeService.instance.effectiveRestaurantId;
    if (restaurantId.isNotEmpty) {
      params['restaurant_id'] = restaurantId;
    }
    return Uri.parse('${ApiService.baseUrl}$normalizedPath')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  Future<void> syncCashierPermissionsFromServer() async {
    if (!AdminAuthService.instance.isLoggedIn) return;

    try {
      final response = await http
          .get(_posUri('/pos/session/permissions'), headers: _headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;

      final map = Map<String, dynamic>.from(decoded);
      Map<String, bool>? rawPermissions;
      if (map['permissions'] is Map) {
        rawPermissions = Map<String, dynamic>.from(map['permissions'] as Map)
            .map((key, value) => MapEntry(key.toString(), value == true));
      }
      final permissions = PosPermissionCatalog.normalizePermissions(rawPermissions);

      final roleId = map['roleId']?.toString() ?? '';
      final existing = _cashierSession;

      if (existing != null) {
        applyCashierSession(
          PosCashierSession(
            staff: existing.staff,
            permissions: permissions,
            roleId: roleId.isNotEmpty ? roleId : existing.roleId,
          ),
        );
      } else if (AdminAuthService.instance.isRestaurantAdmin ||
          AdminAuthService.instance.isSuperAdmin) {
        await bootstrapAdminCashier(permissions: permissions);
      }

      await AdminAuthService.instance.persistCashierPermissions(permissions, roleId: roleId);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('POS permission sync failed: $error');
      }
    }
  }

  Future<PosCashierSession> loginWithPin(
    String pin, {
    String? cashierName,
    String? restaurantName,
  }) async {
    final password = pin.trim();
    final name = cashierName?.trim() ?? '';
    final restaurant = restaurantName?.trim() ?? '';
    final auth = AdminAuthService.instance;

    // Standalone cashier JWT login when restaurant + name are provided and the
    // current session is not a restaurant/super admin managing POS staff.
    final useCashierJwtLogin = restaurant.isNotEmpty &&
        name.isNotEmpty &&
        (!auth.isLoggedIn ||
            auth.isCashierSession ||
            (auth.session?.staffId?.isNotEmpty ?? false));

    if (useCashierJwtLogin) {
      final result = await auth.loginCashier(
        restaurantName: restaurant,
        cashierName: name,
        password: password,
      );
      applyCashierSession(result.cashierSession);
      return result.cashierSession;
    }

    if (!auth.isLoggedIn) {
      throw Exception('يرجى إدخال اسم المطعم واسم الكاشير وكلمة المرور');
    }

    final response = await http
        .post(
          _posUri('/pos/staff/login'),
          headers: _headers,
          body: jsonEncode({
            'pin': password,
            'password': password,
            if (name.isNotEmpty) 'cashierName': name,
            if (name.isNotEmpty) 'name': name,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تسجيل دخول الكاشير'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final session = PosCashierSession.fromJson(Map<String, dynamic>.from(decoded));
    applyCashierSession(session);
    await AdminAuthService.instance.setCashierLoggedIn(true);
    await AdminAuthService.instance.persistCashierPermissions(
      session.permissions,
      roleId: session.roleId,
    );
    return session;
  }

  Future<PosCashierSession?> restoreCashierSessionIfNeeded() async {
    if (_cashierSession != null) return _cashierSession;

    final auth = AdminAuthService.instance;
    if (!auth.isLoggedIn) return null;

    if (auth.isCashierSession) {
      final persisted = await auth.loadPersistedCashierPermissions();
      final permissionsRaw = persisted?['permissions'];
      final permissions = <String, bool>{};
      if (permissionsRaw is Map) {
        permissionsRaw.forEach((key, value) {
          permissions[key.toString()] = value == true;
        });
      }
      final staffName = auth.session?.staffName ?? 'كاشير';
      final staffId = auth.session?.staffId ?? 'cashier';
      final roleId = persisted?['roleId']?.toString() ?? 'cashier';
      final session = PosCashierSession(
        staff: StaffUser(
          id: staffId,
          name: staffName,
          roleId: roleId,
        ),
        permissions: permissions.isEmpty
            ? PosPermissionCatalog.normalizePermissions(null)
            : PosPermissionCatalog.normalizePermissions(permissions),
        roleId: roleId,
      );
      applyCashierSession(session);
      return session;
    }

    return null;
  }

  Future<ManagerOverrideResult> requestManagerOverride({
    required String pin,
    required String action,
    String? entityId,
    String? performedById,
    String? performedByName,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/override'),
          headers: _headers,
          body: jsonEncode({
            'pin': pin.trim(),
            'action': action,
            if (entityId != null) 'entityId': entityId,
            if (performedById != null) 'performedById': performedById,
            if (performedByName != null) 'performedByName': performedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشلت موافقة المشرف'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return ManagerOverrideResult.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<ShiftSession?> fetchCurrentShift({String? cashierId}) async {
    final response = await http
        .get(
          _posUri('/pos/shifts/current', {
            if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل الوردية'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final rawShift = decoded['shift'];
    if (rawShift is! Map) {
      _activeShift = null;
      _notifySessionChanged();
      return null;
    }
    _activeShift = ShiftSession.fromJson(Map<String, dynamic>.from(rawShift));
    _notifySessionChanged();
    return _activeShift;
  }

  Future<ShiftSession> openShift({
    required String cashierId,
    required String cashierName,
    required String roleId,
    double openingFloat = 0,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/shifts/open'),
          headers: _headers,
          body: jsonEncode({
            'cashierId': cashierId,
            'cashierName': cashierName,
            'roleId': roleId,
            'openingFloat': openingFloat,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readError(response, 'فشل فتح الوردية'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    _activeShift = ShiftSession.fromJson(Map<String, dynamic>.from(decoded));
    _notifySessionChanged();
    return _activeShift!;
  }

  Future<ShiftSession> closeShift({
    required String shiftId,
    required double closingCashCounted,
    String notes = '',
    String? closedById,
    String? closedByName,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/shifts/$shiftId/close'),
          headers: _headers,
          body: jsonEncode({
            'closingCashCounted': closingCashCounted,
            'notes': notes,
            if (closedById != null) 'closedById': closedById,
            if (closedByName != null) 'closedByName': closedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل إغلاق الوردية'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    final closed = ShiftSession.fromJson(Map<String, dynamic>.from(decoded));
    if (_activeShift?.id == closed.id) {
      _activeShift = null;
      _notifySessionChanged();
    }
    return closed;
  }

  Future<ShiftReportsResult> fetchShiftReports({
    String? restaurantId,
    String? cashierId,
    DateTime? from,
    DateTime? to,
    bool includeOpen = true,
  }) async {
    final scopedRestaurantId =
        restaurantId?.trim().isNotEmpty == true
            ? restaurantId!.trim()
            : SuperAdminScopeService.instance.effectiveRestaurantId;

    final response = await http
        .get(
          _posUri('/pos/shifts', {
            if (scopedRestaurantId.isNotEmpty) 'restaurant_id': scopedRestaurantId,
            if (cashierId != null && cashierId.isNotEmpty) 'cashierId': cashierId,
            if (from != null) 'from': from.toUtc().toIso8601String(),
            if (to != null) 'to': to.toUtc().toIso8601String(),
            'includeOpen': includeOpen ? 'true' : 'false',
          }),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 400) {
      throw Exception(_readError(response, 'معرّف المطعم مطلوب'));
    }
    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل تقارير الورديات'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      final shifts = decoded
          .whereType<Map>()
          .map((row) => ShiftSession.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      return ShiftReportsResult(shifts: shifts);
    }
    if (decoded is! Map) {
      return const ShiftReportsResult(shifts: []);
    }

    final map = Map<String, dynamic>.from(decoded);
    final rawShifts = map['shifts'];
    final shifts = rawShifts is List
        ? rawShifts
            .whereType<Map>()
            .map((row) => ShiftSession.fromJson(Map<String, dynamic>.from(row)))
            .toList()
        : <ShiftSession>[];
    final meta = map['meta'] is Map
        ? ShiftReportsMeta.fromJson(Map<String, dynamic>.from(map['meta'] as Map))
        : const ShiftReportsMeta();

    return ShiftReportsResult(shifts: shifts, meta: meta);
  }

  Future<List<StaffUser>> fetchStaffUsers() async {
    final response = await http
        .get(_posUri('/pos/staff'), headers: _headers)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحميل الموظفين'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((row) => StaffUser.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<StaffUser> createStaffUser({
    required String name,
    required String roleId,
    required String pin,
  }) async {
    final response = await http
        .post(
          _posUri('/pos/staff'),
          headers: _headers,
          body: jsonEncode({'name': name, 'roleId': roleId, 'pin': pin}),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readError(response, 'فشل إضافة الموظف'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return StaffUser.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<StaffUser> updateStaffUser(
    String id, {
    String? name,
    String? roleId,
    String? pin,
    bool? isActive,
  }) async {
    final response = await http
        .patch(
          _posUri('/pos/staff/$id'),
          headers: _headers,
          body: jsonEncode({
            if (name != null) 'name': name,
            if (roleId != null) 'roleId': roleId,
            if (pin != null) 'pin': pin,
            if (isActive != null) 'isActive': isActive,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل تحديث الموظف'));
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }
    return StaffUser.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteStaffUser(String id) async {
    final response = await http
        .delete(
          _posUri('/pos/staff/$id'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل حذف الموظف'));
    }
  }

  Future<void> voidOrder({
    required String orderId,
    required String reason,
    String? performedById,
    String? performedByName,
    String? managerPin,
    String? authorizedById,
    String? authorizedByName,
  }) async {
    final auth = AdminAuthService.instance;
    final restaurantId = auth.restaurantId ??
        SuperAdminScopeService.instance.effectiveRestaurantId;
    final cashier = _cashierSession;
    final actorId = performedById ??
        (auth.isCashierSession ? auth.session?.staffId : null) ??
        cashier?.staff.id;
    final actorName = performedByName ??
        (auth.isCashierSession ? auth.session?.staffName : null) ??
        cashier?.staff.name;

    final response = await http
        .patch(
          Uri.parse('${ApiService.baseUrl}/orders/$orderId/void').replace(
            queryParameters: {
              if (restaurantId.isNotEmpty) 'restaurant_id': restaurantId,
            },
          ),
          headers: _headers,
          body: jsonEncode({
            'reason': reason,
            if (actorId != null && actorId.isNotEmpty) 'performedById': actorId,
            if (actorName != null && actorName.isNotEmpty)
              'performedByName': actorName,
            if (managerPin != null) 'managerPin': managerPin,
            if (authorizedById != null) 'authorizedById': authorizedById,
            if (authorizedByName != null) 'authorizedByName': authorizedByName,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception(_readError(response, 'فشل إلغاء الطلب'));
    }
  }

  String _readError(http.Response response, String fallback) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {}
    if (kDebugMode) {
      debugPrint('POS API error ${response.statusCode}: ${response.body}');
    }
    return '$fallback (${response.statusCode})';
  }

  Future<void> bootstrapAdminCashier({Map<String, bool>? permissions}) async {
    if (_cashierSession != null && permissions == null) return;
    final adminName = AdminAuthService.instance.restaurantName ?? 'مدير';
    applyCashierSession(
      PosCashierSession(
        staff: StaffUser(
          id: 'restaurant_admin',
          name: adminName,
          roleId: 'pos_admin',
        ),
        roleId: 'pos_admin',
        permissions: permissions ?? PosPermissionCatalog.fullAccessMap(),
      ),
    );
  }
}
