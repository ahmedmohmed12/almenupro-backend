import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_alert_sound.dart';
import 'order_alert_sound_player_stub.dart'
    if (dart.library.html) 'order_alert_sound_player_web.dart';

const _soundTypeKey = 'order_alert_sound_type';
const _soundEnabledKey = 'order_alert_sound_enabled';

class OrderAlertSoundService {
  OrderAlertSoundService._();

  static final OrderAlertSoundService instance = OrderAlertSoundService._();

  OrderAlertSoundType _selectedType = OrderAlertSoundType.bell;
  var _enabled = true;
  var _initialized = false;
  var _audioUnlocked = false;

  OrderAlertSoundType get selectedType => _selectedType;
  bool get enabled => _enabled;
  bool get audioUnlocked => _audioUnlocked;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    _selectedType = OrderAlertSoundType.fromStorageKey(
      prefs.getString(_soundTypeKey),
    );
    _enabled = prefs.getBool(_soundEnabledKey) ?? true;
    _initialized = true;
  }

  Future<void> setSelectedType(OrderAlertSoundType type) async {
    _selectedType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_soundTypeKey, type.storageKey);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, value);
  }

  Future<void> unlockFromUserGesture() async {
    await unlockOrderAlertAudio();
    _audioUnlocked = true;
  }

  Future<void> previewSound([OrderAlertSoundType? type]) async {
    await unlockFromUserGesture();
    await playOrderAlertSound(type ?? _selectedType);
  }

  Future<void> playNewOrderAlert() async {
    if (!_enabled) return;

    try {
      await playOrderAlertSound(_selectedType);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Order alert sound failed: $error\n$stackTrace');
      }
    }
  }
}

Future<void> playNewOrderSound() =>
    OrderAlertSoundService.instance.playNewOrderAlert();
