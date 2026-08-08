import 'dart:async';

import 'dart:convert';



import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;



import '../models/customer.dart';
import '../models/customer_checkout_profile.dart';
import '../models/delivery_notification.dart';
import '../models/delivery_zone.dart';
import '../models/kitchen.dart';
import '../models/loyalty_cashback.dart';
import '../models/menu_item.dart';

import '../models/order.dart';

import '../models/restaurant.dart';

import '../models/restaurant_settings.dart';
import '../models/smart_closing.dart';
import '../models/staff_user.dart';

import 'admin_auth_service.dart';
import 'super_admin_scope_service.dart';



class ApiService {

  ApiService._();



  static final ApiService instance = ApiService._();



  factory ApiService() => instance;



  static const String defaultRestaurantId = 'rest_molton';



  static String get baseUrl {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://almenupro-backend.vercel.app/api',
    );

    var url = configured.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (!url.endsWith('/api')) {
      url = '$url/api';
    }
    return url;
  }

  static const Map<String, String> _publicHeaders = {
    'Accept': 'application/json',
  };



  static const Duration _fetchTimeout = Duration(seconds: 30);
  static const Duration _writeTimeout = Duration(seconds: 60);



  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...AdminAuthService.instance.authHeaders,
        ...SuperAdminScopeService.instance.scopeHeaders,
      };

  void _ensureAdminApiAccess(String action) {
    if (AdminAuthService.instance.isCashierSession) {
      throw Exception('غير مصرح للكاشير بتنفيذ: $action');
    }
  }

  Future<bool> validateAuthSession() async {
    if (!AdminAuthService.instance.isLoggedIn) return false;
    try {
      final response = await http
          .get(_uri('/auth/me'), headers: _jsonHeaders)
          .timeout(_fetchTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  String _scopedRestaurantId({String? restaurantId}) {
    if (restaurantId != null && restaurantId.isNotEmpty) {
      return restaurantId;
    }
    return SuperAdminScopeService.instance.effectiveRestaurantId;
  }



  Uri _uri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath').replace(queryParameters: query);
  }



  Future<AdminSession> loginAdmin({

    String? username,

    String? restaurantSlug,

    required String password,

  }) async {

    final payload = <String, dynamic>{

      'password': password,

    };



    if (username != null && username.trim().isNotEmpty) {

      payload['username'] = username.trim();

    } else if (restaurantSlug != null && restaurantSlug.trim().isNotEmpty) {

      payload['restaurantSlug'] = restaurantSlug.trim();

    } else {

      throw Exception('يرجى إدخال اسم المستخدم أو معرف المطعم');

    }



    final response = await http

        .post(

          _uri('/auth/login'),

          headers: const {'Content-Type': 'application/json'},

          body: jsonEncode(payload),

        )

        .timeout(_fetchTimeout);



    if (response.statusCode != 200) {

      throw Exception('بيانات الدخول غير صحيحة');

    }



    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return AdminSession.fromJson(Map<String, dynamic>.from(decoded));

  }

  Future<CashierLoginResult> loginCashier({
    required String restaurantName,
    required String cashierName,
    required String password,
  }) async {
    final payload = <String, dynamic>{
      'restaurantName': restaurantName.trim(),
      'cashierName': cashierName.trim(),
      'password': password,
    };

    final response = await http
        .post(
          _uri('/pos/cashier/login'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('بيانات دخول الكاشير غير صحيحة');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    final map = Map<String, dynamic>.from(decoded);
    // Prefer authRole if backend provided it; keep POS role under posRole.
    if (map['authRole'] == null && map['role'] is String) {
      map['authRole'] = map['role'];
    }
    final session = AdminSession.fromJson(map);
    if (session.token.isEmpty) {
      throw Exception('لم يتم استلام رمز الجلسة من السيرفر');
    }
    final posSession = PosCashierSession.fromJson(map);
    return CashierLoginResult(
      session: session,
      cashierSession: posSession,
      permissions: posSession.permissions,
      roleId: posSession.roleId.isNotEmpty
          ? posSession.roleId
          : (map['roleId']?.toString() ?? ''),
    );
  }



  Future<List<Restaurant>> fetchRestaurants() async {
    _ensureAdminApiAccess('عرض المطاعم');

    final response = await http

        .get(_uri('/restaurants'), headers: _jsonHeaders)

        .timeout(_fetchTimeout);



    if (response.statusCode != 200) {

      throw Exception('فشل في تحميل المطاعم (${response.statusCode})');

    }



    final decoded = jsonDecode(response.body);

    if (decoded is! List) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return decoded

        .whereType<Map>()

        .map((entry) => Restaurant.fromJson(Map<String, dynamic>.from(entry)))

        .toList();

  }



  Future<Restaurant> createRestaurant({
    required String name,
    required String slug,
    required String adminPassword,
    String ownerName = '',
    String phone = '',
    RestaurantStatus status = RestaurantStatus.active,
    SubscriptionPlan subscriptionPlan = SubscriptionPlan.free,
    SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
    DateTime? subscriptionExpiresAt,
    String subscriptionNotes = '',
  }) async {
    _ensureAdminApiAccess('إنشاء مطعم');
    final response = await http
        .post(
          _uri('/restaurants'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'name': name,
            'slug': slug,
            'adminPassword': adminPassword,
            if (ownerName.isNotEmpty) 'ownerName': ownerName,
            if (phone.isNotEmpty) 'phone': phone,
            'status': status.apiValue,
            'subscriptionPlan': subscriptionPlan.apiValue,
            'subscriptionStatus': subscriptionStatus.apiValue,
            if (subscriptionExpiresAt != null)
              'subscriptionExpiresAt': subscriptionExpiresAt.toUtc().toIso8601String(),
            if (subscriptionNotes.isNotEmpty) 'subscriptionNotes': subscriptionNotes,
          }),
        )
        .timeout(_fetchTimeout);



    if (response.statusCode != 201 && response.statusCode != 200) {
      String message = 'فشل في إنشاء المطعم (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {
        if (response.body.isNotEmpty) {
          message = response.body;
        }
      }
      if (response.statusCode == 503) {
        throw Exception(
          'التخزين غير دائم على السيرفر. أضف MONGODB_URI في Vercel ثم أعد النشر.\n$message',
        );
      }
      if (response.statusCode == 409) {
        throw Exception('معرف المطعم (slug) مستخدم بالفعل');
      }
      throw Exception(message);
    }



    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return Restaurant.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<Restaurant> updateRestaurant({
    required String id,
    required String name,
    required String slug,
    String ownerName = '',
    String phone = '',
    RestaurantStatus status = RestaurantStatus.active,
    SubscriptionPlan subscriptionPlan = SubscriptionPlan.free,
    SubscriptionStatus subscriptionStatus = SubscriptionStatus.active,
    DateTime? subscriptionExpiresAt,
    String subscriptionNotes = '',
    String? adminPassword,
  }) async {
    final response = await http
        .patch(
          _uri('/restaurants/$id'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'name': name,
            'slug': slug,
            if (ownerName.isNotEmpty) 'ownerName': ownerName,
            if (phone.isNotEmpty) 'phone': phone,
            'status': status.apiValue,
            'subscriptionPlan': subscriptionPlan.apiValue,
            'subscriptionStatus': subscriptionStatus.apiValue,
            if (subscriptionExpiresAt != null)
              'subscriptionExpiresAt': subscriptionExpiresAt.toUtc().toIso8601String(),
            if (subscriptionNotes.isNotEmpty) 'subscriptionNotes': subscriptionNotes,
            if (adminPassword != null && adminPassword.isNotEmpty)
              'adminPassword': adminPassword,
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      String message = 'فشل في تحديث المطعم (${response.statusCode})';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] != null) {
          message = decoded['error'].toString();
        }
      } catch (_) {}
      throw Exception(message);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return Restaurant.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<Restaurant> fetchPublicRestaurant(String slug) async {
    final cleanSlug = slug.trim().toLowerCase();
    if (cleanSlug.isEmpty) {
      throw Exception('معرف المطعم غير صالح');
    }

    final response = await http
        .get(_uri('/restaurants/public/$cleanSlug'), headers: _publicHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode == 404) {
      throw Exception('Restaurant not found');
    }

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل بيانات المطعم (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return Restaurant.fromJson(Map<String, dynamic>.from(decoded));
  }



  Future<List<MenuItem>> fetchPublicItems({
    String? slug,
    String? restaurantId,
  }) async {
    try {
      final query = _publicRestaurantQuery(slug: slug, restaurantId: restaurantId);
      final response = await http
          .get(_uri('/items', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode == 404) {
        throw Exception('Restaurant not found');
      }
      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الأصناف (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return decoded
          .whereType<Map>()
          .map((item) => MenuItem.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.name.trim().isNotEmpty)
          .toList();
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } on FormatException {
      throw Exception('تعذر قراءة بيانات المنيو من السيرفر');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('خطأ في الاتصال بالسيرفر: $error');
    }
  }

  Future<List<int>> fetchTopMenuItemIds({
    String? slug,
    String? restaurantId,
    int limit = 12,
    int days = 90,
  }) async {
    try {
      final query = {
        ..._publicRestaurantQuery(slug: slug, restaurantId: restaurantId),
        'limit': '$limit',
        'days': '$days',
      };
      final response = await http
          .get(_uri('/analytics/top-items', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const [];

      final items = decoded['items'];
      if (items is! List) return const [];

      return items
          .whereType<Map>()
          .map((entry) => entry['menuItemId'])
          .map((id) {
            if (id is int) return id;
            if (id is num) return id.toInt();
            return int.tryParse(id?.toString() ?? '');
          })
          .whereType<int>()
          .where((id) => id > 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> fetchFoodCostReport({
    String? restaurantId,
    int days = 30,
  }) async {
    _ensureAdminApiAccess('تقرير تكلفة الطعام');
    final query = {
      'restaurantId': _scopedRestaurantId(restaurantId: restaurantId),
      'days': '$days',
    };

    final response = await http
        .get(_uri('/analytics/food-cost-report', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل تقرير تكلفة الطعام (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> fetchDailySalesAnalytics({
    String? restaurantId,
    int days = 7,
  }) async {
    _ensureAdminApiAccess('تحليل المبيعات');
    final query = {
      'restaurantId': _scopedRestaurantId(restaurantId: restaurantId),
      'days': '$days',
    };

    final response = await http
        .get(_uri('/analytics/daily-sales', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل تقرير المبيعات (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<List<Map<String, dynamic>>> fetchRecommendations({
    String? slug,
    String? restaurantId,
    required List<int> cartItemIds,
    double subtotal = 0,
    int limit = 8,
  }) async {
    try {
      final query = {
        ..._publicRestaurantQuery(slug: slug, restaurantId: restaurantId),
        'cart': cartItemIds.join(','),
        'subtotal': subtotal.toStringAsFixed(3),
        'limit': '$limit',
      };
      final response = await http
          .get(_uri('/recommendations', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const [];

      final recommendations = decoded['recommendations'];
      if (recommendations is! List) return const [];

      return recommendations
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<RestaurantSettings> fetchPublicSettings({
    String? slug,
    String? restaurantId,
  }) async {
    try {
      final query = _publicRestaurantQuery(slug: slug, restaurantId: restaurantId);
      final response = await http
          .get(_uri('/settings', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode == 404) {
        throw Exception('Restaurant not found');
      }
      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الإعدادات (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('خطأ في تحميل الإعدادات: $error');
    }
  }

  Map<String, String> _publicRestaurantQuery({
    String? slug,
    String? restaurantId,
  }) {
    final cleanSlug = slug?.trim();
    if (cleanSlug != null && cleanSlug.isNotEmpty) {
      return {'slug': cleanSlug.toLowerCase()};
    }
    final id = restaurantId?.trim();
    if (id != null && id.isNotEmpty) {
      return {'restaurant_id': id};
    }
    return {'restaurant_id': defaultRestaurantId};
  }



  Future<List<MenuItem>> fetchItems({String? restaurantId, String? slug}) async {

    try {

      final query = <String, String>{};
      final cleanSlug = slug?.trim();
      if (cleanSlug != null && cleanSlug.isNotEmpty) {
        return fetchPublicItems(slug: cleanSlug);
      } else {
        query['restaurant_id'] = _scopedRestaurantId(restaurantId: restaurantId);
      }



      final response = await http

          .get(_uri('/items', query), headers: _jsonHeaders)

          .timeout(_fetchTimeout);



      if (response.statusCode != 200) {

        throw Exception('فشل في تحميل الأصناف (${response.statusCode})');

      }



      final decoded = jsonDecode(response.body);

      if (decoded is! List) {

        throw Exception('استجابة غير متوقعة من السيرفر');

      }



      return decoded

          .whereType<Map>()

          .map((item) => MenuItem.fromJson(Map<String, dynamic>.from(item)))

          .where((item) => item.name.trim().isNotEmpty)

          .toList();

    } on TimeoutException {

      throw Exception('انتهت مهلة الاتصال بالسيرفر');

    } on FormatException {

      throw Exception('تعذر قراءة بيانات المنيو من السيرفر');

    } catch (error) {

      throw Exception('خطأ في الاتصال بالسيرفر: $error');

    }

  }



  Future<List<MenuItem>> fetchMenuItems({String? restaurantId, String? slug}) =>
      fetchItems(restaurantId: restaurantId, slug: slug);



  Future<bool> isOnline() async {
    try {
      final health = await fetchStorageHealth();
      return health.ok;
    } catch (_) {
      return false;
    }
  }

  Future<StorageHealth> fetchStorageHealth() async {
    final response = await http
        .get(_uri('/health'), headers: _publicHeaders)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('فشل في فحص السيرفر (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return StorageHealth.fromJson(Map<String, dynamic>.from(decoded));
  }



  Future<List<Order>> fetchOrders() async {

    try {

      final query = <String, String>{};

      if (AdminAuthService.instance.restaurantId != null) {
        query['restaurant_id'] = AdminAuthService.instance.restaurantId!;
      }

      final response = await http

          .get(_uri('/orders', query.isEmpty ? null : query), headers: _jsonHeaders)

          .timeout(_fetchTimeout);



      if (response.statusCode != 200) {

        throw Exception('فشل في تحميل الطلبات (${response.statusCode})');

      }



      final decoded = jsonDecode(response.body);

      if (decoded is! List) {

        throw Exception('استجابة غير متوقعة من السيرفر');

      }



      return decoded

          .whereType<Map>()

          .map(

            (raw) => Order.fromMap(

              raw['id']?.toString() ?? '',

              Map<String, dynamic>.from(raw),

            ),

          )

          .toList();

    } on TimeoutException {

      throw Exception('انتهت مهلة الاتصال بالسيرفر');

    } catch (error) {

      throw Exception('خطأ في تحميل الطلبات: $error');

    }

  }



  Future<OrderCreationResult> createOrder(
    Order order, {
    required String restaurantId,
    String? restaurantSlug,
  }) async {
    try {
      final payload = order.toMap()
        ..['restaurantId'] = restaurantId
        ..['restaurant_id'] = restaurantId;
      final slug = restaurantSlug?.trim();
      if (slug != null && slug.isNotEmpty) {
        payload['restaurantSlug'] = slug;
        payload['restaurant_slug'] = slug;
      }



      final response = await http

          .post(

            _uri('/orders'),

            headers: const {'Content-Type': 'application/json'},

            body: jsonEncode(payload),

          )

          .timeout(_fetchTimeout);



      if (response.statusCode != 200 && response.statusCode != 201) {

        throw Exception('فشل في حفظ الطلب (${response.statusCode})');

      }



      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {

        throw Exception('استجابة غير متوقعة من السيرفر');

      }



      final map = Map<String, dynamic>.from(decoded);
      final orderMap = map['order'] is Map
          ? Map<String, dynamic>.from(map['order'] as Map)
          : map;
      final savedOrder = Order.fromMap(
        orderMap['id']?.toString() ?? order.id,
        orderMap,
      );
      SmartClosingPayload? smartClosing;
      if (map['smartClosing'] is Map || map['smart_closing'] is Map) {
        final closingRaw = map['smartClosing'] ?? map['smart_closing'];
        smartClosing = SmartClosingPayload.fromMap(
          Map<String, dynamic>.from(closingRaw as Map),
        );
      }

      return OrderCreationResult(order: savedOrder, smartClosing: smartClosing);

    } on TimeoutException {

      throw Exception('انتهت مهلة الاتصال بالسيرفر');

    } catch (error) {

      throw Exception('خطأ في حفظ الطلب: $error');

    }

  }



  Future<RestaurantSettings> fetchSettings({String? restaurantId, String? slug}) async {

    try {

      final cleanSlug = slug?.trim();
      if (cleanSlug != null && cleanSlug.isNotEmpty) {
        return fetchPublicSettings(slug: cleanSlug);
      }

      final query = <String, String>{
        'restaurant_id': _scopedRestaurantId(restaurantId: restaurantId),
      };

      final response = await http

          .get(_uri('/settings', query), headers: _jsonHeaders)

          .timeout(_fetchTimeout);



      if (response.statusCode == 404 &&
          cleanSlug != null &&
          cleanSlug.isNotEmpty) {
        throw Exception('Restaurant not found');
      }

      if (response.statusCode != 200) {
        throw Exception('فشل في تحميل الإعدادات (${response.statusCode})');
      }



      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {

        throw Exception('استجابة غير متوقعة من السيرفر');

      }



      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));

    } on TimeoutException {

      throw Exception('انتهت مهلة الاتصال بالسيرفر');

    } catch (error) {

      throw Exception('خطأ في تحميل الإعدادات: $error');

    }

  }



  Future<RestaurantSettings> updateSettings(
    RestaurantSettings settings, {
    String? restaurantId,
  }) async {
    _ensureAdminApiAccess('تعديل الإعدادات');

    try {

      final payload = settings.copyWith(updatedAt: DateTime.now().toUtc());

      final body = payload.toJson();

      body['restaurantId'] =
          restaurantId ?? SuperAdminScopeService.instance.effectiveRestaurantId;

      final authRestaurantId = AdminAuthService.instance.restaurantId;
      if (authRestaurantId != null) {
        body['restaurantId'] = authRestaurantId;
      }



      final response = await http

          .put(

            _uri('/settings'),

            headers: _jsonHeaders,

            body: jsonEncode(body),

          )

          .timeout(_writeTimeout);



      if (response.statusCode != 200) {

        throw Exception('فشل في حفظ الإعدادات (${response.statusCode})');

      }



      final decoded = jsonDecode(response.body);

      if (decoded is! Map) {

        return payload;

      }



      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));

    } on TimeoutException {

      throw Exception('انتهت مهلة الاتصال بالسيرفر');

    } catch (error) {

      throw Exception('خطأ في حفظ الإعدادات: $error');

    }

  }



  Future<OrderStatusUpdateResult> updateOrderStatus(
    String orderId,
    OrderStatus status,
  ) async {
    try {
      final response = await http
          .patch(
            _uri('/orders/$orderId/status'),
            headers: _jsonHeaders,
            body: jsonEncode({'status': status.name}),
          )
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        throw Exception('فشل في تحديث الطلب (${response.statusCode})');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return OrderStatusUpdateResult(orderId: orderId);
      }

      final map = Map<String, dynamic>.from(decoded);
      final notificationRaw = map['deliveryNotification'] ?? map['delivery_notification'];
      return OrderStatusUpdateResult(
        orderId: orderId,
        deliveryNotification: notificationRaw is Map
            ? DeliveryNotification.fromMap(
                Map<String, dynamic>.from(notificationRaw),
              )
            : null,
      );
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      throw Exception('خطأ في تحديث الطلب: $error');
    }
  }



  Future<TalabatImportResult> importTalabatMenu({
    required String url,
    required String restaurantId,
  }) async {
    try {
      final response = await http
          .post(
            _uri('/talabat/import'),
            headers: _jsonHeaders,
            body: jsonEncode({
              'url': url,
              'restaurantId': restaurantId,
              'downloadImages': true,
            }),
          )
          .timeout(const Duration(seconds: 180));

      final decoded = jsonDecode(response.body);
      if (response.statusCode != 200) {
        final message = decoded is Map
            ? decoded['error']?.toString() ?? 'فشل استيراد المنيو'
            : 'فشل استيراد المنيو (${response.statusCode})';
        throw Exception(message);
      }

      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }

      return TalabatImportResult.fromJson(Map<String, dynamic>.from(decoded));
    } on TimeoutException {
      throw Exception('انتهت مهلة الاستيراد — حاول مرة أخرى');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('خطأ في استيراد المنيو: $error');
    }
  }

  Future<bool> syncMenuItems(

    List<Map<String, dynamic>> items, {

    required String restaurantId,

  }) async {

    if (items.isEmpty) return true;



    try {

      final response = await http

          .post(

            _uri('/items/sync'),

            headers: _jsonHeaders,

            body: jsonEncode({

              'items': items,

              'restaurantId': restaurantId,

              'downloadImages': true,

            }),

          )

          .timeout(const Duration(seconds: 120));



      return response.statusCode == 200;

    } catch (error) {

      debugPrint('ApiService syncMenuItems failed: $error');

      return false;

    }

  }



  Future<MenuItem> createMenuItem(Map<String, dynamic> data) async {
    _ensureAdminApiAccess('إضافة أصناف المنيو');

    final response = await http

        .post(

          _uri('/items'),

          headers: _jsonHeaders,

          body: jsonEncode(_itemPayload(data)),

        )

        .timeout(_writeTimeout);



    if (response.statusCode != 201 && response.statusCode != 200) {

      throw Exception('فشل في إضافة الصنف (${response.statusCode})');

    }



    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));

  }



  Future<MenuItem> updateMenuItem(String itemId, Map<String, dynamic> data) async {
    _ensureAdminApiAccess('تعديل أصناف المنيو');

    final response = await http

        .put(

          _uri('/items/$itemId'),

          headers: _jsonHeaders,

          body: jsonEncode(_itemPayload(data)),

        )

        .timeout(_writeTimeout);



    if (response.statusCode != 200) {

      throw Exception('فشل في تحديث الصنف (${response.statusCode})');

    }



    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));

  }



  Future<void> reorderMenuItems(List<String> orderedIds) async {
    _ensureAdminApiAccess('إعادة ترتيب المنيو');

    final response = await http

        .put(

          _uri('/items/reorder'),

          headers: _jsonHeaders,

          body: jsonEncode({'orderedIds': orderedIds}),

        )

        .timeout(_writeTimeout);



    if (response.statusCode != 200) {

      throw Exception('فشل في حفظ ترتيب الأصناف (${response.statusCode})');

    }

  }



  Future<void> deleteMenuItem(String itemId) async {
    _ensureAdminApiAccess('حذف أصناف المنيو');

    final response = await http

        .delete(_uri('/items/$itemId'), headers: _jsonHeaders)

        .timeout(_fetchTimeout);



    if (response.statusCode != 200) {

      throw Exception('فشل في حذف الصنف (${response.statusCode})');

    }

  }



  Future<MenuItem> setMenuItemAvailability(String itemId, bool isAvailable) async {

    final response = await http

        .patch(

          _uri('/items/$itemId/availability'),

          headers: _jsonHeaders,

          body: jsonEncode({'isAvailable': isAvailable}),

        )

        .timeout(_fetchTimeout);



    if (response.statusCode != 200) {

      throw Exception('فشل في تحديث حالة الصنف (${response.statusCode})');

    }



    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));

  }



  Map<String, dynamic> _itemPayload(Map<String, dynamic> data) {

    final nameAr = (data['nameAr'] ?? data['name_ar'] ?? data['name'] ?? '').toString().trim();
    final nameEn = (data['nameEn'] ?? data['name_en'] ?? '').toString().trim();
    final descriptionAr = (data['descriptionAr'] ??
            data['description_ar'] ??
            data['description'] ??
            '')
        .toString()
        .trim();
    final descriptionEn =
        (data['descriptionEn'] ?? data['description_en'] ?? '').toString().trim();

    return {

      'name': nameAr.isNotEmpty ? nameAr : nameEn,
      'name_ar': nameAr,
      'name_en': nameEn,
      'description': descriptionAr.isNotEmpty ? descriptionAr : descriptionEn,
      'description_ar': descriptionAr,
      'description_en': descriptionEn,

      'price': data['price'] ?? 0,

      if (data['costPrice'] != null || data['cost_price'] != null)
        'costPrice': data['costPrice'] ?? data['cost_price'],

      'categoryName': data['categoryName'] ?? data['category_name'] ?? 'عام',

      'categoryNameEn': data['categoryNameEn'] ?? data['category_name_en'] ?? '',

      'imageUrl': data['imageUrl'] ?? data['image_url'] ?? '',

      'isAvailable': data['isAvailable'] ?? data['is_available'] ?? true,

      if (data['displayOrder'] != null || data['display_order'] != null)
        'display_order':
            (data['displayOrder'] ?? data['display_order'] as num?)?.toInt() ?? 0,

      if (data['options'] != null)
        'options': (data['options'] as List<dynamic>? ?? [])
            .whereType<Map>()
            .map((option) => Map<String, dynamic>.from(option))
            .toList(),

      'source': data['source'] ?? 'Manual',

    };

  }

  Future<List<DeliveryZone>> fetchDeliveryZones({
    String? slug,
    String? restaurantId,
    bool bustCache = false,
  }) async {
    final query = <String, String>{};
    if (slug != null && slug.trim().isNotEmpty) {
      query['slug'] = slug.trim();
    } else {
      query['restaurantId'] = _scopedRestaurantId(restaurantId: restaurantId);
    }
    if (bustCache) {
      query['_'] = DateTime.now().millisecondsSinceEpoch.toString();
    }

    final headers = AdminAuthService.instance.isLoggedIn
        ? _jsonHeaders
        : _publicHeaders;

    final response = await http
        .get(_uri('/delivery-zones', query), headers: headers)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل مناطق التوصيل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((raw) => DeliveryZone.fromMap(Map<String, dynamic>.from(raw)))
        .where((zone) => zone.isActive)
        .toList();
  }

  Future<List<Kitchen>> fetchKitchens({
    String? restaurantId,
    bool includeInactive = false,
    bool allowCashier = false,
  }) async {
    if (!allowCashier) {
      _ensureAdminApiAccess('fetch kitchens');
    }
    final query = <String, String>{
      'restaurant_id': _scopedRestaurantId(restaurantId: restaurantId),
    };
    if (includeInactive) {
      query['include_inactive'] = '1';
    }

    final response = await http
        .get(_uri('/kitchens', query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل المطابخ (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((raw) => Kitchen.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  Future<Kitchen> saveKitchen({
    required Kitchen kitchen,
    String? restaurantId,
  }) async {
    _ensureAdminApiAccess('save kitchen');
    final scoped = _scopedRestaurantId(restaurantId: restaurantId);
    final payload = kitchen.toMap()..['restaurant_id'] = scoped;

    final isUpdate = kitchen.id.isNotEmpty;
    final response = isUpdate
        ? await http
            .put(
              _uri('/kitchens/${kitchen.id}'),
              headers: _jsonHeaders,
              body: jsonEncode(payload),
            )
            .timeout(_writeTimeout)
        : await http
            .post(
              _uri('/kitchens'),
              headers: _jsonHeaders,
              body: jsonEncode(payload),
            )
            .timeout(_writeTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        isUpdate
            ? 'فشل في تحديث المطبخ (${response.statusCode})'
            : 'فشل في إضافة المطبخ (${response.statusCode})',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw Exception('استجابة غير متوقعة من السيرفر');
    return Kitchen.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteKitchen(String kitchenId) async {
    _ensureAdminApiAccess('delete kitchen');
    final response = await http
        .delete(_uri('/kitchens/$kitchenId'), headers: _jsonHeaders)
        .timeout(_writeTimeout);
    if (response.statusCode != 200) {
      throw Exception('فشل في حذف المطبخ (${response.statusCode})');
    }
  }

  Future<Order> updateOrderKitchen({
    required String orderId,
    required String targetKitchenId,
  }) async {
    try {
      final response = await http
          .patch(
            _uri('/orders/$orderId/kitchen'),
            headers: _jsonHeaders,
            body: jsonEncode({'targetKitchenId': targetKitchenId}),
          )
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) {
        String message = 'فشل في تحديث مطبخ الطلب (${response.statusCode})';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map && decoded['error'] != null) {
            message = decoded['error'].toString();
          }
        } catch (_) {}
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('استجابة غير متوقعة من السيرفر');
      }
      final orderRaw = decoded['order'] is Map
          ? Map<String, dynamic>.from(decoded['order'] as Map)
          : Map<String, dynamic>.from(decoded);
      return Order.fromMap(
        orderRaw['id']?.toString() ?? orderId,
        orderRaw,
      );
    } on TimeoutException {
      throw Exception('انتهت مهلة الاتصال بالسيرفر');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('خطأ في تحديث مطبخ الطلب: $error');
    }
  }

  Future<WalletValidationResult> validateWalletAmount({
    required String phone,
    required double walletAmount,
    required double subtotal,
    required double deliveryFee,
    double promoDiscount = 0,
    String? restaurantId,
    String? slug,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (normalizedPhone.length < 8 || walletAmount <= 0) {
      return const WalletValidationResult(valid: false, error: 'invalid');
    }

    final payload = <String, dynamic>{
      'phone': normalizedPhone,
      'walletAmount': walletAmount,
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'promoDiscount': promoDiscount,
    };
    if (slug != null && slug.trim().isNotEmpty) {
      payload['slug'] = slug.trim();
    } else {
      payload['restaurantId'] = _scopedRestaurantId(restaurantId: restaurantId);
    }

    try {
      final response = await http
          .post(
            _uri('/wallet/validate'),
            headers: _publicHeaders,
            body: jsonEncode(payload),
          )
          .timeout(_fetchTimeout);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const WalletValidationResult(valid: false, error: 'invalid_response');
      }
      return WalletValidationResult.fromMap(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('Wallet validation failed: $error');
      return const WalletValidationResult(valid: false, error: 'network');
    }
  }

  Future<PromoValidationResult> validatePromoCode({
    required String phone,
    required String promoCode,
    required double subtotal,
    required double deliveryFee,
    String? restaurantId,
    String? slug,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (normalizedPhone.length < 8 || promoCode.trim().isEmpty) {
      return const PromoValidationResult(valid: false, error: 'invalid');
    }

    final payload = <String, dynamic>{
      'phone': normalizedPhone,
      'promoCode': promoCode.trim(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
    };
    if (slug != null && slug.trim().isNotEmpty) {
      payload['slug'] = slug.trim();
    } else {
      payload['restaurantId'] = _scopedRestaurantId(restaurantId: restaurantId);
    }

    try {
      final response = await http
          .post(
            _uri('/promo/validate'),
            headers: _publicHeaders,
            body: jsonEncode(payload),
          )
          .timeout(_fetchTimeout);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return const PromoValidationResult(valid: false, error: 'invalid_response');
      }
      return PromoValidationResult.fromMap(Map<String, dynamic>.from(decoded));
    } catch (error) {
      debugPrint('Promo validation failed: $error');
      return const PromoValidationResult(valid: false, error: 'network');
    }
  }

  Future<CustomerCheckoutProfile?> fetchCustomerCheckoutProfile({
    required String phone,
    String? restaurantId,
    String? slug,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (normalizedPhone.length < 8) return null;

    final query = <String, String>{'phone': normalizedPhone};
    if (slug != null && slug.trim().isNotEmpty) {
      query['slug'] = slug.trim();
    } else {
      query['restaurantId'] = _scopedRestaurantId(restaurantId: restaurantId);
    }

    try {
      final response = await http
          .get(_uri('/customers/lookup', query), headers: _publicHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode == 404) return null;
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;

      final profileRaw = decoded['profile'];
      if (profileRaw is! Map) return null;

      final profile = CustomerCheckoutProfile.fromMap(
        Map<String, dynamic>.from(profileRaw),
      );
      if (profile.hasUsableData ||
          profile.hasActivePromo ||
          profile.hasWalletBalance) {
        return profile;
      }
      return null;
    } catch (error) {
      debugPrint('Customer lookup failed: $error');
      return null;
    }
  }

  Future<List<Customer>> fetchCustomers({String? restaurantId}) async {
    _ensureAdminApiAccess('عرض العملاء');
    final query = <String, String>{};
    if (restaurantId != null && restaurantId.trim().isNotEmpty) {
      query['restaurant_id'] = restaurantId.trim();
    } else if (AdminAuthService.instance.restaurantId != null) {
      query['restaurant_id'] = AdminAuthService.instance.restaurantId!;
    }

    final response = await http
        .get(_uri('/customers', query.isEmpty ? null : query), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل العملاء (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((raw) => Customer.fromMap(Map<String, dynamic>.from(raw)))
        .toList();
  }

  Future<CustomerDetailData> fetchCustomerDetail(
    String customerId, {
    String? restaurantId,
  }) async {
    _ensureAdminApiAccess('تفاصيل العميل');
    final query = <String, String>{};
    if (restaurantId != null && restaurantId.trim().isNotEmpty) {
      query['restaurant_id'] = restaurantId.trim();
    } else if (AdminAuthService.instance.restaurantId != null) {
      query['restaurant_id'] = AdminAuthService.instance.restaurantId!;
    }

    final response = await http
        .get(
          _uri('/customers/$customerId', query.isEmpty ? null : query),
          headers: _jsonHeaders,
        )
        .timeout(_fetchTimeout);

    if (response.statusCode == 404) {
      throw Exception('العميل غير موجود');
    }
    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل بيانات العميل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return CustomerDetailData.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<DeliveryZone> createDeliveryZone(DeliveryZone zone) async {
    final payload = zone.toMap()
      ..['restaurantId'] = _scopedRestaurantId(restaurantId: zone.restaurantId);

    final response = await http
        .post(
          _uri('/delivery-zones'),
          headers: _jsonHeaders,
          body: jsonEncode(payload),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('فشل في إضافة منطقة التوصيل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return DeliveryZone.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<DeliveryZone> updateDeliveryZone(DeliveryZone zone) async {
    final response = await http
        .put(
          _uri('/delivery-zones/${zone.id}'),
          headers: _jsonHeaders,
          body: jsonEncode(zone.toMap()),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحديث منطقة التوصيل (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return DeliveryZone.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<void> deleteDeliveryZone(String zoneId) async {
    final response = await http
        .delete(_uri('/delivery-zones/$zoneId'), headers: _jsonHeaders)
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في حذف منطقة التوصيل (${response.statusCode})');
    }
  }

  Future<void> logUpsellEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;

    final response = await http
        .post(
          _uri('/analytics/upsell-events'),
          headers: {
            ..._publicHeaders,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'events': events}),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception('Upsell event logging failed (${response.statusCode})');
    }
  }

  Future<LoyaltyCashbackPreview> calculateLoyaltyCashback({
    required double orderTotal,
    String? restaurantId,
  }) async {
    final scopedId = _scopedRestaurantId(restaurantId: restaurantId);
    final query = <String, String>{'restaurant_id': scopedId};

    final response = await http
        .post(
          _uri('/loyalty/preview', query),
          headers: _jsonHeaders,
          body: jsonEncode({'orderTotal': orderTotal}),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في حساب الكاش باك (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return LoyaltyCashbackPreview.fromMap(Map<String, dynamic>.from(decoded));
  }

  Future<SmartClosingPayload> fetchCheckoutClosingPreview({
    required double subtotal,
    required double deliveryFee,
    required int cartItemCount,
    String? phone,
    String? restaurantId,
    String? slug,
    String orderType = 'Delivery',
  }) async {
    final query = _publicRestaurantQuery(slug: slug, restaurantId: restaurantId);
    final response = await http
        .post(
          _uri('/smart-closing/checkout-preview', query),
          headers: {
            ..._publicHeaders,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'subtotal': subtotal,
            'deliveryFee': deliveryFee,
            'cartItemCount': cartItemCount,
            if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
            'orderType': orderType,
          }),
        )
        .timeout(_fetchTimeout);

    if (response.statusCode != 200) {
      throw Exception('فشل في تحميل رسائل الإغلاق (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('استجابة غير متوقعة من السيرفر');
    }

    return SmartClosingPayload.fromMap(Map<String, dynamic>.from(decoded));
  }

}


class CashierLoginResult {
  const CashierLoginResult({
    required this.session,
    required this.cashierSession,
    required this.permissions,
    this.roleId = '',
  });

  final AdminSession session;
  final PosCashierSession cashierSession;
  final Map<String, bool> permissions;
  final String roleId;
}

class TalabatImportResult {
  const TalabatImportResult({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.synced,
    required this.total,
    this.menuUrl,
  });

  final int added;
  final int updated;
  final int skipped;
  final int synced;
  final int total;
  final String? menuUrl;

  factory TalabatImportResult.fromJson(Map<String, dynamic> json) {
    return TalabatImportResult(
      added: _toInt(json['added']),
      updated: _toInt(json['updated']),
      skipped: _toInt(json['skipped']),
      synced: _toInt(json['synced']),
      total: _toInt(json['total']),
      menuUrl: json['menuUrl']?.toString(),
    );
  }

  static int _toInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class StorageHealth {
  const StorageHealth({
    required this.ok,
    required this.storage,
    required this.persistent,
    this.message,
  });

  final bool ok;
  final String storage;
  final bool persistent;
  final String? message;

  factory StorageHealth.fromJson(Map<String, dynamic> json) {
    return StorageHealth(
      ok: json['ok'] == true,
      storage: json['storage']?.toString() ?? 'unknown',
      persistent: json['persistent'] == true,
      message: json['persistenceMessage']?.toString(),
    );
  }
}


