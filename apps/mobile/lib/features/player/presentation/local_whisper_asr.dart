import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:whisper_cpp_flutter_plus/whisper_cpp_flutter_plus.dart';

import '../../settings/presentation/settings_provider.dart';

typedef LocalWhisperProgress = void Function(double? fraction, String message);

/// On-device Whisper.cpp ASR (English `.en` models + multilingual `tiny`/`base`).
///
/// Model weights are **never** shipped in the APK — first use downloads via
/// domestic mirrors (hf-mirror) into the app documents cache.
class LocalWhisperAsr {
  LocalWhisperAsr._();

  static final LocalWhisperAsr instance = LocalWhisperAsr._();

  static const String providerName = '本地 Whisper';
  static const List<String> modelOptions = <String>[
    'tiny.en',
    'base.en',
    'small.en',
    'tiny',
    'base',
  ];
  static const String defaultModel = 'base.en';
  static const String defaultMultilingualModel = 'base';

  final WhisperModelManager _models = WhisperModelManager();
  WhisperEngine? _engine;
  String? _loadedModelId;
  Future<void>? _ensureInFlight;
  Future<void> _engineGate = Future<void>.value();
  static bool isLocalProvider(LearningSettingsState settings) {
    return settings.asrProvider == providerName;
  }

  static WhisperModelDescriptor? catalogDescriptorFor(String modelId) {
    switch (modelId.trim()) {
      case 'tiny.en':
        return WhisperModelCatalog.tinyEnglish;
      case 'base.en':
        return WhisperModelCatalog.baseEnglish;
      case 'tiny':
        return WhisperModelCatalog.tiny;
      case 'base':
        return WhisperModelCatalog.base;
      default:
        return null;
    }
  }

  /// English-only models cannot transcribe Chinese.
  ///
  /// Chinese speech ASR is opt-in ([LearningSettingsState.enableChineseSpeechAsr])
  /// and uses the multilingual [defaultMultilingualModel] downloaded in Settings.
  static String modelForLanguage(
    String modelId,
    String language, {
    bool enableChineseSpeechAsr = false,
  }) {
    final String lang = language.trim().toLowerCase();
    final String id = modelId.trim().isEmpty ? defaultModel : modelId.trim();
    if (lang.startsWith('zh') || lang == 'chinese' || lang == 'cn') {
      if (!enableChineseSpeechAsr) {
        throw StateError(
          '未开启中文语音识别。请到「设置 → AI生成字幕」开启，并下载多语言 Whisper 模型。',
        );
      }
      if (id.endsWith('.en') || id == 'small.en') {
        return defaultMultilingualModel;
      }
    }
    return id;
  }

  static bool isMultilingualModel(String modelId) {
    final String id = modelId.trim();
    return id == 'tiny' || id == 'base' || (!id.contains('.en') && id.isNotEmpty);
  }

  static Uri smallEnglishUri() {
    return Uri.parse(
      'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
    );
  }

  /// Domestic mirrors only for normal installs — huggingface.co is often unreachable
  /// from CN networks and must not be the first (or only) attempt.
  static List<Uri> _downloadUrisFor(WhisperModelDescriptor catalog) {
    final String path = catalog.uri.path;
    final String query = catalog.uri.hasQuery ? '?${catalog.uri.query}' : '';
    final String fileName = catalog.fileName;
    return <Uri>[
      // Primary CN mirror (hf-mirror.com).
      Uri.parse('https://hf-mirror.com$path$query'),
      // Same mirror, branch tip (works when revision pin 404s on the mirror).
      Uri.parse(
        'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/$fileName',
      ),
      // Last resort only — many CN networks time out here.
      catalog.uri,
    ];
  }

  static List<Uri> _smallEnglishDownloadUris() {
    return <Uri>[
      Uri.parse(
        'https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
      ),
      Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin',
      ),
    ];
  }

  static bool _isDomesticMirrorHost(String host) {
    final String h = host.toLowerCase();
    return h.contains('hf-mirror') ||
        h.contains('modelscope') ||
        h.contains('aliyuncs') ||
        h.endsWith('.cn');
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
        final File? cached = await _findCatalogModelOrClearCorrupt(catalog);
        if (cached != null) {
          onProgress?.call(1, '模型已就绪');
          return;
        }
        await _downloadCatalogWithMirrors(catalog, onProgress: onProgress);
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
      onProgress?.call(0, '正在从国内镜像下载 small.en（约 466MB）…');
      Object? lastError;
      for (final Uri uri in _smallEnglishDownloadUris()) {
        try {
          final bool domestic = _isDomesticMirrorHost(uri.host);
          onProgress?.call(
            0,
            domestic
                ? '正在从国内镜像（${uri.host}）下载 small.en…'
                : '国内镜像不可用，回退 ${uri.host}…',
          );
          await for (final ModelDownloadProgress progress in _models.download(
            uri,
            'ggml-small.en.bin',
          )) {
            final double? fraction = progress.fraction;
            onProgress?.call(
              fraction,
              fraction == null
                  ? (domestic
                        ? '正在从国内镜像下载 small.en…'
                        : '正在下载 small.en…')
                  : '${domestic ? '国内镜像' : uri.host} small.en '
                        '${(fraction * 100).clamp(0, 100).round()}%',
            );
          }
          lastError = null;
          break;
        } catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) {
        throw StateError(_modelDownloadFailureMessage('small.en', lastError));
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

  Future<File?> _findCatalogModelOrClearCorrupt(
    WhisperModelDescriptor catalog,
  ) async {
    try {
      return await _models.findCatalogModel(catalog);
    } on FormatException catch (error) {
      debugPrint('whisper: clearing corrupt ${catalog.fileName}: $error');
      try {
        await _models.delete(catalog.fileName);
      } catch (_) {}
      try {
        final File partial = File(
          '${(await _models.directory).path}/${catalog.fileName}.part',
        );
        if (await partial.exists()) {
          await partial.delete();
        }
      } catch (_) {}
      return null;
    }
  }

  Future<void> _downloadCatalogWithMirrors(
    WhisperModelDescriptor catalog, {
    LocalWhisperProgress? onProgress,
  }) async {
    final String id = catalog.id;
    onProgress?.call(
      0,
      '正在从国内镜像下载 $id（约 ${_sizeLabel(catalog.approximateBytes)}）…',
    );
    Object? lastError;
    for (final Uri uri in _downloadUrisFor(catalog)) {
      final bool domestic = _isDomesticMirrorHost(uri.host);
      try {
        onProgress?.call(
          0,
          domestic
              ? '正在从国内镜像（${uri.host}）下载 $id…'
              : '国内镜像不可用，回退 ${uri.host}…',
        );
        await for (final ModelDownloadProgress progress
            in _models.download(
          uri,
          catalog.fileName,
          sha256Hex: catalog.sha256,
        )) {
          final double? fraction = progress.fraction;
          onProgress?.call(
            fraction,
            fraction == null
                ? (domestic ? '正在从国内镜像下载 $id…' : '正在下载 $id…')
                : '${domestic ? '国内镜像' : uri.host} $id '
                      '${(fraction * 100).clamp(0, 100).round()}%',
          );
        }
        final File? verified = await _findCatalogModelOrClearCorrupt(catalog);
        if (verified == null) {
          throw StateError('Whisper 模型 $id 校验失败，请重试。');
        }
        onProgress?.call(1, '模型下载完成');
        return;
      } catch (error) {
        debugPrint('whisper: download via ${uri.host} failed: $error');
        lastError = error;
      }
    }
    throw StateError(_modelDownloadFailureMessage(id, lastError));
  }

  String _modelDownloadFailureMessage(String id, Object? error) {
    final String detail = error == null ? '' : error.toString();
    final String lower = detail.toLowerCase();
    if (lower.contains('socket') ||
        lower.contains('timed out') ||
        lower.contains('failed host lookup') ||
        lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('huggingface')) {
      return 'Whisper 模型 $id 下载失败：国内镜像与备用源均不可用。'
          '请检查网络后在「设置 → AI生成字幕」重试下载。';
    }
    return 'Whisper 模型 $id 下载失败，请检查网络后重试。';
  }

  Future<Map<String, Object?>> transcribeChunk({
    required File file,
    required LearningSettingsState settings,
    required int offsetMs,
    String language = 'en',
    LocalWhisperProgress? onProgress,
  }) async {
    final String lang =
        language.trim().isEmpty ? 'en' : language.trim().toLowerCase();
    final String requested = modelForLanguage(
      settings.asrModel,
      lang,
      enableChineseSpeechAsr: settings.enableChineseSpeechAsr,
    );
    final String modelId = _normalizeModelId(requested);
    if (lang.startsWith('zh') && !await isModelReady(modelId)) {
      throw StateError(
        '中文语音模型尚未下载。请到「设置 → AI生成字幕」下载多语言 Whisper 模型（$modelId）。',
      );
    }
    await ensureModel(modelId, onProgress: onProgress);

    // Claim the mutex slot before awaiting the previous job — the old
    // `_engineGate.then(...); _engineGate = run` pattern raced when two
    // callers both chained off the same previous future.
    final Completer<void> mySlot = Completer<void>();
    final Future<void> previous = _engineGate;
    _engineGate = mySlot.future;
    await previous;
    try {
      Object? lastError;
      for (int attempt = 0; attempt < 3; attempt += 1) {
        try {
          return await _transcribeChunkLocked(
            file: file,
            modelId: modelId,
            offsetMs: offsetMs,
            language: lang,
            onProgress: onProgress,
          );
        } catch (error) {
          lastError = error;
          if (!_isBusyEngineError(error) || attempt >= 2) {
            rethrow;
          }
          debugPrint(
            'whisper: busy engine on attempt ${attempt + 1}, '
            'abandoning and retrying: $error',
          );
          await _abandonEngine();
          await Future<void>.delayed(
            Duration(milliseconds: 80 * (attempt + 1)),
          );
        }
      }
      throw lastError ?? StateError('Whisper 识别失败');
    } finally {
      if (!mySlot.isCompleted) {
        mySlot.complete();
      }
    }
  }

  Future<Map<String, Object?>> _transcribeChunkLocked({
    required File file,
    required String modelId,
    required int offsetMs,
    required String language,
    LocalWhisperProgress? onProgress,
  }) async {
    final WhisperEngine engine = await _loadEngine(
      modelId,
      onProgress: onProgress,
    );
    onProgress?.call(
      null,
      language.startsWith('zh') ? '本地 Whisper 识别中文中…' : '本地 Whisper 识别英文中…',
    );

    final Float32List samples;
    try {
      samples = await WhisperAudio.readWav(file);
    } catch (e) {
      throw StateError('本地 Whisper 无法读取音频块（需 WAV）：$e');
    }
    if (samples.isEmpty) {
      return <String, Object?>{
        'version': 1,
        'language': language.startsWith('zh') ? 'zh' : 'en',
        'lines': const <Map<String, Object?>>[],
      };
    }

    final WhisperTask task = engine.transcribe(
      samples,
      options: TranscribeOptions(
        language: language.startsWith('zh') ? 'zh' : 'en',
      ),
    );
    try {
      final WhisperResult result = await task.result;
      // whisper_cpp decrements _activeJobs in a .then() microtask after the
      // Future completes — yield so the next chunk does not see a stale lock.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return _resultToNormalized(
        result,
        offsetMs: offsetMs,
        language: language.startsWith('zh') ? 'zh' : 'en',
      );
    } catch (error) {
      try {
        task.cancel();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 30));
      rethrow;
    }
  }

  bool _isBusyEngineError(Object error) {
    final String text = error.toString().toLowerCase();
    return text.contains('already has an active transcription') ||
        text.contains('reserved by an active transcription') ||
        text.contains('cannot dispose an engine while transcription');
  }

  /// Drop a stuck engine without waiting for dispose (which throws while busy).
  Future<void> _abandonEngine() async {
    final WhisperEngine? previous = _engine;
    _engine = null;
    _loadedModelId = null;
    if (previous == null) {
      return;
    }
    try {
      previous.dispose();
    } catch (_) {
      // Leave the busy native context orphaned; a fresh load replaces it.
    }
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
    final WhisperEngine? previous = _engine;
    _engine = next;
    _loadedModelId = modelId;
    // Dispose only after swap; ignore busy dispose — orphan the stuck context.
    if (previous != null) {
      try {
        previous.dispose();
      } catch (_) {}
    }
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
    String language = 'en',
  }) {
    final bool chinese = language.startsWith('zh');
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[];
    for (final WhisperSegment segment in result.segments) {
      final String text = segment.text.trim();
      if (text.isEmpty) {
        continue;
      }
      final int startMs = segment.start.inMilliseconds + offsetMs;
      final int endMs = segment.end.inMilliseconds + offsetMs;
      if (endMs <= startMs) {
        continue;
      }
      final List<Map<String, Object?>> words = <Map<String, Object?>>[];
      for (final WhisperToken token in segment.tokens) {
        final String tokenText = token.text.trim();
        if (tokenText.isEmpty ||
            tokenText.startsWith('[') ||
            tokenText.startsWith('<') ||
            tokenText.startsWith('(_')) {
          continue;
        }
        final int wordStart = token.start.inMilliseconds + offsetMs;
        final int wordEnd = token.end.inMilliseconds + offsetMs;
        if (wordEnd <= wordStart) {
          continue;
        }
        words.add(<String, Object?>{
          'text': tokenText,
          'startMs': wordStart,
          'endMs': wordEnd,
          'confidence': token.probability,
        });
      }
      lines.add(<String, Object?>{
        'startMs': startMs,
        'endMs': endMs,
        'english': chinese ? '' : text,
        'chinese': chinese ? text : '',
        'words': words,
      });
    }
    return <String, Object?>{
      'version': 1,
      'language': result.language.isEmpty
          ? (chinese ? 'zh' : 'en')
          : result.language,
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
    if (value == 'tiny' ||
        value.endsWith('/tiny') ||
        value.contains('ggml-tiny.bin')) {
      return 'tiny';
    }
    if (value == 'base' ||
        value.endsWith('/base') ||
        value.contains('ggml-base.bin')) {
      return 'base';
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
