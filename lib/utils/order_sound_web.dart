import 'package:flutter/services.dart';

Future<void> playNewOrderSound() async {
  try {
    await SystemSound.play(SystemSoundType.alert);
  } catch (_) {
    // Web browsers may block autoplay until user interaction.
  }
}
