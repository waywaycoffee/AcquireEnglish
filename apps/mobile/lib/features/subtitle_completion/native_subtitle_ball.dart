import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native SYSTEM_ALERT_WINDOW floating ball (MainActivity WindowManager).
///
/// Prefer this over [flutter_overlay_window] — the latter needs a second
/// Flutter engine entrypoint that breaks under flavor `-t lib/main_prod.dart`.
class NativeSubtitleBall {
  NativeSubtitleBall._();

  static const MethodChannel _channel = MethodChannel(
    'com.acquire.english/subtitle_overlay',
  );

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> canDrawOverlays() async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openOverlaySettings() async {
    if (!_supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } catch (_) {}
  }

  static Future<bool> show({
    required double progress,
    required String label,
  }) async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'showSubtitleBall',
            <String, Object?>{
              'progress': progress.clamp(0.0, 1.0),
              'label': label,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> update({
    required double progress,
    required String label,
  }) async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'updateSubtitleBall',
            <String, Object?>{
              'progress': progress.clamp(0.0, 1.0),
              'label': label,
            },
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> hide() async {
    if (!_supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('hideSubtitleBall');
    } catch (_) {}
  }

  /// Whether the user tapped × (persisted until [setDismissed] false).
  static Future<bool> isDismissed() async {
    if (!_supported) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('isSubtitleBallDismissed') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Persist hide/show. When [dismissed] is true the native ball stays off
  /// even while subtitle fill continues in the foreground service.
  static Future<void> setDismissed(bool dismissed) async {
    if (!_supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setSubtitleBallDismissed',
        <String, Object?>{'dismissed': dismissed},
      );
    } catch (_) {}
  }
}
