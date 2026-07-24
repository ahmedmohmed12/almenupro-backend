import 'dart:html' as html;

import '../models/order_alert_sound.dart';

final _players = <OrderAlertSoundType, html.AudioElement>{};
var _audioUnlocked = false;

String _assetPath(OrderAlertSoundType type) {
  switch (type) {
    case OrderAlertSoundType.bell:
      return 'assets/assets/sounds/order_bell.wav';
    case OrderAlertSoundType.soft:
      return 'assets/assets/sounds/order_soft.wav';
    case OrderAlertSoundType.alarm:
      return 'assets/assets/sounds/order_alarm.wav';
  }
}

html.AudioElement _playerFor(OrderAlertSoundType type) {
  return _players.putIfAbsent(
    type,
    () => html.AudioElement(_assetPath(type))..preload = 'auto',
  );
}

Future<void> unlockOrderAlertAudio() async {
  for (final type in OrderAlertSoundType.values) {
    _playerFor(type);
  }

  try {
    final probe = _playerFor(OrderAlertSoundType.soft);
    probe.volume = 0.01;
    await probe.play();
    probe.pause();
    probe.currentTime = 0;
    probe.volume = 1;
    _audioUnlocked = true;
  } catch (_) {
    _audioUnlocked = false;
  }
}

Future<void> playOrderAlertSound(OrderAlertSoundType type) async {
  final player = _playerFor(type);
  player.currentTime = 0;

  try {
    await player.play();
  } catch (_) {
    _audioUnlocked = false;
  }
}

bool get isOrderAlertAudioUnlocked => _audioUnlocked;
