import 'dart:async';

import 'dart:convert';



import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;



import '../models/menu_item.dart';

import '../models/order.dart';

import '../models/restaurant.dart';

import '../models/restaurant_settings.dart';

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



  static const Duration _fetchTimeout = Duration(seconds: 15);



  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ...AdminAuthService.instance.authHeaders,
        ...SuperAdminScopeService.instance.scopeHeaders,
      };

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

  }) async {

    final response = await http

        .post(

          _uri('/restaurants'),

          headers: _jsonHeaders,

          body: jsonEncode({

            'name': name,

            'slug': slug,

            'adminPassword': adminPassword,

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



  Future<Order> createOrder(

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

      return Order.fromMap(map['id']?.toString() ?? '', map);

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



  Future<RestaurantSettings> updateSettings(RestaurantSettings settings) async {

    try {

      final payload = settings.copyWith(updatedAt: DateTime.now().toUtc());

      final body = payload.toJson();

      final restaurantId = AdminAuthService.instance.restaurantId;

      if (restaurantId != null) {

        body['restaurantId'] = restaurantId;

      }



      final response = await http

          .put(

            _uri('/settings'),

            headers: _jsonHeaders,

            body: jsonEncode(body),

          )

          .timeout(_fetchTimeout);



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

        .timeout(_fetchTimeout);



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

        .timeout(_fetchTimeout);



    if (response.statusCode != 200) {

      throw Exception('فشل في تحديث الصنف (${response.statusCode})');

    }



    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {

      throw Exception('استجابة غير متوقعة من السيرفر');

    }



    return MenuItem.fromJson(Map<String, dynamic>.from(decoded));

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

    return {

      'name': data['name'],

      'description': data['description'] ?? '',

      'price': data['price'] ?? 0,

      'categoryName': data['categoryName'] ?? data['category_name'] ?? 'عام',

      'imageUrl': data['imageUrl'] ?? data['image_url'] ?? '',

      'isAvailable': data['isAvailable'] ?? data['is_available'] ?? true,

      'source': data['source'] ?? 'Manual',

    };

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


