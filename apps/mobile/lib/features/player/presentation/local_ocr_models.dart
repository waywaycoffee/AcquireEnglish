import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../constants/model_cdn.dart';

typedef LocalOcrProgress = void Function(double? fraction, String message);

/// Downloads ML Kit OCR asset packs from the official ECS CDN on first use.
///
/// Native libs stay in the APK; only the ~2–3MB model assets are fetched and
/// registered via [AssetManager.addAssetPath].
class LocalOcrModels {
  LocalOcrModels._();

  static final LocalOcrModels instance = LocalOcrModels._();

  static const MethodChannel _channel = MethodChannel(
    'com.acquire.english/ocr_assets',
  );

  Future<void>? _ensureInFlight;
  bool _ready = false;

  Future<bool> isReady() async {
    if (_ready) {
      return true;
    }
    try {
      final Object? raw = await _channel.invokeMethod<Object?>('isOcrAssetPackReady');
      _ready = raw == true;
      return _ready;
    } catch (error) {
      debugPrint('ocr: isReady failed: $error');
      return false;
    }
  }

  Future<void> ensureModels({LocalOcrProgress? onProgress}) async {
    while (_ensureInFlight != null) {
      await _ensureInFlight;
    }
    if (await isReady()) {
      onProgress?.call(1, 'OCR 模型已就绪');
      return;
    }
    final Completer<void> gate = Completer<void>();
    _ensureInFlight = gate.future;
    try {
      onProgress?.call(0.02, '正在从官方服务器下载 OCR 模型…');
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory packDir = Directory('${docs.path}/ocr_asset_pack');
      final File zipFile = File('${packDir.path}/mlkit-google-ocr-models.zip');
      await packDir.create(recursive: true);

      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
          followRedirects: true,
        ),
      );
      Object? lastError;
      // ECS app host first, then official website (same packs on the server).
      for (final String url in ModelCdn.ocrOfficialUrls) {
        try {
          await dio.download(
            url,
            zipFile.path,
            onReceiveProgress: (int received, int total) {
              if (total <= 0) {
                onProgress?.call(null, '正在从官方服务器下载 OCR 模型…');
                return;
              }
              final double p = (received / total).clamp(0.0, 1.0);
              onProgress?.call(
                0.05 + p * 0.7,
                '官方服务器 OCR ${(p * 100).round()}%',
              );
            },
          );
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
          debugPrint('ocr: download failed via $url: $error');
        }
      }
      if (lastError != null || !zipFile.existsSync() || zipFile.lengthSync() < 1024) {
        throw StateError(
          'OCR 模型下载失败：官方服务器不可用。请检查网络后重试。',
        );
      }

      onProgress?.call(0.8, '正在安装 OCR 模型…');
      final Object? raw = await _channel.invokeMethod<Object?>(
        'installOcrAssetPack',
        <String, Object?>{
          'zipPath': zipFile.path,
          'destDir': packDir.path,
        },
      );
      debugPrint('ocr: install result=$raw');
      if (!await isReady()) {
        throw StateError('OCR 模型安装失败，请重试。');
      }
      onProgress?.call(1, 'OCR 模型已就绪');
    } finally {
      gate.complete();
      _ensureInFlight = null;
    }
  }
}
