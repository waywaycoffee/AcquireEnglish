import 'package:flutter/services.dart';

/// Prefer mic / assistant keys for auto PTT; Space only when [allowSpace] (TV).
bool isTvPrimaryMicKey(LogicalKeyboardKey key, {required bool allowSpace}) {
  if (key == LogicalKeyboardKey.microphoneToggle ||
      key == LogicalKeyboardKey.mediaRecord ||
      key == LogicalKeyboardKey.voiceDial ||
      key == LogicalKeyboardKey.launchAssistant ||
      key == LogicalKeyboardKey.browserSearch) {
    return true;
  }
  if (allowSpace && key == LogicalKeyboardKey.space) {
    return true;
  }
  return false;
}
