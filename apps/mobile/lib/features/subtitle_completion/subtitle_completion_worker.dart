import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../player/presentation/asr_subtitle_job.dart';
import '../player/presentation/asr_subtitle_service.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/player_subtitle_loader.dart';
import '../player/presentation/subtitle_file_persist.dart';
import '../player/presentation/subtitle_sentence_merge.dart';
import '../settings/presentation/settings_provider.dart';
import '../shared/data/word_lookup_service.dart';
import 'external_subtitle_fill.dart';
import 'subtitle_completion_queue.dart';

typedef SubtitleCompletionProgress =
    void Function(String episodeId, String label);

typedef SubtitleCompletionPersistedHook =
    Future<void> Function({
      required String episodeId,
      required String englishPath,
      required String chinesePath,
    });

typedef SubtitleChineseTranslator =
    Future<List<String>> Function({
      required List<String> sentences,
      required LearningSettingsState settings,
    });

/// Fills missing English (Whisper) and/or Chinese (EN→ZH), then persists.
class SubtitleCompletionWorker {
  SubtitleCompletionWorker({
    this.asrRunner = const AsrSubtitleJobRunner(),
    SubtitleCompletionQueue? queue,
    this.onPersisted,
    this.translateChinese,
    this.externalFill = const ExternalSubtitleFill(),
    Future<Directory> Function()? appSupportDirectory,
  }) : queue = queue ?? SubtitleCompletionQueue(),
       _appSupportDirectory =
           appSupportDirectory ?? getApplicationSupportDirectory;

  final AsrSubtitleJobRunner asrRunner;
  final SubtitleCompletionQueue queue;
  final SubtitleCompletionPersistedHook? onPersisted;
  final SubtitleChineseTranslator? translateChinese;
  final ExternalSubtitleFill externalFill;
  final Future<Directory> Function() _appSupportDirectory;

  LearningSettingsState _settingsForAsr(LearningSettingsState settings) {
    // Mobile import fill always uses on-device Whisper: no Bailian key prompts
    // and no multi‑hundred‑MB cloud uploads that stall the queue for hours.
    if (Platform.isAndroid || Platform.isIOS) {
      final TranslationProviderPreset local =
          asrProviderPresets['本地 Whisper']!;
      final String model = settings.asrProvider == local.name &&
              settings.asrModel.trim().isNotEmpty
          ? settings.asrModel.trim()
          : (local.model.isEmpty ? 'base.en' : local.model);
      return settings.copyWith(
        asrProvider: local.name,
        asrApiKey: '',
        asrBaseUrl: local.baseUrl,
        asrModel: model,
        useCustomAsrEndpoint: false,
      );
    }
    if (describeAsrConfigurationError(settings) == null) {
      return settings;
    }
    final TranslationProviderPreset local =
        asrProviderPresets['本地 Whisper']!;
    return settings.copyWith(
      asrProvider: local.name,
      asrApiKey: '',
      asrBaseUrl: local.baseUrl,
      asrModel: local.model.isEmpty ? 'base.en' : local.model,
      useCustomAsrEndpoint: false,
    );
  }

  Future<bool> processNext({
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    await queue.recoverInterrupted();
    final SubtitleCompletionJob? job = await queue.nextRunnable();
    if (job == null) {
      return false;
    }
    final LearningSettingsState asrSettings = _settingsForAsr(settings);
    await queue.markRunning(job.episodeId);
    final String label = job.needEnglish && job.needChinese
        ? '正在补全中英文字幕…'
        : (job.needEnglish ? '正在用语音生成英文字幕…' : '正在翻译中文字幕…');
    onProgress?.call(job.episodeId, label);
    try {
      await _runJob(
        job: job,
        settings: asrSettings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      await queue.markDone(job.episodeId);
      onProgress?.call(job.episodeId, '字幕已补全');
      return true;
    } catch (error) {
      if (_isCancellation(error, cancellationToken)) {
        // Do not burn attempts — phone lock / detach should retry on resume.
        await queue.markDeferred(job.episodeId, '$error');
        onProgress?.call(job.episodeId, '字幕补全已暂停，稍后自动继续');
        return true;
      }
      await queue.markFailed(job.episodeId, '$error');
      onProgress?.call(job.episodeId, '字幕补全失败：$error');
      return true;
    }
  }

  bool _isCancellation(
    Object error,
    AsrSubtitleCancellationToken? cancellationToken,
  ) {
    if (cancellationToken?.isCancelled == true) {
      return true;
    }
    final String text = '$error'.toLowerCase();
    return text.contains('取消') || text.contains('cancel');
  }

  Future<void> _runJob({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    if (job.needEnglish) {
      await _runAsrEnglishThenMaybeChinese(
        job: job,
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      return;
    }
    if (job.needChinese) {
      await _runChineseFillOnly(
        job: job,
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      return;
    }
  }

  Future<void> _runAsrEnglishThenMaybeChinese({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    if (!isUsableLocalVideoPath(job.videoPath)) {
      throw StateError('本地视频不可用，无法语音识别');
    }

    // Prefer vendored auto-subs / whisper-subtitle-generator when available
    // (desktop). Mobile falls through to on-device Whisper.cpp.
    final List<PlayerSubtitleLine>? externalLines =
        await _tryExternalEnglishLines(
          job: job,
          settings: settings,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
    cancellationToken?.throwIfCancelled();

    late final List<PlayerSubtitleLine> asrLines;
    if (externalLines != null && externalLines.isNotEmpty) {
      asrLines = externalLines;
    } else {
      final String raw = await asrRunner.run(
        episodeId: job.episodeId,
        videoPath: job.videoPath,
        settings: settings,
        referenceSubtitleLines: const <PlayerSubtitleLine>[],
        referenceSignatureOverride: 'pipeline=hear_video',
        forceRegenerate: true,
        jobPipeline: 'hear_video',
        cancellationToken: cancellationToken,
        onProgress: (AsrSubtitleProgress progress) {
          onProgress?.call(job.episodeId, progress.label);
        },
      );
      cancellationToken?.throwIfCancelled();
      asrLines = parseSubtitleLines(raw);
    }
    final List<PlayerSubtitleLine> chineseLines = await _loadChineseLines(job);
    MergedSubtitleBundle bundle = mergeAsrIntoSentences(
      asrLines: asrLines,
      chineseLines: chineseLines,
    );
    if (bundle.sentences.isEmpty) {
      throw StateError('语音识别未产出可用英文字幕');
    }

    // Fill any EN cue still missing ZH — including partial official Chinese
    // tracks (every() wrongly skipped translation when a few lines already had ZH).
    final bool anyChineseMissing = bundle.sentences.any(
      (SubtitleSentence s) =>
          looksEnglish(s.english) && !looksChinese(s.chinese),
    );
    if (job.needChinese || anyChineseMissing) {
      onProgress?.call(job.episodeId, '正在翻译中文字幕…');
      bundle = await _fillBundleChinese(
        bundle: bundle,
        settings: settings,
        cancellationToken: cancellationToken,
      );
    }

    final PersistedBilingualSubtitleFiles? files =
        await persistAsrSentenceSubtitles(
          episodeId: job.episodeId,
          bundle: bundle,
          sourceKey: job.sourceKey,
          appSupportDirectory: _appSupportDirectory,
        );
    if (files == null) {
      throw StateError('字幕保存失败');
    }
    await _notifyPersisted(job.episodeId, files);
  }

  Future<void> _runChineseFillOnly({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    String? enPath = job.enPath;
    if (!isUsableSubtitlePath(enPath)) {
      enPath = await existingOfficialBilibiliSubtitle(
        idKey: job.sourceKey,
        fileName: 'en.srt',
      );
    }
    if (!isUsableSubtitlePath(enPath)) {
      throw StateError('没有可用英文字幕，无法翻译中文');
    }

    onProgress?.call(job.episodeId, '正在翻译中文字幕…');
    final List<PlayerSubtitleLine> englishLines = await loadSubtitleLines(
      enPath!,
    );
    final List<PlayerSubtitleLine> withEnglish = englishLines
        .where((PlayerSubtitleLine line) => looksEnglish(line.english))
        .toList(growable: false);
    if (withEnglish.isEmpty) {
      throw StateError('英文字幕为空，无法翻译中文');
    }

    final List<PlayerSubtitleLine> bilingual = await _fillLinesChinese(
      lines: withEnglish,
      settings: settings,
      cancellationToken: cancellationToken,
    );

    final MergedSubtitleBundle bundle = MergedSubtitleBundle(
      sentences: bilingual
          .map(
            (PlayerSubtitleLine line) => SubtitleSentence(
              startMs: line.startMs,
              endMs: line.endMs,
              english: line.english,
              chinese: line.chinese,
              fragmentStartMs: <int>[line.startMs],
              fragmentEndMs: <int>[line.endMs],
            ),
          )
          .toList(growable: false),
      fragments: bilingual
          .map(
            (PlayerSubtitleLine line) => SubtitleFragment(
              startMs: line.startMs,
              endMs: line.endMs,
              english: line.english,
              chinese: line.chinese,
            ),
          )
          .toList(growable: false),
    );

    final PersistedBilingualSubtitleFiles? files =
        await persistAsrSentenceSubtitles(
          episodeId: job.episodeId,
          bundle: bundle,
          sourceKey: job.sourceKey,
          origin: enTranslationOrigin,
          appSupportDirectory: _appSupportDirectory,
        );
    if (files == null) {
      throw StateError('字幕保存失败');
    }
    await _notifyPersisted(job.episodeId, files);
  }

  Future<List<PlayerSubtitleLine>?> _tryExternalEnglishLines({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    try {
      if (!await externalFill.isAvailable()) {
        return null;
      }
      cancellationToken?.throwIfCancelled();
      final Directory support = await _appSupportDirectory();
      final String outDir =
          '${support.path}${Platform.pathSeparator}external_subtitle_fill'
          '${Platform.pathSeparator}${job.episodeId}';
      final String model = settings.asrModel.trim().isEmpty
          ? 'base.en'
          : settings.asrModel.trim();
      final ExternalSubtitleFillResult? filled = await externalFill.fillMissing(
        videoPath: job.videoPath,
        outDir: outDir,
        needEnglish: true,
        needChinese: job.needChinese,
        enInPath: job.enPath,
        model: model,
        onProgress: (String label) => onProgress?.call(job.episodeId, label),
      );
      cancellationToken?.throwIfCancelled();
      final String? enPath = filled?.enPath;
      if (enPath == null || !File(enPath).existsSync()) {
        return null;
      }
      onProgress?.call(
        job.episodeId,
        '已用 ${filled?.engine ?? 'auto-subs'} 生成英文字幕',
      );
      return loadSubtitleLines(enPath);
    } on AsrSubtitleGenerationException {
      rethrow;
    } catch (_) {
      // Fall back to on-device / cloud ASR.
      return null;
    }
  }

  Future<List<PlayerSubtitleLine>> _loadChineseLines(
    SubtitleCompletionJob job,
  ) async {
    List<PlayerSubtitleLine> chineseLines = const <PlayerSubtitleLine>[];
    final String? zhPath = job.zhPath;
    if (isUsableSubtitlePath(zhPath)) {
      try {
        chineseLines = normalizeChineseOnlySubtitleLines(
          await loadSubtitleLines(zhPath!),
        );
      } catch (_) {}
    }
    if (chineseLines.isEmpty) {
      final String? officialZh = await existingOfficialBilibiliSubtitle(
        idKey: job.sourceKey,
        fileName: 'zh.srt',
      );
      if (officialZh != null) {
        try {
          chineseLines = normalizeChineseOnlySubtitleLines(
            await loadSubtitleLines(officialZh),
          );
        } catch (_) {}
      }
    }
    return chineseLines;
  }

  Future<MergedSubtitleBundle> _fillBundleChinese({
    required MergedSubtitleBundle bundle,
    required LearningSettingsState settings,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final List<PlayerSubtitleLine> filled = await _fillLinesChinese(
      lines: bundle.sentenceLines,
      settings: settings,
      cancellationToken: cancellationToken,
    );
    final List<SubtitleSentence> sentences = <SubtitleSentence>[];
    for (int i = 0; i < bundle.sentences.length; i++) {
      final SubtitleSentence original = bundle.sentences[i];
      final PlayerSubtitleLine line = i < filled.length
          ? filled[i]
          : original.toLine();
      sentences.add(
        SubtitleSentence(
          startMs: original.startMs,
          endMs: original.endMs,
          english: original.english,
          chinese: looksChinese(line.chinese)
              ? line.chinese
              : original.chinese,
          fragmentStartMs: original.fragmentStartMs,
          fragmentEndMs: original.fragmentEndMs,
        ),
      );
    }
    return MergedSubtitleBundle(
      sentences: sentences,
      fragments: bundle.fragments,
    );
  }

  Future<List<PlayerSubtitleLine>> _fillLinesChinese({
    required List<PlayerSubtitleLine> lines,
    required LearningSettingsState settings,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final List<int> pendingIndexes = <int>[];
    final List<String> pendingSentences = <String>[];
    for (int i = 0; i < lines.length; i++) {
      final PlayerSubtitleLine line = lines[i];
      if (looksChinese(line.chinese)) {
        continue;
      }
      final String english = line.english.trim();
      if (!looksEnglish(english)) {
        continue;
      }
      pendingIndexes.add(i);
      pendingSentences.add(english);
    }
    if (pendingSentences.isEmpty) {
      return lines;
    }
    cancellationToken?.throwIfCancelled();

    final List<String> translated;
    if (translateChinese != null) {
      translated = await translateChinese!(
        sentences: pendingSentences,
        settings: settings,
      );
    } else {
      translated = await const WordLookupService().translateSentences(
        sentences: pendingSentences,
        settings: settings,
        targetLanguage: 'zh',
      );
    }
    if (translated.length != pendingSentences.length) {
      throw StateError('中文翻译结果数量不匹配');
    }

    final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(lines);
    for (int i = 0; i < pendingIndexes.length; i++) {
      cancellationToken?.throwIfCancelled();
      final int index = pendingIndexes[i];
      final String zh = translated[i].trim();
      if (zh.isEmpty) {
        continue;
      }
      final PlayerSubtitleLine line = next[index];
      next[index] = PlayerSubtitleLine(
        startTime: line.startTime,
        english: line.english,
        chinese: zh,
        startMs: line.startMs,
        endMs: line.endMs,
        words: line.words,
      );
    }
    return next;
  }

  Future<void> _notifyPersisted(
    String episodeId,
    PersistedBilingualSubtitleFiles files,
  ) async {
    final SubtitleCompletionPersistedHook? hook = onPersisted;
    if (hook == null) {
      return;
    }
    try {
      await hook(
        episodeId: episodeId,
        englishPath: files.englishPath,
        chinesePath: files.chinesePath,
      );
    } catch (_) {}
  }
}
