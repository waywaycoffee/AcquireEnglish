import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'bilingual_subtitle_helpers.dart';

typedef OcrFrameCapturer =
    Future<Uint8List?> Function({
      required Player? player,
      required String? videoPath,
      required int positionMs,
    });

typedef OcrTextRecognizer = Future<List<String>> Function(Uint8List jpegBytes);

/// Samples video frames while playing and OCR-reads the bottom subtitle band.
class OcrSubtitleSampler {
  OcrSubtitleSampler({
    this.interval = const Duration(milliseconds: 800),
    this.bottomBandRatio = 0.35,
    this.captureFrame,
    this.recognizeText,
  });

  final Duration interval;
  final double bottomBandRatio;
  final OcrFrameCapturer? captureFrame;
  final OcrTextRecognizer? recognizeText;

  static const MethodChannel _audioToolsChannel = MethodChannel(
    'com.shadowing.english/audio_tools',
  );

  TextRecognizer? _latinRecognizer;
  TextRecognizer? _chineseRecognizer;
  Timer? _timer;
  bool _busy = false;
  bool _cancelled = false;
  Player? _player;
  String? _videoPath;
  bool Function()? _isPlaying;
  int Function()? _positionMs;
  void Function(int positionMs, OcrCueText cue)? _onCue;

  bool get isRunning => _timer != null && !_cancelled;

  Future<void> start({
    required Player? player,
    required String? videoPath,
    required bool Function() isPlaying,
    required int Function() positionMs,
    required void Function(int positionMs, OcrCueText cue) onCue,
  }) async {
    await stop();
    _cancelled = false;
    _player = player;
    _videoPath = videoPath;
    _isPlaying = isPlaying;
    _positionMs = positionMs;
    _onCue = onCue;
    if (recognizeText == null) {
      _latinRecognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
      _chineseRecognizer ??= TextRecognizer(
        script: TextRecognitionScript.chinese,
      );
    }
    _timer = Timer.periodic(interval, (_) {
      unawaited(_tick());
    });
    unawaited(_tick());
  }

  Future<void> stop() async {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
    _busy = false;
  }

  Future<void> dispose() async {
    await stop();
    await _latinRecognizer?.close();
    await _chineseRecognizer?.close();
    _latinRecognizer = null;
    _chineseRecognizer = null;
  }

  Future<void> _tick() async {
    if (_cancelled || _busy) {
      return;
    }
    final bool Function()? playing = _isPlaying;
    if (playing == null || !playing()) {
      return;
    }
    _busy = true;
    try {
      final int ms = _positionMs?.call() ?? 0;
      final Uint8List? frame = await (captureFrame ?? defaultCaptureFrame)(
        player: _player,
        videoPath: _videoPath,
        positionMs: ms,
      );
      if (_cancelled || frame == null || frame.isEmpty) {
        return;
      }
      final Uint8List band = cropBottomBand(frame, bottomBandRatio);
      final List<String> blocks = await (recognizeText ?? _recognizeWithMlKit)(
        band,
      );
      if (_cancelled || blocks.isEmpty) {
        return;
      }
      final OcrCueText cue = splitOcrTextBlocks(blocks);
      if (cue.isEmpty) {
        return;
      }
      _onCue?.call(ms, cue);
    } catch (_) {
      // OCR is best-effort; keep playback uninterrupted.
    } finally {
      _busy = false;
    }
  }

  Future<List<String>> _recognizeWithMlKit(Uint8List jpegBytes) async {
    final Directory tmp = await getTemporaryDirectory();
    final File file = File(
      '${tmp.path}${Platform.pathSeparator}ocr_band_'
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    try {
      await file.writeAsBytes(jpegBytes, flush: true);
      final InputImage input = InputImage.fromFilePath(file.path);
      final List<String> blocks = <String>[];
      final Set<String> seen = <String>{};
      for (final TextRecognizer? recognizer in <TextRecognizer?>[
        _chineseRecognizer,
        _latinRecognizer,
      ]) {
        if (recognizer == null) {
          continue;
        }
        final RecognizedText result = await recognizer.processImage(input);
        for (final TextBlock block in result.blocks) {
          final String text = block.text.trim();
          if (text.isEmpty || !seen.add(text)) {
            continue;
          }
          blocks.add(text);
        }
        for (final TextBlock block in result.blocks) {
          for (final TextLine line in block.lines) {
            final String text = line.text.trim();
            if (text.isEmpty || !seen.add(text)) {
              continue;
            }
            blocks.add(text);
          }
        }
      }
      return blocks;
    } finally {
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  /// Prefer live media_kit screenshot; fall back to Android native frame grab.
  static Future<Uint8List?> defaultCaptureFrame({
    required Player? player,
    required String? videoPath,
    required int positionMs,
  }) async {
    try {
      final Uint8List? shot = await player?.screenshot(format: 'image/jpeg');
      if (shot != null && shot.isNotEmpty) {
        return shot;
      }
    } catch (_) {}
    final String? path = videoPath;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return null;
    }
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final Object? raw = await _audioToolsChannel.invokeMethod(
        'captureFrameAt',
        <String, Object?>{'sourcePath': path, 'positionMs': positionMs},
      );
      if (raw is Uint8List && raw.isNotEmpty) {
        return raw;
      }
      if (raw is String && raw.isNotEmpty) {
        final File file = File(raw);
        if (file.existsSync()) {
          final Uint8List bytes = await file.readAsBytes();
          file.deleteSync();
          return bytes;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Crops the lower [ratio] of a JPEG frame for hard-subtitle OCR.
  static Uint8List cropBottomBand(Uint8List jpegBytes, double ratio) {
    final img.Image? decoded = img.decodeImage(jpegBytes);
    if (decoded == null) {
      return jpegBytes;
    }
    final double safeRatio = ratio.clamp(0.15, 0.6);
    final int bandHeight = (decoded.height * safeRatio).round().clamp(
      1,
      decoded.height,
    );
    final int y = decoded.height - bandHeight;
    final img.Image band = img.copyCrop(
      decoded,
      x: 0,
      y: y,
      width: decoded.width,
      height: bandHeight,
    );
    return Uint8List.fromList(img.encodeJpg(band, quality: 85));
  }

}
