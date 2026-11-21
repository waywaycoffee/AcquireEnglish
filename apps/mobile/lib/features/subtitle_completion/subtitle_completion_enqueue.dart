import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/bilibili_multipage.dart';
import '../import_course/data/ensure_official_softsubs.dart';
import '../import_course/data/subtitle_source_policy.dart';
import '../library/presentation/library_mock_data.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/player_subtitle_loader.dart';
import '../player/presentation/subtitle_file_persist.dart';
import '../player/presentation/subtitle_sentence_merge.dart';
import '../sync/data/acquire_api_client.dart';
import 'shared_bilibili_subtitle_sync.dart';
import 'spoken_language.dart';
import 'subtitle_completion_background.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_runtime.dart';
import 'subtitle_completion_scheduler.dart';
import 'subtitle_completion_status_hub.dart';
import 'subtitle_fill_label.dart';

bool looksLikeScopedEpisodeSubtitle(String? path) {
  final String value = (path ?? '').trim();
  if (value.isEmpty) {
    return false;
  }
  return value.contains('episode_subtitles');
}

class SubtitleCompletionNeed {
  const SubtitleCompletionNeed({
    required this.needEnglish,
    required this.needChinese,
    this.needProofread = false,
  });

  final bool needEnglish;
  final bool needChinese;

  /// Official EN+ZH exist but speech has not verified them yet (ASR校对).
  final bool needProofread;

  bool get any => needEnglish || needChinese || needProofread;
}

/// Decide which sides still need filling for one episode.
///
/// Import-time rule: inspect English and Chinese together. Missing either side
/// enqueues ASR (EN) and/or EN→ZH fill so both land before study.
Future<SubtitleCompletionNeed> detectSubtitleCompletionNeed({
  required String episodeId,
  String? zhSubtitlePath,
  String? enSubtitlePath,
  String? sourceKey,
  String? videoPath,
  bool force = false,
  /// Hardsub English lessons: ignore B站 JSON ZH so fill goes ASR→translate.
  bool ignoreOfficialChinese = false,
  Future<Directory> Function()? appSupportDirectory,
}) async {
  if (force) {
    return const SubtitleCompletionNeed(
      needEnglish: true,
      needChinese: true,
      needProofread: true,
    );
  }

  final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
    episodeId: episodeId,
    sourceKey: sourceKey,
    videoFingerprint: videoFileFingerprint(videoPath),
    appSupportDirectory:
        appSupportDirectory ?? getApplicationSupportDirectory,
  );
  if (asrBundle != null && asrBundle.sentences.isNotEmpty) {
    final int total = asrBundle.sentences.length;
    final int enHits = asrBundle.sentences
        .where((SubtitleSentence s) => looksEnglish(s.english))
        .length;
    final int zhHits = asrBundle.sentences
        .where((SubtitleSentence s) => looksChinese(s.chinese))
        .length;
    // Sparse sides (< half of cues) still count as missing so import backfill
    // can finish the other language instead of stopping early.
    // Existing Chinese is never auto-cleared; only missing sides enqueue fill.
    bool needEnglish = enHits * 2 < total;
    bool needChinese = zhHits * 2 < total;
    // Official softsubs on disk still satisfy a side even when the ASR cache
    // is English-only / sparse ZH (player prefers official when present).
    if (needEnglish &&
        await _subtitleFileHasLanguage(
          enSubtitlePath,
          requireEnglish: true,
        )) {
      needEnglish = false;
    }
    if (needChinese && !ignoreOfficialChinese) {
      String? zhPath = isUsableSubtitlePath(zhSubtitlePath)
          ? zhSubtitlePath!.trim()
          : null;
      zhPath ??= await existingOfficialBilibiliSubtitle(
        idKey: sourceKey,
        fileName: 'zh.srt',
      );
      if (await _subtitleFileHasLanguage(zhPath, requireEnglish: false)) {
        needChinese = false;
      }
    }
    return SubtitleCompletionNeed(
      needEnglish: needEnglish,
      needChinese: needChinese,
    );
  }

  String? enPath = isUsableSubtitlePath(enSubtitlePath)
      ? enSubtitlePath!.trim()
      : null;
  // Prefer B站 Documents/bilibili/<id>/en.srt over scoped ASR cache paths.
  final String? officialEn = await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'en.srt',
  );
  if (isUsableSubtitlePath(officialEn)) {
    enPath = officialEn;
  } else if (enPath != null && looksLikeScopedEpisodeSubtitle(enPath)) {
    // ASR-scoped path alone is not "official"; still usable if English.
  }

  String? zhPath = ignoreOfficialChinese
      ? null
      : (isUsableSubtitlePath(zhSubtitlePath) ? zhSubtitlePath!.trim() : null);
  if (!ignoreOfficialChinese) {
    zhPath ??= await existingOfficialBilibiliSubtitle(
      idKey: sourceKey,
      fileName: 'zh.srt',
    );
  }
  // Paths may exist but be empty, unreadable, or the wrong language (e.g. a
  // Chinese CC saved as en.srt). Size + cue language must both pass.
  final bool hasReliableEn = await _subtitleFileHasLanguage(
    enPath,
    requireEnglish: true,
  );
  final bool hasZh =
      isUsableSubtitlePath(zhPath) &&
      await _subtitleFileHasLanguage(zhPath, requireEnglish: false);

  // Official softsubs are authoritative. Do not auto-ASR / "proofread" when
  // reliable EN (and/or ZH) already exists — user regenerates manually.
  return SubtitleCompletionNeed(
    needEnglish: !hasReliableEn,
    needChinese: !hasZh,
    needProofread: false,
  );
}

/// True when the SRT exists, is non-trivial, and ≥ half of cues match [lang].
Future<bool> _subtitleFileHasLanguage(
  String? path, {
  required bool requireEnglish,
}) async {
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
      final String primary = requireEnglish
          ? (line.english.trim().isNotEmpty ? line.english : line.chinese)
          : (line.chinese.trim().isNotEmpty ? line.chinese : line.english);
      if (requireEnglish) {
        if (looksEnglish(primary) && !looksChinese(primary)) {
          hits += 1;
        }
      } else if (looksChinese(primary)) {
        hits += 1;
      }
    }
    return hits * 2 >= lines.length;
  } catch (_) {
    return false;
  }
}

/// Missing-subtitle chip the user tapped on the course episode list.
enum SubtitleFillChip { english, chinese }

/// Plan which sides to fill and which language Whisper must ASR first.
({
  bool needEnglish,
  bool needChinese,
  SpokenLanguage asrPrimary,
}) planSubtitleFillOrder({
  required SubtitleCompletionNeed need,
  required SpokenLanguage spoken,
  SubtitleFillChip? chip,
}) {
  // needProofread is only set on explicit force/manual regenerate.
  bool needEn = need.needEnglish || need.needProofread;
  bool needZh = need.needChinese;
  if (chip == SubtitleFillChip.english) {
    needEn = true;
  } else if (chip == SubtitleFillChip.chinese) {
    needZh = true;
    // Tapping「补中文」must not re-run Whisper just because force/proofread
    // flipped needEnglish — that was burning attempts before EN→ZH ran.
    if (!need.needEnglish) {
      needEn = false;
    }
  }

  // Product rules:
  // - English-spoken: ASR English; Chinese via EN→ZH (or official ZH).
  // - Chinese-spoken: ASR Chinese (multilingual Whisper); English via ZH→EN.
  // - Mixed teaching: multilingual Whisper auto; split lines by script.
  // - Chinese chip with English already present → EN→ZH only (no Whisper).
  if (spoken == SpokenLanguage.mixed && (needEn || needZh)) {
    return (
      needEnglish: needEn || needZh,
      needChinese: needEn || needZh,
      asrPrimary: SpokenLanguage.mixed,
    );
  }
  if (spoken == SpokenLanguage.chinese && (needEn || needZh)) {
    // Prefer speech Chinese; translate the other side afterward.
    return (
      needEnglish: needEn,
      needChinese: needZh || needEn,
      asrPrimary: SpokenLanguage.chinese,
    );
  }
  if (needEn) {
    return (
      needEnglish: true,
      needChinese: needZh,
      asrPrimary: SpokenLanguage.english,
    );
  }
  if (needZh) {
    return (
      needEnglish: false,
      needChinese: true,
      asrPrimary: SpokenLanguage.english,
    );
  }
  return (
    needEnglish: false,
    needChinese: false,
    asrPrimary: spoken,
  );
}

/// Enqueue completion when English and/or Chinese is missing.
///
/// Order: official softsubs → shared cloud pack → cloud GPU generation →
/// local EN→ZH translate only when English is already present.
/// Tapping a missing-subtitle chip sets [chip] so that side is requested.
Future<void> enqueueSubtitleCompletionForEpisode({
  required String episodeId,
  required String? videoPath,
  String? zhSubtitlePath,
  String? enSubtitlePath,
  String? sourceUrl,
  String? title,
  String? description,
  LibraryCourseData? course,
  LibraryEpisodeItem? episode,
  SubtitleCompletionQueue? queue,
  bool force = false,
  SubtitleFillChip? chip,
  SpokenLanguage? forceSpokenLanguage,
  String? bilibiliCookieHeader,
  Future<Directory> Function()? appSupportDirectory,
  Future<Directory> Function()? documentsDirectory,
  AcquireApiClient? sharedSubtitleApi,
  bool skipSharedLookup = false,
  bool networkFetchOfficial = true,
}) async {
  final bool hasLocalVideo = isUsableLocalVideoPath(videoPath);

  final String? resolvedSource = sourceUrl ?? episode?.sourceUrl;
  final String? sourceKey = bilibiliEpisodeCacheKey(
    course: course,
    episode: episode,
    sourceUrl: resolvedSource,
    videoAsset: videoPath,
  );

  final SubtitleSourceDecision sourcePolicy =
      SubtitleSourcePolicy.decideEpisode(
        episode: episode,
        course: course,
        sourceUrl: resolvedSource,
        title: title ?? episode?.title,
        description: description ?? course?.description,
      );

  String? zhPath = isUsableSubtitlePath(zhSubtitlePath)
      ? zhSubtitlePath!.trim()
      : null;
  String? enPath = isUsableSubtitlePath(enSubtitlePath)
      ? enSubtitlePath!.trim()
      : null;

  // Prefer official softsubs (network + disk) before any ASR/translate job.
  if (!sourcePolicy.ignoreAllOfficialSoftsubs) {
    final OfficialSoftsubs soft = await ensureOfficialSoftsubs(
      sourceUrl: resolvedSource,
      sourceKey: sourceKey,
      bilibiliCookieHeader: bilibiliCookieHeader,
      existingEnPath: enPath,
      existingZhPath: sourcePolicy.ignoreOfficialChinese ? null : zhPath,
      networkFetch: networkFetchOfficial,
    );
    enPath = soft.enPath;
    if (sourcePolicy.ignoreOfficialChinese) {
      zhPath = null;
    } else {
      zhPath = soft.zhPath;
    }
  } else {
    // Duration-poisoned / forced wipe path only.
    zhPath = null;
    enPath = null;
  }

  // Shared community cache: after official softsubs, before cloud / local ASR.
  // Language-aware: a wrong-language file on disk still counts as missing so
  // cloud bilingual packs are pulled before Whisper/translate.
  bool usedSharedCache = false;
  BilibiliSharedSubtitleIds? sharedIds;
  final AcquireApiClient? sharedApi = resolveSharedBilibiliSubtitleApi(
    sharedSubtitleApi,
  );
  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  if (!force &&
      !skipSharedLookup &&
      sharedApi != null &&
      !sourcePolicy.ignoreAllOfficialSoftsubs) {
    final bool missingEn = !(await _subtitleFileHasLanguage(
      enPath,
      requireEnglish: true,
    ));
    final bool missingZh =
        !sourcePolicy.ignoreOfficialChinese &&
        !(await _subtitleFileHasLanguage(zhPath, requireEnglish: false));
    if (missingEn || missingZh) {
      sharedIds = resolveBilibiliSharedSubtitleIds(
        sourceKey: sourceKey,
        sourceUrl: sourceUrl ?? episode?.sourceUrl,
        course: course,
        episode: episode,
        videoAsset: videoPath,
      );
      if (sharedIds != null) {
        SubtitleCompletionStatusHub.instance.reportProgress(
          episodeId,
          kSubtitleSharedCacheLookupLabel,
          status: SubtitleCompletionStatus.running,
          needEnglish: missingEn,
          needChinese: missingZh,
        );
        final ({String? enPath, String? zhPath})? shared =
            await tryApplySharedBilibiliSubtitles(
              api: sharedApi,
              ids: sharedIds,
              documentsDirectory: documentsDirectory,
            );
        if (shared != null) {
          if (missingEn && isUsableSubtitlePath(shared.enPath)) {
            enPath = shared.enPath;
            usedSharedCache = true;
          }
          if (missingZh &&
              !sourcePolicy.ignoreOfficialChinese &&
              isUsableSubtitlePath(shared.zhPath)) {
            zhPath = shared.zhPath;
            usedSharedCache = true;
          }
          if (usedSharedCache) {
            SubtitleCompletionStatusHub.instance.reportSharedApplied(
              episodeId: episodeId,
              enPath: enPath,
              zhPath: zhPath,
            );
          }
        }
      }
    }
  }

  final SubtitleCompletionNeed detected = await detectSubtitleCompletionNeed(
    episodeId: episodeId,
    zhSubtitlePath: zhPath,
    enSubtitlePath: enPath,
    sourceKey: sourceKey,
    videoPath: videoPath,
    force: force,
    ignoreOfficialChinese:
        sourcePolicy.ignoreOfficialChinese ||
        sourcePolicy.ignoreAllOfficialSoftsubs,
    appSupportDirectory: appSupportDirectory,
  );
  if (!detected.any && chip == null) {
    // Full shared-cache hit: honest ready copy, never fake Whisper progress.
    if (usedSharedCache) {
      SubtitleCompletionStatusHub.instance.reportProgress(
        episodeId,
        kSubtitleSharedCacheReadyDetailLabel,
        status: SubtitleCompletionStatus.done,
        needEnglish: false,
        needChinese: false,
      );
      // Drop stuck ASR/translate jobs for this episode — cloud already has both.
      await store.markDone(episodeId);
    }
    return;
  }
  if (usedSharedCache) {
    SubtitleCompletionStatusHub.instance.reportProgress(
      episodeId,
      kSubtitleSharedCachePartialLabel,
      status: SubtitleCompletionStatus.running,
      needEnglish: detected.needEnglish || detected.needProofread,
      needChinese: detected.needChinese,
    );
  }

  final bool hasReliableEn =
      !detected.needEnglish &&
      !detected.needProofread &&
      isUsableSubtitlePath(enPath);
  final bool hasReliableZh =
      !detected.needChinese && isUsableSubtitlePath(zhPath);
  final SpokenLanguage spoken = inferSpokenLanguage(
    title: title,
    description: description,
    hasReliableEnglish: hasReliableEn,
    hasReliableChinese: hasReliableZh,
    force: forceSpokenLanguage,
  );
  final ({
    bool needEnglish,
    bool needChinese,
    SpokenLanguage asrPrimary,
  }) plan = planSubtitleFillOrder(
    need: detected,
    spoken: spoken,
    chip: chip,
  );
  if (!plan.needEnglish && !plan.needChinese) {
    return;
  }

  // Still missing after official + shared → push ECS GPU generation (Bilibili).
  // Prefer cloud over auto on-device Whisper; local remains for force / chip /
  // ZH-only translate / non-Bilibili / cloud submit failure.
  bool cloudQueued = false;
  final bool preferCloudAsr =
      !force &&
      chip == null &&
      plan.needEnglish &&
      !sourcePolicy.ignoreAllOfficialSoftsubs;
  if (preferCloudAsr && sharedApi != null) {
    sharedIds ??= resolveBilibiliSharedSubtitleIds(
      sourceKey: sourceKey,
      sourceUrl: sourceUrl ?? episode?.sourceUrl,
      course: course,
      episode: episode,
      videoAsset: videoPath,
    );
    if (sharedIds != null) {
      cloudQueued = await tryRequestCloudSubtitleGeneration(
        api: sharedApi,
        ids: sharedIds,
      );
      if (cloudQueued) {
        SubtitleCompletionStatusHub.instance.reportProgress(
          episodeId,
          kSubtitleCloudGenerationQueuedLabel,
          status: SubtitleCompletionStatus.running,
          needEnglish: plan.needEnglish,
          needChinese: plan.needChinese,
        );
        SubtitleCompletionStatusHub.instance.notifyChanged();
      }
    }
  }

  // No local media: cloud (or shared) is the only path — cannot Whisper.
  if (!hasLocalVideo) {
    return;
  }

  // Cloud accepted: wait for shared pack on a later scan; skip auto local ASR.
  if (cloudQueued && preferCloudAsr) {
    return;
  }

  await store.enqueue(
    episodeId: episodeId,
    videoPath: videoPath!.trim(),
    zhPath: zhPath,
    enPath: enPath,
    sourceKey: sourceKey,
    needEnglish: plan.needEnglish,
    needChinese: plan.needChinese,
    asrPrimary: plan.asrPrimary.code,
    force: force || chip != null,
  );
  await scheduleSubtitleCompletionNudge();
  SubtitleCompletionStatusHub.instance.notifyChanged();
  // Start FGS + overlay while still foreground — Android 12+ blocks later starts.
  unawaited(() async {
    final List<SubtitleCompletionJob> jobs = await store.loadJobs();
    final int done = jobs
        .where(
          (SubtitleCompletionJob j) =>
              j.status == SubtitleCompletionStatus.done,
        )
        .length;
    final int total = jobs.isEmpty ? 1 : jobs.length;
    final String compact = formatSubtitleFillCompactLabel(
      doneCount: done,
      totalCount: total,
      currentPercent: 5,
    );
    await SubtitleCompletionRuntime.instance.ensureRunning(
      label: compact,
      progress: subtitleFillOverallProgress(
        doneCount: done,
        totalCount: total,
        currentFraction: 0.05,
      ),
    );
  }());
  SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
}

Future<void> enqueueSubtitleCompletionForCourse({
  required LibraryCourseData course,
  SubtitleCompletionQueue? queue,
  String? bilibiliCookieHeader,
  bool networkFetchOfficial = true,
  SpokenLanguage? forceSpokenLanguage,
}) async {
  final SpokenLanguage? spoken =
      forceSpokenLanguage ??
      (course.spokenLanguage.trim().isEmpty
          ? null
          : spokenLanguageFromCode(course.spokenLanguage));
  for (final LibraryEpisodeItem episode in course.episodes) {
    await enqueueSubtitleCompletionForEpisode(
      episodeId: episode.id,
      videoPath: episode.videoAsset,
      zhSubtitlePath: episode.cnSubtitleAsset,
      enSubtitlePath: episode.enSubtitleAsset,
      sourceUrl: episode.sourceUrl,
      title: episode.title,
      description: course.description,
      course: course,
      episode: episode,
      queue: queue,
      bilibiliCookieHeader: bilibiliCookieHeader,
      networkFetchOfficial: networkFetchOfficial,
      forceSpokenLanguage: spoken,
    );
  }
}

/// Scan the whole library and enqueue every local episode still missing a side.
Future<void> enqueuePendingSubtitleCompletionsForCatalog({
  required List<LibraryCourseData> courses,
  SubtitleCompletionQueue? queue,
  String? bilibiliCookieHeader,
  bool networkFetchOfficial = true,
  SpokenLanguage? forceSpokenLanguage,
}) async {
  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  for (final LibraryCourseData course in courses) {
    await enqueueSubtitleCompletionForCourse(
      course: course,
      queue: store,
      bilibiliCookieHeader: bilibiliCookieHeader,
      networkFetchOfficial: networkFetchOfficial,
      forceSpokenLanguage: forceSpokenLanguage,
    );
  }
  SubtitleCompletionScheduler.instance.kick();
}
