import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _orientationChannel = MethodChannel(
  'com.acquire.english/orientation',
);

bool _fullscreenLandscapeActive = false;

bool get isFullscreenLandscapeActive => _fullscreenLandscapeActive;

/// App default: portrait only. Landscape is reserved for video fullscreen.
Future<void> lockPortraitOrientation() async {
  _fullscreenLandscapeActive = false;
  // On Android, SystemChrome alone is remapped to USER on Xiaomi HyperOS and
  // does not actually lock rotation. Drive the Activity API instead.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await _setNativeOrientation('portrait');
    return;
  }
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
}

/// Video fullscreen may rotate into a landscape player chrome.
Future<void> unlockFullscreenLandscapeOrientation() async {
  _fullscreenLandscapeActive = true;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await _setNativeOrientation('landscape');
    return;
  }
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
}

/// Re-assert portrait unless fullscreen video currently owns orientation.
Future<void> ensureDefaultPortraitOrientation() async {
  if (_fullscreenLandscapeActive) {
    return;
  }
  await lockPortraitOrientation();
}

Future<void> _setNativeOrientation(String mode) async {
  try {
    await _orientationChannel.invokeMethod<void>(
      'setOrientation',
      <String, String>{'mode': mode},
    );
  } catch (_) {}
}
