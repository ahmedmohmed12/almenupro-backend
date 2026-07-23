import 'package:flutter/services.dart';

Future<void> playNewOrderSound() async {
  await SystemSound.play(SystemSoundType.alert);
}
