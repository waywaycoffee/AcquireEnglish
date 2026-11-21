import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/ensure_official_softsubs.dart';
import '../import_course/domain/bilibili_import.dart';
import '../player/presentation/asr_subtitle_job.dart';
import '../player/presentation/asr_subtitle_service.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/hardsub_asr_repair.dart';
import '../player/presentation/local_whisper_asr.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/player_subtitle_loader.dart';
import '../player/presentation/subtitle_file_persist.dart';
import '../player/presentation/subtitle_sentence_merge.dart';
import '../settings/presentation/settings_provider.dart';
import '../shared/data/word_lookup_service.dart';
import '../sync/data/acquire_api_client.dart';
import 'external_subtitle_fill.dart';
import 'shared_bilibili_subtitle_sync.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_status_hub.dart';
import 'subtitle_fill_label.dart';

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
    AsrSubtitleJobRunner? asrRunner,
    SubtitleCompletionQueue? queue,
    this.onPersisted,
    this.translateChinese,
    this.fallbackTranslateChinese,
    this.externalFill = const ExternalSubtitleFill(),
    Future<Directory> Function()? appSupportDirectory,
  }) : asrRunner = asrRunner ?? AsrSubtitleJobRunner(),
       queue = queue ?? SubtitleCompletionQueue(),
       _appSupportDirectory =
           appSupportDirectory ?? getApplicationSupportDirectory;

  final AsrSubtitleJobRunner asrRunner;
  final SubtitleCompletionQueue queue;
  final SubtitleCompletionPersistedHook? onPersisted;
  final SubtitleChineseTranslator? translateChinese;
  final SubtitleChineseTranslator? fallbackTranslateChinese;
  final ExternalSubtitleFill externalFill;
  final Future<Directory> Function() _appSupportDirectory;

  LearningSettingsState _settingsForAsr(LearningSettingsState settings) {
    // On-device Whisper is no longer packaged. Prefer configured cloud ASR
    // (Bailian/Tencent). Import-time English fill should use shared pack /
    // ECS GPU enqueue instead of this path.
    if (!LocalWhisperAsr.isLocalProvider(settings) &&
        describeAsrConfigurationError(settings) == null) {
      return settings;
    }
    final TranslationProviderPreset bailian = asrProviderPresets['阿里云百炼']!;
    return settings.copyWith(
      asrProvider: bailian.name,
      asrBaseUrl: bailian.baseUrl,
      asrModel: bailian.model.isEmpty ? settings.asrModel : bailian.model,
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

    // Stuck translate/ASR jobs: pull bilingual shared pack before Whisper.
    final bool sharedDone = await _trySatisfyFromSharedCache(
      job: job,
      onProgress: onProgress,
    );
    if (sharedDone) {
      await queue.markDone(job.episodeId);
      onProgress?.call(job.episodeId, kSubtitleSharedCacheReadyDetailLabel);
      return true;
    }

    final String asrPrimary = job.asrPrimary.trim().toLowerCase();
    final bool asrZh = asrPrimary.startsWith('zh');
    final bool asrMixed = asrPrimary == 'auto' || asrPrimary == 'mixed';
    final String label;
    if (asrMixed) {
      label = '正在识别中英混合口播…';
    } else if (asrZh && job.needChinese) {
      label = job.needEnglish ? '正在语音生成中文字幕，随后翻译英文…' : '正在用语音生成中文字幕…';
    } else if (job.needEnglish) {
      label = job.needChinese ? '正在语音生成英文字幕，随后翻译中文…' : '正在用语音生成英文字幕…';
    } else {
      label = '正在翻译中文字幕…';
    }
    onProgress?.call(job.episodeId, label);
    try {
      await _runJob(
        job: job,
        settings: asrSettings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      // Persist may leave a sparse side (partial EN→ZH).
      final ({bool needEnglish, bool needChinese})? still =
          await _remainingNeedAfterJob(job);
      if (still != null && (still.needEnglish || still.needChinese)) {
        // ignore: avoid_print
        print(
          'subtitle.completion incomplete ep=${job.episodeId} '
          'needEn=${still.needEnglish} needZh=${still.needChinese}',
        );
        // Partial Chinese progress: re-queue without burning attempts so
        // free-API rate limits around ~60 cues don't permanently fail the job.
        final bool chineseOnlyPartial =
            still.needChinese &&
            !still.needEnglish &&
            await _asrHasAnyChinese(job);
        if (chineseOnlyPartial) {
          await queue.markDeferred(job.episodeId, '中文翻译未完成，稍后继续（已保留已译句子）');
          onProgress?.call(job.episodeId, '中文翻译限流，稍后自动继续…');
          return true;
        }
        await queue.markIncompleteRetry(
          episodeId: job.episodeId,
          needEnglish: still.needEnglish,
          needChinese: still.needChinese,
          error: still.needChinese && !still.needEnglish
              ? '中文翻译未完成，将重试'
              : '补全后字幕仍不完整，将重试',
          asrPrimary: still.needEnglish ? job.asrPrimary : 'en',
        );
        onProgress?.call(job.episodeId, '字幕仍不完整，将有限次重试');
        return true;
      }
      await queue.markDone(job.episodeId);
      onProgress?.call(job.episodeId, '字幕已补全');
      return true;
    } catch (error) {
      if (_isCancellation(error, cancellationToken)) {
        // If user tapped 停止, clearActiveWork already failed the job; markDeferred
        // is a no-op for 用户已停止 so we do not auto-resume.
        await queue.markDeferred(job.episodeId, '$error');
        final List<SubtitleCompletionJob> after = await queue.loadJobs();
        final bool userStopped = after.any(
          (SubtitleCompletionJob row) =>
              row.episodeId == job.episodeId &&
              row.status == SubtitleCompletionStatus.failed &&
              (row.lastError ?? '').contains(
                SubtitleCompletionQueue.userStoppedError,
              ),
        );
        onProgress?.call(
          job.episodeId,
          userStopped ? '字幕补全已停止' : '字幕补全已暂停，稍后自动继续',
        );
        return true;
      }
      // ignore: avoid_print
      print('subtitle.completion failed ep=${job.episodeId} err=$error');
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

  /// Pull ECS shared bilingual pack before local Whisper/translate.
  ///
  /// Returns true when the job's requested sides are fully satisfied on disk.
  Future<bool> _trySatisfyFromSharedCache({
    required SubtitleCompletionJob job,
    SubtitleCompletionProgress? onProgress,
  }) async {
    final AcquireApiClient? api = resolveSharedBilibiliSubtitleApi();
    if (api == null) {
      return false;
    }
    final BilibiliSharedSubtitleIds? ids = resolveBilibiliSharedSubtitleIds(
      sourceKey: job.sourceKey,
      videoAsset: job.videoPath,
    );
    if (ids == null) {
      return false;
    }
    onProgress?.call(job.episodeId, kSubtitleSharedCacheLookupLabel);
    final ({String? enPath, String? zhPath})? shared =
        await tryApplySharedBilibiliSubtitles(api: api, ids: ids);
    if (shared == null) {
      // Local still missing → durable ECS GPU generation (not on-device Whisper).
      if (job.needEnglish) {
        await tryRequestCloudSubtitleGeneration(api: api, ids: ids);
      }
      return false;
    }
    final String? enPath = isUsableSubtitlePath(shared.enPath)
        ? shared.enPath
        : (isUsableSubtitlePath(job.enPath) ? job.enPath : null);
    final String? zhPath = isUsableSubtitlePath(shared.zhPath)
        ? shared.zhPath
        : (isUsableSubtitlePath(job.zhPath) ? job.zhPath : null);
    SubtitleCompletionStatusHub.instance.reportSharedApplied(
      episodeId: job.episodeId,
      enPath: enPath,
      zhPath: zhPath,
    );
    final SubtitleCompletionJob updated = job.copyWith(
      enPath: enPath,
      zhPath: zhPath,
    );
    final ({bool needEnglish, bool needChinese})? still =
        await _remainingNeedAfterJob(updated);
    final bool needEn = still?.needEnglish ?? job.needEnglish;
    final bool needZh = still?.needChinese ?? job.needChinese;
    if (needEn || needZh) {
      if (needEn) {
        await tryRequestCloudSubtitleGeneration(api: api, ids: ids);
      }
      // Partial shared hit — refresh paths/flags so local only fills the rest
      // when cloud submit is unavailable (enqueue still runs as fallback).
      await queue.enqueue(
        episodeId: job.episodeId,
        videoPath: job.videoPath,
        enPath: enPath,
        zhPath: zhPath,
        sourceKey: job.sourceKey,
        needEnglish: needEn,
        needChinese: needZh,
        asrPrimary: job.asrPrimary,
      );
      return false;
    }
    if (onPersisted != null &&
        isUsableSubtitlePath(enPath) &&
        isUsableSubtitlePath(zhPath)) {
      await onPersisted!(
        episodeId: job.episodeId,
        englishPath: enPath!,
        chinesePath: zhPath!,
      );
    }
    return true;
  }

  Future<bool> _asrHasAnyChinese(SubtitleCompletionJob job) async {
    final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
      episodeId: job.episodeId,
      sourceKey: job.sourceKey,
      videoFingerprint: videoFileFingerprint(job.videoPath),
      appSupportDirectory: _appSupportDirectory,
    );
    if (asrBundle == null || asrBundle.sentences.isEmpty) {
      return false;
    }
    return asrBundle.sentences.any(
      (SubtitleSentence s) => looksChinese(s.chinese),
    );
  }

  Future<({bool needEnglish, bool needChinese})?> _remainingNeedAfterJob(
    SubtitleCompletionJob job,
  ) async {
    final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
      episodeId: job.episodeId,
      sourceKey: job.sourceKey,
      videoFingerprint: videoFileFingerprint(job.videoPath),
      appSupportDirectory: _appSupportDirectory,
    );
    bool needEnglish = job.needEnglish;
    bool needChinese = job.needChinese;
    if (asrBundle != null && asrBundle.sentences.isNotEmpty) {
      final int total = asrBundle.sentences.length;
      final int enHits = asrBundle.sentences
          .where((SubtitleSentence s) => looksEnglish(s.english))
          .length;
      final int zhHits = asrBundle.sentences
          .where((SubtitleSentence s) => looksChinese(s.chinese))
          .length;
      final bool trustedZh = await hasTrustedAsrChineseTranslation(
        episodeId: job.episodeId,
        appSupportDirectory: _appSupportDirectory,
      );
      final bool chineseCoverageOk = zhHits * 2 >= total && zhHits > 0;
      if (chineseCoverageOk && !trustedZh) {
        // This job just produced dense ZH — stamp v3 so the queue can settle.
        await markHardsubChineseFromTranslation(
          episodeId: job.episodeId,
          appSupportDirectory: _appSupportDirectory,
        );
      }
      needEnglish = enHits * 2 < total;
      needChinese = !chineseCoverageOk;
    }
    // Official softsubs count as satisfied (player prefers them when present).
    if (needEnglish &&
        await _officialEnglishCoversEpisode(
          job.enPath ??
              await existingOfficialBilibiliSubtitle(
                idKey: job.sourceKey,
                fileName: 'en.srt',
              ),
        )) {
      needEnglish = false;
    }
    if (needChinese) {
      final List<PlayerSubtitleLine> enTimeline =
          asrBundle?.sentenceLines
              .where((PlayerSubtitleLine line) => looksEnglish(line.english))
              .toList(growable: false) ??
          const <PlayerSubtitleLine>[];
      final String? zhPath =
          job.zhPath ??
          await existingOfficialBilibiliSubtitle(
            idKey: job.sourceKey,
            fileName: 'zh.srt',
          );
      // Official softsub file is enough — do not require ASR-timeline overlap.
      if (await _officialChineseCoversEpisode(zhPath) ||
          (enTimeline.isNotEmpty &&
              await _officialChineseCoversEnglishTimeline(
                zhPath,
                englishLines: enTimeline,
              ))) {
        needChinese = false;
      }
    }
    if (!needEnglish && !needChinese) {
      return null;
    }
    return (needEnglish: needEnglish, needChinese: needChinese);
  }

  Future<bool> _officialEnglishCoversEpisode(String? path) async {
    final String? trimmed = isUsableSubtitlePath(path) ? path!.trim() : null;
    if (trimmed == null) {
      return false;
    }
    try {
      final File file = File(trimmed);
      if (!file.existsSync() || file.lengthSync() < 16) {
        return false;
      }
      final List<PlayerSubtitleLine> lines = await loadSubtitleLines(trimmed);
      if (lines.isEmpty) {
        return false;
      }
      int hits = 0;
      for (final PlayerSubtitleLine line in lines) {
        final String primary = line.english.trim().isNotEmpty
            ? line.english
            : line.chinese;
        if (looksEnglish(primary) && !looksChinese(primary)) {
          hits += 1;
        }
      }
      return hits * 2 >= lines.length;
    } catch (_) {
      return false;
    }
  }

  Future<void> _runJob({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    // Official softsubs win: network-fetch / rediscover before any Whisper work.
    onProgress?.call(job.episodeId, '正在检查官方软字幕…');
    final OfficialSoftsubs soft = await ensureOfficialSoftsubs(
      sourceUrl: null,
      sourceKey: job.sourceKey,
      bilibiliCookieHeader: settings.resolvedBilibiliCookieHeader,
      existingEnPath: job.enPath,
      existingZhPath: job.zhPath,
      // Jobs often lack a watch URL; disk + cookieed refetch by key still
      // happens inside ensure when sourceUrl is empty via existing files.
      // When sourceKey alone is set, try a BV watch URL for network pull.
      networkFetch: false,
    );
    OfficialSoftsubs resolved = soft;
    if ((!soft.hasEnglish && job.needEnglish) ||
        (!soft.hasChinese && job.needChinese)) {
      final String? watch = _watchUrlFromSourceKey(job.sourceKey);
      if (watch != null) {
        resolved = await ensureOfficialSoftsubs(
          sourceUrl: watch,
          sourceKey: job.sourceKey,
          bilibiliCookieHeader: settings.resolvedBilibiliCookieHeader,
          existingEnPath: soft.enPath,
          existingZhPath: soft.zhPath,
          networkFetch: true,
        );
      }
    }
    final String? officialEn = resolved.enPath;
    final String? officialZh = resolved.zhPath;
    final SubtitleCompletionJob linked = job.copyWith(
      enPath: officialEn ?? job.enPath,
      zhPath: officialZh ?? job.zhPath,
    );
    final bool hasOfficialEn = await _officialEnglishCoversEpisode(officialEn);
    final bool hasOfficialZh = await _officialChineseCoversEpisode(officialZh);
    bool needEnglish = linked.needEnglish && !hasOfficialEn;
    bool needChinese = linked.needChinese && (!hasOfficialZh || needEnglish);
    if (!needEnglish && !needChinese) {
      onProgress?.call(job.episodeId, '官方软字幕已就绪');
      final String en = (officialEn ?? '').trim();
      final String zh = (officialZh ?? '').trim();
      if (en.isNotEmpty || zh.isNotEmpty) {
        final SubtitleCompletionPersistedHook? hook = onPersisted;
        if (hook != null) {
          await hook(
            episodeId: job.episodeId,
            englishPath: en.isNotEmpty ? en : (linked.enPath ?? ''),
            chinesePath: zh.isNotEmpty ? zh : (linked.zhPath ?? ''),
          );
        }
      }
      return;
    }

    final String asrPrimary = linked.asrPrimary.trim().toLowerCase();
    if (asrPrimary.startsWith('zh')) {
      await _runAsrChineseThenMaybeEnglish(
        job: linked.copyWith(
          needEnglish: needEnglish,
          needChinese: needChinese || needEnglish,
        ),
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      return;
    }
    if (asrPrimary == 'auto' || asrPrimary == 'mixed') {
      await _runAsrMixedBilingual(
        job: linked.copyWith(
          needEnglish: needEnglish || needChinese,
          needChinese: needEnglish || needChinese,
        ),
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      return;
    }

    // If speech/official English already exists, Chinese is EN→ZH only.
    if (needChinese && !needEnglish) {
      await _runChineseFillOnly(
        job: linked.copyWith(needEnglish: false, needChinese: true),
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      return;
    }
    if (needChinese) {
      final MergedSubtitleBundle? existing = await loadAsrSentenceSubtitles(
        episodeId: job.episodeId,
        sourceKey: job.sourceKey,
        videoFingerprint: videoFileFingerprint(job.videoPath),
        appSupportDirectory: _appSupportDirectory,
      );
      final int enHits =
          existing?.sentences
              .where((SubtitleSentence s) => looksEnglish(s.english))
              .length ??
          0;
      final int total = existing?.sentences.length ?? 0;
      if (total > 0 && enHits * 2 >= total) {
        await _runChineseFillOnly(
          job: linked.copyWith(needEnglish: false, needChinese: true),
          settings: settings,
          onProgress: onProgress,
          cancellationToken: cancellationToken,
        );
        return;
      }
    }

    // English missing → ASR English (never ZH→EN). Official EN already gated.
    // Then EN→ZH when Chinese is also needed and official ZH is absent.
    if (needEnglish) {
      await _runAsrEnglishThenMaybeChinese(
        job: linked.copyWith(needEnglish: true, needChinese: needChinese),
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
      return;
    }
    if (needChinese) {
      await _runChineseFillOnly(
        job: linked.copyWith(needEnglish: false, needChinese: true),
        settings: settings,
        onProgress: onProgress,
        cancellationToken: cancellationToken,
      );
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
    final _ExternalFillLines? external = await _tryExternalFillLines(
      job: job,
      settings: settings,
      onProgress: onProgress,
      cancellationToken: cancellationToken,
    );
    cancellationToken?.throwIfCancelled();

    late final List<PlayerSubtitleLine> asrLines;
    if (external != null && external.english.isNotEmpty) {
      asrLines = external.english;
    } else {
      final String raw = await asrRunner.run(
        episodeId: job.episodeId,
        videoPath: job.videoPath,
        settings: settings,
        referenceSubtitleLines: const <PlayerSubtitleLine>[],
        referenceSignatureOverride: 'pipeline=hear_video_en',
        forceRegenerate: true,
        jobPipeline: 'hear_video_en',
        language: 'en',
        cancellationToken: cancellationToken,
        onProgress: (AsrSubtitleProgress progress) {
          onProgress?.call(job.episodeId, progress.label);
        },
      );
      cancellationToken?.throwIfCancelled();
      asrLines = parseSubtitleLines(raw);
    }
    // Keep any existing Chinese under the new ASR English timeline.
    // Never auto-clear Chinese — only manual「重新识别中文」may wipe it.
    final MergedSubtitleBundle? prior = await loadAsrSentenceSubtitles(
      episodeId: job.episodeId,
      sourceKey: job.sourceKey,
      videoFingerprint: videoFileFingerprint(job.videoPath),
      appSupportDirectory: _appSupportDirectory,
    );
    final List<PlayerSubtitleLine> keptChinese = prior == null
        ? const <PlayerSubtitleLine>[]
        : prior.sentenceLines
              .where((PlayerSubtitleLine line) => looksChinese(line.chinese))
              .map(
                (PlayerSubtitleLine line) => PlayerSubtitleLine(
                  startTime: line.startTime,
                  english: '',
                  chinese: line.chinese,
                  startMs: line.startMs,
                  endMs: line.endMs,
                ),
              )
              .toList(growable: false);

    MergedSubtitleBundle bundle = mergeAsrIntoSentences(
      asrLines: asrLines,
      chineseLines: keptChinese,
    );
    if (bundle.sentences.isEmpty) {
      throw StateError('语音识别未产出可用英文字幕');
    }

    int translatedChineseCount = 0;
    final int total = bundle.sentences.length;
    final int zhHits = bundle.sentences
        .where((SubtitleSentence s) => looksChinese(s.chinese))
        .length;
    final bool chineseCoverageOk = total > 0 && zhHits * 2 >= total;
    final bool anyChineseMissing = bundle.sentences.any(
      (SubtitleSentence s) =>
          looksEnglish(s.english) && !looksChinese(s.chinese),
    );
    if (chineseCoverageOk && !anyChineseMissing) {
      onProgress?.call(job.episodeId, '中文字幕已就绪');
    } else if (job.needChinese || anyChineseMissing) {
      // Prefer official ZH only when it actually covers this English timeline.
      // A short/dirty zh.srt that is "100% Chinese" by itself must not skip
      // EN→ZH — that was failing episode 2+ after a longer ASR English track.
      final String? officialZh = isUsableSubtitlePath(job.zhPath)
          ? job.zhPath
          : await existingOfficialBilibiliSubtitle(
              idKey: job.sourceKey,
              fileName: 'zh.srt',
            );
      if (await _officialChineseCoversEnglishTimeline(
        officialZh,
        englishLines: bundle.sentenceLines,
      )) {
        onProgress?.call(job.episodeId, '中文字幕已就绪（官方软字幕）');
        translatedChineseCount = 0;
      } else {
        onProgress?.call(job.episodeId, '正在翻译中文字幕…');
        // Only translate missing sides — do not wipe kept Chinese.
        final ({MergedSubtitleBundle bundle, int translatedCount}) filled =
            await _fillBundleChinese(
              bundle: bundle,
              settings: settings,
              cancellationToken: cancellationToken,
            );
        bundle = filled.bundle;
        translatedChineseCount = filled.translatedCount;
      }
    }

    final PersistedBilingualSubtitleFiles? files =
        await persistAsrSentenceSubtitles(
          episodeId: job.episodeId,
          bundle: bundle,
          sourceKey: job.sourceKey,
          videoFingerprint: videoFileFingerprint(job.videoPath),
          appSupportDirectory: _appSupportDirectory,
        );
    if (files == null) {
      throw StateError('字幕保存失败');
    }
    // Only mark trusted EN→ZH — never when leftover softsub ZH was already there.
    if (translatedChineseCount > 0) {
      await markHardsubChineseFromTranslation(
        episodeId: job.episodeId,
        appSupportDirectory: _appSupportDirectory,
      );
    }
    await _notifyPersisted(job.episodeId, files);
  }

  Future<void> _runAsrChineseThenMaybeEnglish({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    if (!isUsableLocalVideoPath(job.videoPath)) {
      throw StateError('本地视频不可用，无法语音识别');
    }
    if (LocalWhisperAsr.isLocalProvider(settings) &&
        !settings.enableChineseSpeechAsr) {
      throw StateError('未开启中文语音识别。请到「设置 → AI生成字幕」开启，并下载多语言 Whisper 模型。');
    }

    onProgress?.call(job.episodeId, '正在用语音生成中文字幕…');
    final String raw = await asrRunner.run(
      episodeId: job.episodeId,
      videoPath: job.videoPath,
      settings: settings,
      referenceSubtitleLines: const <PlayerSubtitleLine>[],
      referenceSignatureOverride: 'pipeline=hear_video_zh',
      forceRegenerate: true,
      jobPipeline: 'hear_video_zh',
      language: 'zh',
      cancellationToken: cancellationToken,
      onProgress: (AsrSubtitleProgress progress) {
        onProgress?.call(job.episodeId, progress.label);
      },
    );
    cancellationToken?.throwIfCancelled();
    final List<PlayerSubtitleLine> asrLines = parseSubtitleLines(raw);
    final List<PlayerSubtitleLine> chineseLines = asrLines
        .map((PlayerSubtitleLine line) {
          final String zh = looksChinese(line.chinese)
              ? line.chinese
              : (looksChinese(line.english) ? line.english : '');
          return PlayerSubtitleLine(
            startTime: line.startTime,
            english: '',
            chinese: zh,
            startMs: line.startMs,
            endMs: line.endMs,
            words: line.words,
          );
        })
        .where(
          (PlayerSubtitleLine line) =>
              line.endMs > line.startMs && looksChinese(line.chinese),
        )
        .toList(growable: false);
    if (chineseLines.isEmpty) {
      throw StateError('语音识别未产出可用中文字幕');
    }

    MergedSubtitleBundle bundle = MergedSubtitleBundle(
      sentences: chineseLines
          .map(
            (PlayerSubtitleLine line) => SubtitleSentence(
              startMs: line.startMs,
              endMs: line.endMs,
              english: '',
              chinese: line.chinese,
              fragmentStartMs: <int>[line.startMs],
              fragmentEndMs: <int>[line.endMs],
            ),
          )
          .toList(growable: false),
      fragments: chineseLines
          .map(
            (PlayerSubtitleLine line) => SubtitleFragment(
              startMs: line.startMs,
              endMs: line.endMs,
              english: '',
              chinese: line.chinese,
            ),
          )
          .toList(growable: false),
    );

    // Translate to English only after speech-aligned Chinese exists.
    final bool anyEnglishMissing = bundle.sentences.any(
      (SubtitleSentence s) =>
          looksChinese(s.chinese) && !looksEnglish(s.english),
    );
    if (job.needEnglish || anyEnglishMissing) {
      onProgress?.call(job.episodeId, '正在翻译英文字幕…');
      bundle = await _fillBundleEnglish(
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
          videoFingerprint: videoFileFingerprint(job.videoPath),
          appSupportDirectory: _appSupportDirectory,
        );
    if (files == null) {
      throw StateError('字幕保存失败');
    }
    await _notifyPersisted(job.episodeId, files);
  }

  /// Multilingual Whisper with language=auto for Chinese-English mixed teaching.
  Future<void> _runAsrMixedBilingual({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    if (!isUsableLocalVideoPath(job.videoPath)) {
      throw StateError('本地视频不可用，无法语音识别');
    }
    if (LocalWhisperAsr.isLocalProvider(settings) &&
        !settings.enableChineseSpeechAsr) {
      throw StateError('未开启中文语音识别。请到「设置 → AI生成字幕」开启，并下载多语言 Whisper 模型。');
    }

    onProgress?.call(job.episodeId, '正在识别中英混合口播…');
    final String raw = await asrRunner.run(
      episodeId: job.episodeId,
      videoPath: job.videoPath,
      settings: settings,
      referenceSubtitleLines: const <PlayerSubtitleLine>[],
      referenceSignatureOverride: 'pipeline=hear_video_auto',
      forceRegenerate: true,
      jobPipeline: 'hear_video_auto',
      language: 'auto',
      cancellationToken: cancellationToken,
      onProgress: (AsrSubtitleProgress progress) {
        onProgress?.call(job.episodeId, progress.label);
      },
    );
    cancellationToken?.throwIfCancelled();
    final List<PlayerSubtitleLine> asrLines = parseSubtitleLines(raw);
    if (asrLines.isEmpty) {
      throw StateError('语音识别未产出可用字幕');
    }

    MergedSubtitleBundle bundle = mergeAsrIntoSentences(
      asrLines: asrLines
          .where((PlayerSubtitleLine line) => looksEnglish(line.english))
          .toList(growable: false),
      chineseLines: asrLines
          .where((PlayerSubtitleLine line) => looksChinese(line.chinese))
          .map(
            (PlayerSubtitleLine line) => PlayerSubtitleLine(
              startTime: line.startTime,
              english: '',
              chinese: line.chinese,
              startMs: line.startMs,
              endMs: line.endMs,
              words: line.words,
            ),
          )
          .toList(growable: false),
    );
    // Segments that landed only on one side still become sentences.
    if (bundle.sentences.isEmpty) {
      bundle = MergedSubtitleBundle(
        sentences: asrLines
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
            .where(
              (SubtitleSentence s) =>
                  looksEnglish(s.english) || looksChinese(s.chinese),
            )
            .toList(growable: false),
        fragments: asrLines
            .map(
              (PlayerSubtitleLine line) => SubtitleFragment(
                startMs: line.startMs,
                endMs: line.endMs,
                english: line.english,
                chinese: line.chinese,
              ),
            )
            .where(
              (SubtitleFragment f) =>
                  looksEnglish(f.english) || looksChinese(f.chinese),
            )
            .toList(growable: false),
      );
    }
    if (bundle.sentences.isEmpty) {
      throw StateError('语音识别未产出可用字幕');
    }

    final bool anyChineseMissing = bundle.sentences.any(
      (SubtitleSentence s) =>
          looksEnglish(s.english) && !looksChinese(s.chinese),
    );
    final bool anyEnglishMissing = bundle.sentences.any(
      (SubtitleSentence s) =>
          looksChinese(s.chinese) && !looksEnglish(s.english),
    );
    int translatedChineseCount = 0;
    if (job.needChinese && anyChineseMissing) {
      onProgress?.call(job.episodeId, '正在补译中文字幕…');
      final ({MergedSubtitleBundle bundle, int translatedCount}) filled =
          await _fillBundleChinese(
            bundle: bundle,
            settings: settings,
            cancellationToken: cancellationToken,
          );
      bundle = filled.bundle;
      translatedChineseCount = filled.translatedCount;
    }
    if (job.needEnglish && anyEnglishMissing) {
      onProgress?.call(job.episodeId, '正在补译英文字幕…');
      bundle = await _fillBundleEnglish(
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
          videoFingerprint: videoFileFingerprint(job.videoPath),
          appSupportDirectory: _appSupportDirectory,
        );
    if (files == null) {
      throw StateError('字幕保存失败');
    }
    if (translatedChineseCount > 0) {
      await markHardsubChineseFromTranslation(
        episodeId: job.episodeId,
        appSupportDirectory: _appSupportDirectory,
      );
    }
    await _notifyPersisted(job.episodeId, files);
  }

  Future<void> _runChineseFillOnly({
    required SubtitleCompletionJob job,
    required LearningSettingsState settings,
    SubtitleCompletionProgress? onProgress,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    // Prefer speech-aligned ASR sentences (hardsub strip leaves EN here).
    MergedSubtitleBundle? existingAsr = await loadAsrSentenceSubtitles(
      episodeId: job.episodeId,
      sourceKey: job.sourceKey,
      videoFingerprint: videoFileFingerprint(job.videoPath),
      appSupportDirectory: _appSupportDirectory,
    );
    // Official ZH softsub on disk is authoritative — never wipe / retranslate.
    final String? officialZhEarly = isUsableSubtitlePath(job.zhPath)
        ? job.zhPath
        : await existingOfficialBilibiliSubtitle(
            idKey: job.sourceKey,
            fileName: 'zh.srt',
          );
    if (await _officialChineseCoversEpisode(officialZhEarly)) {
      onProgress?.call(job.episodeId, '中文字幕已就绪（官方软字幕）');
      return;
    }

    if (existingAsr != null && existingAsr.sentences.isNotEmpty) {
      final int total = existingAsr.sentences.length;
      final int zhHits = existingAsr.sentences
          .where((SubtitleSentence s) => looksChinese(s.chinese))
          .length;
      if (total > 0 && zhHits * 2 >= total) {
        // Keep existing Chinese (official merge or prior fill). Never auto-wipe
        // to EN→ZH — user regenerates via「重新识别中文」if wrong.
        onProgress?.call(job.episodeId, '中文字幕已就绪');
        return;
      }
    }
    onProgress?.call(job.episodeId, '正在翻译中文字幕…');

    List<PlayerSubtitleLine> withEnglish = const <PlayerSubtitleLine>[];
    MergedSubtitleBundle? baseBundle;
    if (existingAsr != null && existingAsr.sentences.isNotEmpty) {
      // Only fill blank Chinese sides — do not clear existing text.
      baseBundle = existingAsr;
      withEnglish = baseBundle.sentenceLines
          .where((PlayerSubtitleLine line) => looksEnglish(line.english))
          .toList(growable: false);
    }

    if (withEnglish.isEmpty) {
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
      final List<PlayerSubtitleLine> englishLines = await loadSubtitleLines(
        enPath!,
      );
      withEnglish = englishLines
          .where((PlayerSubtitleLine line) => looksEnglish(line.english))
          .map(
            (PlayerSubtitleLine line) => PlayerSubtitleLine(
              startTime: line.startTime,
              english: line.english,
              chinese: '',
              startMs: line.startMs,
              endMs: line.endMs,
              words: line.words,
            ),
          )
          .toList(growable: false);
    }
    if (withEnglish.isEmpty) {
      throw StateError('英文字幕为空，无法翻译中文');
    }

    // Official ZH softsub already on disk → skip EN→ZH.
    final String? officialZh = isUsableSubtitlePath(job.zhPath)
        ? job.zhPath
        : await existingOfficialBilibiliSubtitle(
            idKey: job.sourceKey,
            fileName: 'zh.srt',
          );
    if (await _officialChineseCoversEpisode(officialZh) ||
        await _officialChineseCoversEnglishTimeline(
          officialZh,
          englishLines: withEnglish,
        )) {
      onProgress?.call(job.episodeId, '中文字幕已就绪（官方软字幕）');
      return;
    }

    final ({List<PlayerSubtitleLine> lines, int translatedCount}) filled =
        await _fillLinesChinese(
          lines: withEnglish,
          settings: settings,
          cancellationToken: cancellationToken,
          onProgress: onProgress,
          episodeId: job.episodeId,
        );
    final List<PlayerSubtitleLine> bilingual = filled.lines;

    // Map translations back by startMs — withEnglish may be a filtered subset.
    final Map<int, String> zhByStart = <int, String>{
      for (final PlayerSubtitleLine line in bilingual)
        if (looksChinese(line.chinese)) line.startMs: line.chinese,
    };
    final MergedSubtitleBundle bundle = baseBundle == null
        ? MergedSubtitleBundle(
            sentences: bilingual
                .map(
                  (PlayerSubtitleLine line) => SubtitleSentence(
                    startMs: line.startMs,
                    endMs: line.endMs,
                    english: line.english,
                    chinese: line.chinese,
                    fragmentStartMs: <int>[line.startMs],
                    fragmentEndMs: <int>[line.endMs],
                    words: line.words,
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
          )
        : MergedSubtitleBundle(
            sentences: <SubtitleSentence>[
              for (final SubtitleSentence sentence in baseBundle.sentences)
                SubtitleSentence(
                  startMs: sentence.startMs,
                  endMs: sentence.endMs,
                  english: sentence.english,
                  // Keep prior Chinese when this cue was not in the EN→ZH set
                  // (e.g. Chinese-only rows) — never blank the whole track.
                  chinese:
                      zhByStart[sentence.startMs] ??
                      (looksChinese(sentence.chinese) ? sentence.chinese : ''),
                  fragmentStartMs: sentence.fragmentStartMs,
                  fragmentEndMs: sentence.fragmentEndMs,
                  words: sentence.words,
                ),
            ],
            fragments: baseBundle.fragments,
          );

    final PersistedBilingualSubtitleFiles? files =
        await persistAsrSentenceSubtitles(
          episodeId: job.episodeId,
          bundle: bundle,
          sourceKey: job.sourceKey,
          videoFingerprint: videoFileFingerprint(job.videoPath),
          origin: enTranslationOrigin,
          appSupportDirectory: _appSupportDirectory,
        );
    if (files == null) {
      throw StateError('字幕保存失败');
    }
    if (filled.translatedCount > 0) {
      await markHardsubChineseFromTranslation(
        episodeId: job.episodeId,
        appSupportDirectory: _appSupportDirectory,
      );
    }
    await _notifyPersisted(job.episodeId, files);
  }

  Future<bool> _officialChineseCoversEpisode(String? path) async {
    final String? trimmed = isUsableSubtitlePath(path) ? path!.trim() : null;
    if (trimmed == null) {
      return false;
    }
    try {
      final File file = File(trimmed);
      if (!file.existsSync() || file.lengthSync() < 16) {
        return false;
      }
      final List<PlayerSubtitleLine> lines = await loadSubtitleLines(trimmed);
      if (lines.isEmpty) {
        return false;
      }
      int hits = 0;
      for (final PlayerSubtitleLine line in lines) {
        final String primary = line.chinese.trim().isNotEmpty
            ? line.chinese
            : line.english;
        if (looksChinese(primary)) {
          hits += 1;
        }
      }
      return hits * 2 >= lines.length;
    } catch (_) {
      return false;
    }
  }

  /// True when official ZH cues overlap ≥ half of the English timeline cues.
  ///
  /// Unlike [_officialChineseCoversEpisode], a 1-cue dirty zh.srt cannot
  /// satisfy a multi-minute English ASR track.
  Future<bool> _officialChineseCoversEnglishTimeline(
    String? path, {
    required List<PlayerSubtitleLine> englishLines,
  }) async {
    final List<PlayerSubtitleLine> english = englishLines
        .where((PlayerSubtitleLine line) => looksEnglish(line.english))
        .toList(growable: false);
    if (english.isEmpty) {
      return _officialChineseCoversEpisode(path);
    }
    final String? trimmed = isUsableSubtitlePath(path) ? path!.trim() : null;
    if (trimmed == null) {
      return false;
    }
    try {
      final List<PlayerSubtitleLine> zhLines = await loadSubtitleLines(trimmed);
      final List<PlayerSubtitleLine> chinese = zhLines
          .where((PlayerSubtitleLine line) {
            final String primary = line.chinese.trim().isNotEmpty
                ? line.chinese
                : line.english;
            return looksChinese(primary) && line.endMs > line.startMs;
          })
          .toList(growable: false);
      if (chinese.isEmpty) {
        return false;
      }
      int covered = 0;
      int enEndMs = 0;
      int zhEndMs = 0;
      for (final PlayerSubtitleLine en in english) {
        if (en.endMs > enEndMs) {
          enEndMs = en.endMs;
        }
        final bool hit = chinese.any((PlayerSubtitleLine zh) {
          if (zh.endMs > zhEndMs) {
            zhEndMs = zh.endMs;
          }
          final int overlapStart = en.startMs > zh.startMs
              ? en.startMs
              : zh.startMs;
          final int overlapEnd = en.endMs < zh.endMs ? en.endMs : zh.endMs;
          return overlapEnd > overlapStart;
        });
        if (hit) {
          covered += 1;
        }
      }
      for (final PlayerSubtitleLine zh in chinese) {
        if (zh.endMs > zhEndMs) {
          zhEndMs = zh.endMs;
        }
      }
      // Cue overlap alone is too weak for 2-cue tracks (1/2 == 50%).
      // Also require Chinese to reach ~half the English end time.
      final bool cueOk = covered * 2 >= english.length;
      final bool durationOk = enEndMs <= 0 || zhEndMs * 2 >= enEndMs;
      return cueOk && durationOk;
    } catch (_) {
      return false;
    }
  }

  Future<_ExternalFillLines?> _tryExternalFillLines({
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
      final List<PlayerSubtitleLine> english = await loadSubtitleLines(enPath);
      List<PlayerSubtitleLine> chinese = const <PlayerSubtitleLine>[];
      final String? zhPath = filled?.zhPath;
      if (zhPath != null && File(zhPath).existsSync()) {
        try {
          chinese = normalizeChineseOnlySubtitleLines(
            await loadSubtitleLines(zhPath),
          );
        } catch (_) {}
      }
      return _ExternalFillLines(english: english, chinese: chinese);
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

  Future<({MergedSubtitleBundle bundle, int translatedCount})>
  _fillBundleChinese({
    required MergedSubtitleBundle bundle,
    required LearningSettingsState settings,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final ({List<PlayerSubtitleLine> lines, int translatedCount}) filled =
        await _fillLinesChinese(
          lines: bundle.sentenceLines,
          settings: settings,
          cancellationToken: cancellationToken,
        );
    final Map<int, PlayerSubtitleLine> byStart = <int, PlayerSubtitleLine>{
      for (final PlayerSubtitleLine line in filled.lines) line.startMs: line,
    };
    final List<SubtitleSentence> sentences = <SubtitleSentence>[];
    for (final SubtitleSentence original in bundle.sentences) {
      final PlayerSubtitleLine? line = byStart[original.startMs];
      sentences.add(
        SubtitleSentence(
          startMs: original.startMs,
          endMs: original.endMs,
          english: original.english,
          chinese: line != null && looksChinese(line.chinese)
              ? line.chinese
              : original.chinese,
          fragmentStartMs: original.fragmentStartMs,
          fragmentEndMs: original.fragmentEndMs,
          words: original.words.isNotEmpty
              ? original.words
              : (line?.words ?? const <PlayerSubtitleWord>[]),
        ),
      );
    }
    return (
      bundle: MergedSubtitleBundle(
        sentences: sentences,
        fragments: bundle.fragments,
      ),
      translatedCount: filled.translatedCount,
    );
  }

  Future<MergedSubtitleBundle> _fillBundleEnglish({
    required MergedSubtitleBundle bundle,
    required LearningSettingsState settings,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final List<PlayerSubtitleLine> filled = await _fillLinesEnglish(
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
          english: looksEnglish(line.english) ? line.english : original.english,
          chinese: original.chinese,
          fragmentStartMs: original.fragmentStartMs,
          fragmentEndMs: original.fragmentEndMs,
          words: original.words.isNotEmpty ? original.words : line.words,
        ),
      );
    }
    return MergedSubtitleBundle(
      sentences: sentences,
      fragments: bundle.fragments,
    );
  }

  // Keep batches tiny — slow mobile networks time out on 40-line AI payloads
  // (device log: 中文翻译超时（40 句）). Marker: zh_batch_v184_size8
  static const int _zhBatchLines = 8;
  static const int _zhBatchCharacters = 1200;

  Future<({List<PlayerSubtitleLine> lines, int translatedCount})>
  _fillLinesChinese({
    required List<PlayerSubtitleLine> lines,
    required LearningSettingsState settings,
    AsrSubtitleCancellationToken? cancellationToken,
    SubtitleCompletionProgress? onProgress,
    String? episodeId,
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
      return (lines: lines, translatedCount: 0);
    }

    final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(lines);
    final int priorChinese = lines
        .where((PlayerSubtitleLine line) => looksChinese(line.chinese))
        .length;
    int translatedCount = 0;
    int offset = 0;
    int emptyStreak = 0;
    while (offset < pendingSentences.length) {
      cancellationToken?.throwIfCancelled();
      int end = offset;
      int characters = 0;
      while (end < pendingSentences.length && end - offset < _zhBatchLines) {
        final int length = pendingSentences[end].length;
        if (end > offset && characters + length > _zhBatchCharacters) {
          break;
        }
        characters += length;
        end += 1;
      }
      final List<String> batch = pendingSentences.sublist(offset, end);
      if (onProgress != null && episodeId != null) {
        onProgress(
          episodeId,
          '正在翻译中文字幕… ${offset + 1}-$end/${pendingSentences.length}',
        );
      }
      // Never abort the whole episode on one slow batch (old bug: 40-句超时).
      final List<String> translated = await _translateChineseBatch(
        batch: batch,
        settings: settings,
      );
      int batchHits = 0;
      for (int i = 0; i < batch.length; i++) {
        cancellationToken?.throwIfCancelled();
        final String zh = i < translated.length ? translated[i].trim() : '';
        if (zh.isEmpty || !looksChinese(zh)) {
          continue;
        }
        final int index = pendingIndexes[offset + i];
        final PlayerSubtitleLine line = next[index];
        next[index] = PlayerSubtitleLine(
          startTime: line.startTime,
          english: line.english,
          chinese: zh,
          startMs: line.startMs,
          endMs: line.endMs,
          words: line.words,
        );
        translatedCount += 1;
        batchHits += 1;
      }
      offset = end;
      if (batchHits == 0) {
        emptyStreak += 1;
        // Free APIs often rate-limit after ~50–80 cues. Keep what we have and
        // let the queue continue later instead of failing the episode.
        if ((translatedCount > 0 || priorChinese > 0) && emptyStreak >= 2) {
          break;
        }
        await Future<void>.delayed(
          Duration(milliseconds: 600 * emptyStreak.clamp(1, 5)),
        );
      } else {
        emptyStreak = 0;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    if (translatedCount == 0) {
      // Hole-fill pass got nothing new — soft-fail if we already have Chinese.
      if (priorChinese > 0) {
        return (lines: lines, translatedCount: 0);
      }
      throw StateError(
        '中文翻译未返回可用结果（网络过慢或翻译 API 不可用）。'
        '请检查网络后点重试，或到「设置 → 翻译」配置可用 API。',
      );
    }
    return (lines: next, translatedCount: translatedCount);
  }

  /// Prefer GPU-box Ollama (qwen2.5) first; free MT only fills holes / offline.
  /// Never throw — empty slots stay for a later retry.
  Future<List<String>> _translateChineseBatch({
    required List<String> batch,
    required LearningSettingsState settings,
  }) async {
    if (batch.isEmpty) {
      return const <String>[];
    }
    final List<String> out = List<String>.filled(batch.length, '');

    Future<void> merge(List<String> translated) async {
      if (translated.length != batch.length) {
        return;
      }
      for (int i = 0; i < batch.length; i++) {
        if (looksChinese(out[i])) {
          continue;
        }
        final String zh = translated[i].trim();
        if (looksChinese(zh)) {
          out[i] = zh;
        }
      }
    }

    // 1) Local Ollama / configured AI on 5060 Ti — primary EN→ZH path.
    try {
      final List<String> translated;
      if (translateChinese != null) {
        translated = await translateChinese!(
          sentences: batch,
          settings: settings,
        ).timeout(const Duration(seconds: 90));
      } else {
        translated = await const WordLookupService()
            .translateSentences(
              sentences: batch,
              settings: settings,
              targetLanguage: 'zh',
            )
            .timeout(const Duration(seconds: 90));
      }
      await merge(translated);
    } catch (_) {}

    final int aiHits = out.where(looksChinese).length;
    if (aiHits * 2 >= batch.length) {
      return out;
    }

    // 2) Free / Edge / MyMemory only for remaining holes (GPU unreachable).
    try {
      await merge(
        fallbackTranslateChinese != null
            ? await fallbackTranslateChinese!(
                sentences: batch,
                settings: settings,
              )
            : await const WordLookupService()
                  .translateSentencesFreeParallel(
                    sentences: batch,
                    toEnglish: false,
                    concurrency: 3,
                  )
                  .timeout(const Duration(seconds: 90)),
      );
    } catch (_) {}

    return out;
  }

  Future<List<PlayerSubtitleLine>> _fillLinesEnglish({
    required List<PlayerSubtitleLine> lines,
    required LearningSettingsState settings,
    AsrSubtitleCancellationToken? cancellationToken,
  }) async {
    final List<int> pendingIndexes = <int>[];
    final List<String> pendingSentences = <String>[];
    for (int i = 0; i < lines.length; i++) {
      final PlayerSubtitleLine line = lines[i];
      if (looksEnglish(line.english) && !looksChinese(line.english)) {
        continue;
      }
      final String chinese = line.chinese.trim().isNotEmpty
          ? line.chinese.trim()
          : line.english.trim();
      if (!looksChinese(chinese)) {
        continue;
      }
      pendingIndexes.add(i);
      pendingSentences.add(chinese);
    }
    if (pendingSentences.isEmpty) {
      return lines;
    }
    cancellationToken?.throwIfCancelled();

    final List<String> translated = await const WordLookupService()
        .translateSentences(
          sentences: pendingSentences,
          settings: settings,
          targetLanguage: 'en',
        );
    if (translated.length != pendingSentences.length) {
      throw StateError('英文翻译结果数量不匹配');
    }

    final List<PlayerSubtitleLine> next = List<PlayerSubtitleLine>.of(lines);
    for (int i = 0; i < pendingIndexes.length; i++) {
      cancellationToken?.throwIfCancelled();
      final int index = pendingIndexes[i];
      final String en = translated[i].trim();
      if (en.isEmpty || !looksEnglish(en)) {
        continue;
      }
      final PlayerSubtitleLine line = next[index];
      next[index] = PlayerSubtitleLine(
        startTime: line.startTime,
        english: en,
        chinese: looksChinese(line.chinese)
            ? line.chinese
            : pendingSentences[i],
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

  /// Rebuild a watch URL from `BV…` / `BV…-p02` / `av…` source keys.
  String? _watchUrlFromSourceKey(String? sourceKey) {
    final String key = (sourceKey ?? '').trim();
    if (key.isEmpty) {
      return null;
    }
    final RegExpMatch? pageMatch = RegExp(
      r'-p(\d{2,})$',
      caseSensitive: false,
    ).firstMatch(key);
    int page = 1;
    String root = key;
    if (pageMatch != null) {
      page = int.tryParse(pageMatch.group(1) ?? '') ?? 1;
      root = key.substring(0, pageMatch.start);
    }
    if (root.toUpperCase().startsWith('BV')) {
      // Keep original BV letter case for view/playurl.
      return BilibiliImport.watchUrl(bvid: root, page: page);
    }
    if (root.toLowerCase().startsWith('av')) {
      final String aid = root.toLowerCase().startsWith('av')
          ? root.substring(2)
          : root;
      return BilibiliImport.watchUrl(aid: aid, page: page);
    }
    return null;
  }
}

class _ExternalFillLines {
  const _ExternalFillLines({
    required this.english,
    this.chinese = const <PlayerSubtitleLine>[],
  });

  final List<PlayerSubtitleLine> english;
  final List<PlayerSubtitleLine> chinese;
}
