import 'dart:async';

import 'dart:convert';



import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;



import '../models/customer.dart';
import '../models/customer_checkout_profile.dart';
import '../models/delivery_zone.dart';
import '../models/loyalty_cashback.dart';
import '../models/menu_item.dart';

import '../models/order.dart';

import '../models/restaurant.dart';

import '../models/restaurant_settings.dart';
import '../models/smart_closing.dart';

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
        ...AdminAuthService.instance.authHeaders,
        ...SuperAdminScopeService.instance.scopeHeaders,
      };

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



  Future<List<Restaurant>> fetchRestaurants() async {

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

    String restaurantId = defaultRestaurantId,

  }) async {

    try {

      final payload = order.toMap()

        ..['restaurantId'] = restaurantId;



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



  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {

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
  }) async {
    final query = <String, String>{};
    if (slug != null && slug.trim().isNotEmpty) {
      query['slug'] = slug.trim();
    } else {
      query['restaurantId'] = _scopedRestaurantId(restaurantId: restaurantId);
    }

    final response = await http
        .get(_uri('/delivery-zones', query), headers: _publicHeaders)
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
      return profile.hasUsableData ? profile : null;
    } catch (error) {
      debugPrint('Customer lookup failed: $error');
      return null;
    }
  }

  Future<List<Customer>> fetchCustomers({String? restaurantId}) async {
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


