import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/menu_item.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  factory ApiService() => instance;

  // Web / Desktop: localhost
  // Android Emulator: 10.0.2.2
  // Physical device: machine LAN IP
  static String get baseUrl {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://almenupro-backend.vercel.app/api',
    );
    return configured;
  }
  static const Duration _fetchTimeout = Duration(seconds: 15);

  /// جلب قائمة الأصناف من الباك إند المنشور على Vercel.
  Future<List<MenuItem>> fetchItems() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/items'))
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

  /// Alias for older call sites.
  Future<List<MenuItem>> fetchMenuItems() => fetchItems();

  Future<bool> isOnline() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncMenuItems(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return true;

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/items/sync'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'items': items}),
          )
          .timeout(const Duration(seconds: 20));

      return response.statusCode == 200;
    } catch (error) {
      debugPrint('ApiService syncMenuItems failed: $error');
      return false;
    }
  }
}
