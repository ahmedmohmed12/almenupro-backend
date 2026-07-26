import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/restaurant_settings.dart';
import '../models/working_hours.dart';
import '../utils/firebase_config.dart';
import 'api_service.dart';
import 'super_admin_scope_service.dart';

const _cacheKey = 'restaurant_settings_cache';

class RestaurantSettingsService {
  RestaurantSettingsService._();

  static final RestaurantSettingsService instance = RestaurantSettingsService._();

  RestaurantSettings? _cached;

  RestaurantSettings? get cached => _cached;

  Future<RestaurantSettings> load({String? restaurantId}) async {
    final scopedRestaurantId =
        restaurantId ?? SuperAdminScopeService.instance.effectiveRestaurantId;

    try {
      final remote = await ApiService.instance.fetchSettings(
        restaurantId: scopedRestaurantId,
      );
      _cached = remote;
      await _saveCache(remote, restaurantId: scopedRestaurantId);
      return remote;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RestaurantSettingsService.load remote failed: $error');
      }
    }

    final local = await _loadCache(restaurantId: scopedRestaurantId);
    if (local != null) {
      _cached = local;
      return local;
    }

    if (isFirebaseConfigured) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('settings')
            .doc('restaurant_info')
            .get();
        if (doc.exists && doc.data() != null) {
          final settings = RestaurantSettings.fromJson(doc.data()!);
          _cached = settings;
          await _saveCache(settings);
          return settings;
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('RestaurantSettingsService.load firebase failed: $error');
        }
      }
    }

    _cached = RestaurantSettings.defaults();
    return _cached!;
  }

  Future<void> saveWorkingHours(WorkingHoursSettings workingHours) async {
    final scopedRestaurantId = SuperAdminScopeService.instance.effectiveRestaurantId;
    final current = _cached ?? await load(restaurantId: scopedRestaurantId);
    final updated = current.copyWith(
      workingHours: workingHours,
      updatedAt: DateTime.now().toUtc(),
    );

    await ApiService.instance.updateSettings(
      updated,
      restaurantId: scopedRestaurantId,
    );
    _cached = updated;
    await _saveCache(updated, restaurantId: scopedRestaurantId);
    await _syncFirebase(updated);
  }

  Future<void> saveWhatsappNumber({
    required String countryCode,
    required String phone,
    String? restaurantId,
  }) async {
    final scopedRestaurantId =
        restaurantId ?? SuperAdminScopeService.instance.effectiveRestaurantId;
    final current = _cached ?? await load(restaurantId: scopedRestaurantId);
    final updated = current.copyWith(
      whatsappCountryCode: countryCode.trim(),
      whatsappPhone: phone.trim(),
      updatedAt: DateTime.now().toUtc(),
    );

    await ApiService.instance.updateSettings(
      updated,
      restaurantId: scopedRestaurantId,
    );
    _cached = updated;
    await _saveCache(updated, restaurantId: scopedRestaurantId);
    await _syncFirebase(updated);
  }

  void clearCache() {
    _cached = null;
  }

  Future<void> _syncFirebase(RestaurantSettings settings) async {
    if (!isFirebaseConfigured) return;

    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('restaurant_info')
          .set(settings.toJson(), SetOptions(merge: true));
    } catch (error) {
      if (kDebugMode) {
        debugPrint('RestaurantSettingsService firebase sync failed: $error');
      }
    }
  }

  Future<void> _saveCache(
    RestaurantSettings settings, {
    String? restaurantId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = _cacheKeyFor(restaurantId);
    await prefs.setString(cacheKey, jsonEncode(settings.toJson()));
  }

  Future<RestaurantSettings?> _loadCache({String? restaurantId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKeyFor(restaurantId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return RestaurantSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  String _cacheKeyFor(String? restaurantId) {
    final id = restaurantId?.trim();
    if (id == null || id.isEmpty) return _cacheKey;
    return '${_cacheKey}_$id';
  }
}
