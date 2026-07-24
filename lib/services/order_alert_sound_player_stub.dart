import 'package:flutter/services.dart';

import '../models/order_alert_sound.dart';

Future<void> unlockOrderAlertAudio() async {}

Future<void> playOrderAlertSound(OrderAlertSoundType type) async {
  switch (type) {
    case OrderAlertSoundType.bell:
      await SystemSound.play(SystemSoundType.alert);
    case OrderAlertSoundType.soft:
      await SystemSound.play(SystemSoundType.click);
    case OrderAlertSoundType.alarm:
      await SystemSound.play(SystemSoundType.alert);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      await SystemSound.play(SystemSoundType.alert);
  }
}
