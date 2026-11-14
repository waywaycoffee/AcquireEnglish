import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/bilibili_multipage.dart';
import '../import_course/domain/bilibili_import.dart';
import '../library/presentation/library_mock_data.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/player_subtitle_loader.dart';
import '../player/presentation/subtitle_file_persist.dart';
import '../player/presentation/subtitle_sentence_merge.dart';
import 'subtitle_completion_background.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_scheduler.dart';

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
  });

  final bool needEnglish;
  final bool needChinese;

  bool get any => needEnglish || needChinese;
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
  bool force = false,
  Future<Directory> Function()? appSupportDirectory,
}) async {
  if (force) {
    return const SubtitleCompletionNeed(needEnglish: true, needChinese: true);
  }

  final MergedSubtitleBundle? asrBundle = await loadAsrSentenceSubtitles(
    episodeId: episodeId,
    sourceKey: sourceKey,
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
    return SubtitleCompletionNeed(
      needEnglish: enHits * 2 < total,
      needChinese: zhHits * 2 < total,
    );
  }

  final bool pathLooksOfficialEn =
      isUsableSubtitlePath(enSubtitlePath) &&
      !looksLikeScopedEpisodeSubtitle(enSubtitlePath);
  String? zhPath = isUsableSubtitlePath(zhSubtitlePath)
      ? zhSubtitlePath!.trim()
      : null;
  zhPath ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'zh.srt',
  );
  // Paths may exist but be empty, unreadable, or the wrong language (e.g. a
  // Chinese CC saved as en.srt). Size + cue language must both pass.
  final bool hasReliableEn =
      pathLooksOfficialEn &&
      await _subtitleFileHasLanguage(
        enSubtitlePath,
        requireEnglish: true,
      );
  final bool hasZh =
      isUsableSubtitlePath(zhPath) &&
      await _subtitleFileHasLanguage(zhPath, requireEnglish: false);

  return SubtitleCompletionNeed(
    needEnglish: !hasReliableEn,
    needChinese: !hasZh,
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

/// Enqueue completion when English and/or Chinese is missing.
Future<void> enqueueSubtitleCompletionForEpisode({
  required String episodeId,
  required String? videoPath,
  String? zhSubtitlePath,
  String? enSubtitlePath,
  String? sourceUrl,
  SubtitleCompletionQueue? queue,
  bool force = false,
  Future<Directory> Function()? appSupportDirectory,
}) async {
  if (!isUsableLocalVideoPath(videoPath)) {
    return;
  }

  final String? sourceKey =
      bilibiliIdKeyFromPath(sourceUrl) ??
      bilibiliIdKeyFromPath(videoPath) ??
      BilibiliImport.extractIds(sourceUrl ?? '')?['bvid'];

  String? zhPath = isUsableSubtitlePath(zhSubtitlePath)
      ? zhSubtitlePath!.trim()
      : null;
  zhPath ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'zh.srt',
  );

  String? enPath = isUsableSubtitlePath(enSubtitlePath)
      ? enSubtitlePath!.trim()
      : null;
  enPath ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'en.srt',
  );

  final SubtitleCompletionNeed need = await detectSubtitleCompletionNeed(
    episodeId: episodeId,
    zhSubtitlePath: zhPath,
    enSubtitlePath: enPath,
    sourceKey: sourceKey,
    force: force,
    appSupportDirectory: appSupportDirectory,
  );
  if (!need.any) {
    return;
  }

  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  await store.enqueue(
    episodeId: episodeId,
    videoPath: videoPath!.trim(),
    zhPath: zhPath,
    enPath: enPath,
    sourceKey: sourceKey,
    needEnglish: need.needEnglish,
    needChinese: need.needChinese,
    force: force,
  );
  await scheduleSubtitleCompletionNudge();
  SubtitleCompletionScheduler.instance.kick();
}

Future<void> enqueueSubtitleCompletionForCourse({
  required LibraryCourseData course,
  SubtitleCompletionQueue? queue,
}) async {
  for (final LibraryEpisodeItem episode in course.episodes) {
    await enqueueSubtitleCompletionForEpisode(
      episodeId: episode.id,
      videoPath: episode.videoAsset,
      zhSubtitlePath: episode.cnSubtitleAsset,
      enSubtitlePath: episode.enSubtitleAsset,
      sourceUrl: episode.sourceUrl,
      queue: queue,
    );
  }
}

/// Scan the whole library and enqueue every local episode still missing a side.
Future<void> enqueuePendingSubtitleCompletionsForCatalog({
  required List<LibraryCourseData> courses,
  SubtitleCompletionQueue? queue,
}) async {
  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  for (final LibraryCourseData course in courses) {
    await enqueueSubtitleCompletionForCourse(course: course, queue: store);
  }
  SubtitleCompletionScheduler.instance.kick();
}
