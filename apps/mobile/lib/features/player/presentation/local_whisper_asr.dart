import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import '../../settings/presentation/settings_provider.dart';

typedef LocalWhisperProgress = void Function(double? fraction, String message);

/// On-device Whisper.cpp ASR for English courses (tiny.en / base.en / small.en).
class LocalWhisperAsr {
  LocalWhisperAsr._();

  static final LocalWhisperAsr instance = LocalWhisperAsr._();

  static const String providerName = '本地 Whisper';
  static const List<String> modelOptions = <String>[
    'tiny.en',
    'base.en',
    'small.en',
  ];
  static const String defaultModel = 'base.en';

  final WhisperModelManager _models = WhisperModelManager();
  WhisperEngine? _engine;
  String? _loadedModelId;
  Future<void>? _ensureInFlight;

  static bool isLocalProvider(LearningSettingsState settings) {
    return settings.asrProvider == providerName;
  }

  static WhisperModelDescriptor? catalogDescriptorFor(String modelId) {
    switch (modelId.trim()) {
      case 'tiny.en':
        return WhisperModelCatalog.tinyEnglish;
      case 'base.en':
        return WhisperModelCatalog.baseEnglish;
      default:
        return null;
    }
  }

  static Uri smallEnglishUri() {
    return Uri.parse(
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
    );
  }

  Future<bool> isModelReady(String modelId) async {
    final String id = _normalizeModelId(modelId);
    final WhisperModelDescriptor? catalog = catalogDescriptorFor(id);
    if (catalog != null) {
      return await _models.findCatalogModel(catalog) != null;
    }
    if (id == 'small.en') {
      return await _models.find('ggml-small.en.bin') != null;
    }
    return false;
  }

  Future<void> ensureModel(
    String modelId, {
    LocalWhisperProgress? onProgress,
  }) async {
    final String id = _normalizeModelId(modelId);
    while (_ensureInFlight != null) {
      await _ensureInFlight;
    }
    final Completer<void> gate = Completer<void>();
    _ensureInFlight = gate.future;
    try {
      onProgress?.call(null, '正在检查 Whisper 模型 $id…');
      final WhisperModelDescriptor? catalog = catalogDescriptorFor(id);
      if (catalog != null) {
        final File? cached = await _models.findCatalogModel(catalog);
        if (cached != null) {
          onProgress?.call(1, '模型已就绪');
          return;
        }
        onProgress?.call(
          0,
          '正在下载 $id（约 ${_sizeLabel(catalog.approximateBytes)}）…',
        );
        await for (final ModelDownloadProgress progress
            in _models.downloadCatalogModel(catalog)) {
          final double? fraction = progress.fraction;
          onProgress?.call(
            fraction,
            fraction == null
                ? '正在下载 $id…'
                : '正在下载 $id ${(fraction * 100).clamp(0, 100).round()}%',
          );
        }
        final File? verified = await _models.findCatalogModel(catalog);
        if (verified == null) {
          throw StateError('Whisper 模型 $id 下载失败，请检查网络后重试。');
        }
        onProgress?.call(1, '模型下载完成');
        return;
      }

      if (id != 'small.en') {
        throw StateError('不支持的 Whisper 模型：$id');
      }
      final File? smallCached = await _models.find('ggml-small.en.bin');
      if (smallCached != null) {
        onProgress?.call(1, '模型已就绪');
        return;
      }
      onProgress?.call(0, '正在下载 small.en（约 466MB）…');
      await for (final ModelDownloadProgress progress in _models.download(
        smallEnglishUri(),
        'ggml-small.en.bin',
      )) {
        final double? fraction = progress.fraction;
        onProgress?.call(
          fraction,
          fraction == null
              ? '正在下载 small.en…'
              : '正在下载 small.en ${(fraction * 100).clamp(0, 100).round()}%',
        );
      }
      final File? small = await _models.find('ggml-small.en.bin');
      if (small == null) {
        throw StateError('Whisper 模型 small.en 下载失败，请检查网络后重试。');
      }
      onProgress?.call(1, '模型下载完成');
    } finally {
      gate.complete();
      _ensureInFlight = null;
    }
  }

  Future<Map<String, Object?>> transcribeChunk({
    required File file,
    required LearningSettingsState settings,
    required int offsetMs,
    LocalWhisperProgress? onProgress,
  }) async {
    final String modelId = _normalizeModelId(settings.asrModel);
    await ensureModel(modelId, onProgress: onProgress);
    final WhisperEngine engine = await _loadEngine(
      modelId,
      onProgress: onProgress,
    );
    onProgress?.call(null, '本地 Whisper 识别中…');

    final Float32List samples;
    try {
      samples = await WhisperAudio.readWav(file);
    } catch (e) {
      throw StateError('本地 Whisper 无法读取音频块（需 WAV）：$e');
    }
    if (samples.isEmpty) {
      return <String, Object?>{
        'version': 1,
        'language': 'en',
        'lines': const <Map<String, Object?>>[],
      };
    }

    final WhisperTask task = engine.transcribe(
      samples,
      options: const TranscribeOptions(language: 'en'),
    );
    final WhisperResult result = await task.result;
    return _resultToNormalized(result, offsetMs: offsetMs);
  }

  Future<WhisperEngine> _loadEngine(
    String modelId, {
    LocalWhisperProgress? onProgress,
  }) async {
    if (_engine != null && _loadedModelId == modelId) {
      return _engine!;
    }
    onProgress?.call(null, '正在加载 Whisper 模型 $modelId…');
    final String path = await _modelPath(modelId);
    final WhisperEngine next = await WhisperEngine.load(path);
    _engine?.dispose();
    _engine = next;
    _loadedModelId = modelId;
    return next;
  }

  Future<String> _modelPath(String modelId) async {
    final WhisperModelDescriptor? catalog = catalogDescriptorFor(modelId);
    if (catalog != null) {
      final File? model = await _models.findCatalogModel(catalog);
      if (model == null) {
        throw StateError('Whisper 模型 $modelId 未安装。');
      }
      return model.path;
    }
    final File? small = await _models.find('ggml-small.en.bin');
    if (small == null) {
      throw StateError('Whisper 模型 small.en 未安装。');
    }
    return small.path;
  }

  Map<String, Object?> _resultToNormalized(
    WhisperResult result, {
    required int offsetMs,
  }) {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    for (final WhisperSegment segment in result.segments) {
      final String english = segment.text.trim();
      if (english.isEmpty) {
        continue;
      }
      final int startMs = segment.start.inMilliseconds + offsetMs;
      final int endMs = segment.end.inMilliseconds + offsetMs;
      if (endMs <= startMs) {
        continue;
      }
      final List<Map<String, Object?>> words = <Map<String, Object?>>[];
      for (final WhisperToken token in segment.tokens) {
        final String text = token.text.trim();
        if (text.isEmpty ||
            text.startsWith('[') ||
            text.startsWith('<') ||
            text.startsWith('(_')) {
          continue;
        }
        final int wordStart = token.start.inMilliseconds + offsetMs;
        final int wordEnd = token.end.inMilliseconds + offsetMs;
        if (wordEnd <= wordStart) {
          continue;
        }
        words.add(<String, Object?>{
          'text': text,
          'startMs': wordStart,
          'endMs': wordEnd,
          'confidence': token.probability,
        });
      }
      lines.add(<String, Object?>{
        'startMs': startMs,
        'endMs': endMs,
        'english': english,
        'chinese': '',
        'words': words,
      });
    }
    return <String, Object?>{
      'version': 1,
      'language': result.language.isEmpty ? 'en' : result.language,
      'lines': lines,
    };
  }

  String _normalizeModelId(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return defaultModel;
    }
    if (modelOptions.contains(value)) {
      return value;
    }
    if (value.contains('tiny.en')) {
      return 'tiny.en';
    }
    if (value.contains('small.en')) {
      return 'small.en';
    }
    if (value.contains('base.en')) {
      return 'base.en';
    }
    return defaultModel;
  }

  String _sizeLabel(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }
    return '${(bytes / (1024 * 1024)).round()}MB';
  }

  Future<void> dispose() async {
    _engine?.dispose();
    _engine = null;
    _loadedModelId = null;
    _models.close();
  }
}
