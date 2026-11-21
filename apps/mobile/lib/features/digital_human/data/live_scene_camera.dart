import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Continuous rear-camera capture for digital-human scene sharing.
class LiveSceneCamera {
  CameraController? _controller;
  bool _busyShot = false;

  CameraController? get controller => _controller;
  bool get isReady =>
      _controller != null && (_controller?.value.isInitialized ?? false);

  Future<void> start() async {
    if (isReady) return;
    final List<CameraDescription> cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('没有可用摄像头');
    }
    final CameraDescription rear = cameras.firstWhere(
      (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final CameraController next = CameraController(
      rear,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await next.initialize();
    _controller = next;
  }

  Future<String?> takeStillPath() async {
    final CameraController? cam = _controller;
    if (cam == null || !cam.value.isInitialized || _busyShot) return null;
    if (cam.value.isTakingPicture) return null;
    _busyShot = true;
    try {
      final XFile shot = await cam.takePicture();
      final Directory dir = await getTemporaryDirectory();
      final String path =
          '${dir.path}/live-scene-${DateTime.now().microsecondsSinceEpoch}.jpg';
      await File(shot.path).copy(path);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return path;
    } finally {
      _busyShot = false;
    }
  }

  Future<void> stop() async {
    final CameraController? cam = _controller;
    _controller = null;
    if (cam == null) return;
    try {
      await cam.dispose();
    } catch (error, stack) {
      debugPrint('LiveSceneCamera dispose failed: $error\n$stack');
    }
  }
}
