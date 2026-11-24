import 'dart:async';

import 'package:media_kit/media_kit.dart';

typedef VideoInitializationRunner = Future<void> Function();

Future<void> waitForVideoInitialization(
  VideoInitializationRunner initialize, {
  Duration timeout = const Duration(seconds: 8),
}) {
  return initialize().timeout(timeout);
}

Future<void> waitForPlayerReady(
  Player player, {
  Duration timeout = const Duration(seconds: 8),
  /// When true (netdisk progressive MKV), do not proceed on duration alone —
  /// audio can be ready while video is still black.
  bool requireVideoSize = false,
}) async {
  bool hasDuration = player.state.duration > Duration.zero;
  bool hasVideoSize =
      (player.state.width ?? 0) > 0 && (player.state.height ?? 0) > 0;
  bool ready() =>
      hasDuration && (!requireVideoSize || hasVideoSize);
  if (ready()) {
    return;
  }

  final Completer<void> completer = Completer<void>();
  StreamSubscription<Duration>? durationSubscription;
  StreamSubscription<int?>? widthSubscription;
  StreamSubscription<int?>? heightSubscription;

  void completeIfReady() {
    if (!completer.isCompleted && ready()) {
      completer.complete();
    }
  }

  durationSubscription = player.stream.duration.listen((Duration duration) {
    if (duration > Duration.zero) {
      hasDuration = true;
      completeIfReady();
    }
  });
  widthSubscription = player.stream.width.listen((int? width) {
    hasVideoSize = (width ?? 0) > 0 && (player.state.height ?? 0) > 0;
    completeIfReady();
  });
  heightSubscription = player.stream.height.listen((int? height) {
    hasVideoSize = (player.state.width ?? 0) > 0 && (height ?? 0) > 0;
    completeIfReady();
  });

  try {
    await completer.future.timeout(timeout);
  } on TimeoutException {
    // Soft: proceed anyway so UI is not stuck forever on odd streams.
  } finally {
    await durationSubscription.cancel();
    await widthSubscription.cancel();
    await heightSubscription.cancel();
  }
}
