import 'package:flutter/material.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/bilibili_import_service.dart';
import '../import_course/data/bilibili_multipage.dart';
import '../import_course/data/ensure_official_softsubs.dart';
import '../import_course/domain/bilibili_import.dart';
import '../library/presentation/library_catalog_provider.dart';
import '../library/presentation/library_mock_data.dart';
import '../player/presentation/asr_subtitle_cache.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/hardsub_asr_repair.dart';
import '../player/presentation/manual_subtitle_guard.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/subtitle_file_persist.dart';
import '../player/presentation/subtitle_sentence_merge.dart';
import 'cloud_subtitle_job_tracker.dart';
import 'retranslate_episode_chinese.dart';
import 'spoken_language.dart';
import 'subtitle_completion_enqueue.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_scheduler.dart';
import 'subtitle_completion_status_hub.dart';

enum SubtitleResetSide { chinese, english, both }

/// Confirm before wiping / regenerating subtitles that already exist.
Future<bool> confirmRerecognizeExistingSubtitles(
  BuildContext context, {
  required SubtitleResetSide side,
}) async {
  final String label = switch (side) {
    SubtitleResetSide.chinese => '中文字幕',
    SubtitleResetSide.english => '英文字幕',
    SubtitleResetSide.both => '中英字幕',
  };
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: Text('重新生成$label？'),
      content: Text('本集已有$label。继续会覆盖现有内容，并重新排队生成。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('继续生成'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Player / library「重新识别」chooser: English ASR vs Chinese EN→ZH vs both.
Future<SubtitleResetSide?> showSubtitleRerecognizeDialog(
  BuildContext context,
) {
  return showDialog<SubtitleResetSide>(
    context: context,
    builder: (BuildContext context) => SimpleDialog(
      title: const Text('重新识别'),
      children: <Widget>[
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, SubtitleResetSide.english),
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.record_voice_over_rounded),
            title: Text('重新识别英文字幕'),
            subtitle: Text('用语音 ASR 重新识别英文（不用中文翻译）'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, SubtitleResetSide.chinese),
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.translate_rounded),
            title: Text('重新识别中文字幕'),
            subtitle: Text('保留英文，用英文字幕重新翻译中文'),
          ),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, SubtitleResetSide.both),
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.restart_alt_rounded),
            title: Text('全部重新识别'),
            subtitle: Text('清空中英后：先 ASR 英文，再翻译中文'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

/// Marker under app-support: next scheduler bootstrap reimports all course
/// subtitles from official softsubs + fill missing sides (ASR/translate).
const String kReimportSubtitlesFlagName = 'reimport_subtitles.flag';

/// Re-run import-time subtitle pipeline for a whole course.
///
/// Clears ASR/`episode_subtitles` only — keeps B站 official softsubs on disk,
/// re-links them into the catalog, optionally refreshes from network, then
/// enqueues fill for missing sides (does not force-wipe good official CC).
Future<int> reimportCourseSubtitles({
  required LibraryCatalogNotifier catalog,
  required LibraryCourseData course,
  String? bilibiliCookieHeader,
  SubtitleCompletionQueue? queue,
  AsrSubtitleCache cache = const AsrSubtitleCache(),
  bool refetchOfficial = true,
}) async {
  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  final BilibiliImportService service = BilibiliImportService.withCookie(
    bilibiliCookieHeader,
  );
  int queued = 0;
  for (final LibraryEpisodeItem episode in course.episodes) {
    final String episodeId = episode.id.trim();
    if (episodeId.isEmpty) {
      continue;
    }
    await deletePersistedBilingualSubtitleFiles(episodeId: episodeId);
    await clearHardsubChineseTranslationMarker(episodeId: episodeId);
    try {
      await clearManualSubtitleLocks(episodeId: episodeId);
    } catch (_) {}

    final String? videoPath = episode.videoAsset?.trim();
    if (isUsableLocalVideoPath(videoPath)) {
      try {
        await cache.delete(episodeId: episodeId, videoPath: videoPath!);
      } catch (_) {}
    }

    await store.removeEpisode(episodeId);

    final String? source =
        bilibiliSourceForEpisode(
          course: course,
          episode: episode,
          videoAsset: videoPath,
        ) ??
        episode.sourceUrl;
    final String? sourceKey = bilibiliEpisodeCacheKey(
      course: course,
      episode: episode,
      sourceUrl: source,
      videoAsset: videoPath,
    );

    final OfficialSoftsubs soft = await ensureOfficialSoftsubs(
      sourceUrl: source,
      sourceKey: sourceKey,
      bilibiliCookieHeader: bilibiliCookieHeader,
      networkFetch: refetchOfficial,
      service: service,
    );
    final String? enPath = soft.enPath;
    final String? zhPath = soft.zhPath;

    // Drop ASR catalog links (files already deleted), then attach official.
    await catalog.relinkEpisodeSubtitleFiles(
      episodeId: episodeId,
      clearEnglishIfMissing: true,
      clearChineseIfMissing: true,
    );
    await catalog.updateEpisodeLocalMedia(
      courseId: course.id,
      episodeId: episodeId,
      sourceUrl: source,
      enSubtitlePath: enPath,
      zhSubtitlePath: zhPath,
    );

    if (!isUsableLocalVideoPath(videoPath)) {
      continue;
    }
    await enqueueSubtitleCompletionForEpisode(
      episodeId: episodeId,
      videoPath: videoPath,
      zhSubtitlePath: zhPath,
      enSubtitlePath: enPath,
      sourceUrl: source,
      title: episode.title,
      description: course.description,
      course: course,
      episode: episode,
      force: false,
      queue: store,
      bilibiliCookieHeader: bilibiliCookieHeader,
      // Softsubs just fetched above — avoid a duplicate network round-trip.
      networkFetchOfficial: false,
    );
    queued += 1;
  }
  SubtitleCompletionStatusHub.instance.notifyChanged();
  SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
  return queued;
}

/// Wipe machine/official subtitle files for one episode and optionally re-queue
/// speech fill. Use when EN↔ZH translation or ASR output is wrong.
Future<void> resetEpisodeSubtitles({
  required LibraryCatalogNotifier catalog,
  required LibraryCourseData course,
  required LibraryEpisodeItem episode,
  String? bilibiliCookieHeader,
  bool requeueFill = true,
  SpokenLanguage? forceSpokenLanguage,
  SubtitleCompletionQueue? queue,
  AsrSubtitleCache cache = const AsrSubtitleCache(),
}) async {
  final String episodeId = episode.id;
  await deletePersistedBilingualSubtitleFiles(episodeId: episodeId);
  await clearHardsubChineseTranslationMarker(episodeId: episodeId);
  try {
    await clearManualSubtitleLocks(episodeId: episodeId);
  } catch (_) {}

  final String? videoPath = episode.videoAsset;
  if ((videoPath ?? '').trim().isNotEmpty) {
    try {
      await cache.delete(episodeId: episodeId, videoPath: videoPath!.trim());
    } catch (_) {}
  }

  final String? source =
      bilibiliSourceForEpisode(
        course: course,
        episode: episode,
        videoAsset: videoPath,
      ) ??
      episode.sourceUrl;
  final String? sourceKey =
      bilibiliIdKeyFromPath(source) ??
      bilibiliIdKeyFromPath(videoPath) ??
      BilibiliImport.extractIds(source ?? '')?['bvid'];
  if ((sourceKey ?? '').trim().isNotEmpty) {
    try {
      await BilibiliImportService.withCookie(
        bilibiliCookieHeader,
      ).clearOfficialSubtitleFiles(sourceKey);
    } catch (_) {}
  }

  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  await store.removeEpisode(episodeId);

  await catalog.updateEpisodeLocalMedia(
    courseId: course.id,
    episodeId: episodeId,
    sourceUrl: source,
    clearSubtitles: true,
  );

  SubtitleCompletionStatusHub.instance.notifyChanged();

  if (!requeueFill || !isUsableLocalVideoPath(videoPath)) {
    SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    return;
  }

  await enqueueSubtitleCompletionForEpisode(
    episodeId: episodeId,
    videoPath: videoPath,
    zhSubtitlePath: null,
    enSubtitlePath: null,
    sourceUrl: source,
    title: episode.title,
    description: course.description,
    course: course,
    episode: episode,
    force: true,
    forceSpokenLanguage: forceSpokenLanguage ?? SpokenLanguage.english,
    queue: store,
  );
}

/// Reset Chinese only: keep English, EN→ZH re-translate.
Future<bool> resetEpisodeChineseSubtitles({
  required LibraryCatalogNotifier catalog,
  required LibraryCourseData course,
  required LibraryEpisodeItem episode,
  String? bilibiliCookieHeader,
  SubtitleCompletionQueue? queue,
  List<PlayerSubtitleLine>? fallbackEnglishLines,
}) {
  return retranslateEpisodeChineseFromEnglish(
    catalog: catalog,
    course: course,
    episode: episode,
    bilibiliCookieHeader: bilibiliCookieHeader,
    queue: queue,
    fallbackEnglishLines: fallbackEnglishLines,
  );
}

/// Reset English only: keep Chinese when present; English always via ASR.
Future<bool> resetEpisodeEnglishSubtitles({
  required LibraryCatalogNotifier catalog,
  required LibraryCourseData course,
  required LibraryEpisodeItem episode,
  String? bilibiliCookieHeader,
  SubtitleCompletionQueue? queue,
  AsrSubtitleCache cache = const AsrSubtitleCache(),
  List<PlayerSubtitleLine>? fallbackChineseLines,
  bool allowWhileBusy = false,
}) async {
  final String episodeId = episode.id.trim();
  if (episodeId.isEmpty) {
    return false;
  }
  if (!allowWhileBusy) {
    final SubtitleCompletionJob? active = await (queue ??
            SubtitleCompletionQueue.shared)
        .loadJobs()
        .then(
          (List<SubtitleCompletionJob> jobs) => jobs
              .where(
                (SubtitleCompletionJob j) =>
                    j.episodeId == episodeId &&
                    (j.status == SubtitleCompletionStatus.pending ||
                        j.status == SubtitleCompletionStatus.running) &&
                    j.needEnglish,
              )
              .firstOrNull,
        );
    if (active != null ||
        CloudSubtitleJobTracker.instance.forEpisode(episodeId) != null) {
      // Generation already in flight — do not wipe / restart.
      return false;
    }
  }
  final String? videoPath = episode.videoAsset?.trim();
  if (!isUsableLocalVideoPath(videoPath)) {
    return false;
  }

  final String? sourceKey = bilibiliEpisodeCacheKey(
    course: course,
    episode: episode,
    sourceUrl: episode.sourceUrl,
    videoAsset: videoPath,
  );

  final MergedSubtitleBundle? existing = await loadAsrSentenceSubtitles(
    episodeId: episodeId,
    sourceKey: sourceKey,
    videoFingerprint: videoFileFingerprint(videoPath),
  );

  final List<PlayerSubtitleLine> keptChinese = <PlayerSubtitleLine>[];
  if (existing != null) {
    for (final SubtitleSentence sentence in existing.sentences) {
      if (looksChinese(sentence.chinese)) {
        keptChinese.add(
          PlayerSubtitleLine(
            startTime: sentence.startTime,
            english: '',
            chinese: sentence.chinese,
            startMs: sentence.startMs,
            endMs: sentence.endMs,
          ),
        );
      }
    }
  }
  if (keptChinese.isEmpty && fallbackChineseLines != null) {
    for (final PlayerSubtitleLine line in fallbackChineseLines) {
      if (looksChinese(line.chinese)) {
        keptChinese.add(
          PlayerSubtitleLine(
            startTime: line.startTime,
            english: '',
            chinese: line.chinese,
            startMs: line.startMs,
            endMs: line.endMs,
          ),
        );
      }
    }
  }

  // Clear speech English cache so Whisper runs fresh.
  try {
    await cache.delete(episodeId: episodeId, videoPath: videoPath!);
  } catch (_) {}

  if (keptChinese.isEmpty) {
    await deletePersistedBilingualSubtitleFiles(episodeId: episodeId);
    await clearHardsubChineseTranslationMarker(episodeId: episodeId);
  } else {
    // Persist Chinese-only so ASR English can re-attach by time overlap.
    final MergedSubtitleBundle chineseOnly = MergedSubtitleBundle(
      sentences: keptChinese
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
      fragments: keptChinese
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
    await persistAsrSentenceSubtitles(
      episodeId: episodeId,
      bundle: chineseOnly,
      sourceKey: sourceKey,
      videoFingerprint: videoFileFingerprint(videoPath),
      origin: asrSentencesOrigin,
    );
  }

  try {
    await clearManualSubtitleLocks(episodeId: episodeId);
  } catch (_) {}

  final String idKey = (sourceKey ?? '').trim();
  if (idKey.isNotEmpty) {
    try {
      await BilibiliImportService.withCookie(
        bilibiliCookieHeader,
      ).clearOfficialSubtitleFiles(idKey);
    } catch (_) {}
  }

  await catalog.relinkEpisodeSubtitleFiles(
    episodeId: episodeId,
    clearEnglishIfMissing: true,
    clearChineseIfMissing: keptChinese.isEmpty,
  );

  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  await store.enqueue(
    episodeId: episodeId,
    videoPath: videoPath!,
    zhPath: null,
    enPath: null,
    sourceKey: sourceKey,
    needEnglish: true,
    // Chinese kept on disk — do not EN→ZH unless missing.
    needChinese: keptChinese.isEmpty,
    asrPrimary: 'en',
    force: true,
  );
  await store.prioritizeEpisode(episodeId);
  SubtitleCompletionStatusHub.instance.notifyChanged();
  SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
  return true;
}
