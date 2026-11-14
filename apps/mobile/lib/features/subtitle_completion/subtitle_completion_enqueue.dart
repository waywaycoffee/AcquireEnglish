import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/bilibili_multipage.dart';
import '../import_course/domain/bilibili_import.dart';
import '../library/presentation/library_mock_data.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
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
    final bool hasEn = asrBundle.sentences.any(
      (SubtitleSentence s) => looksEnglish(s.english),
    );
    final bool hasZh = asrBundle.sentences.any(
      (SubtitleSentence s) => looksChinese(s.chinese),
    );
    return SubtitleCompletionNeed(
      needEnglish: !hasEn,
      needChinese: !hasZh,
    );
  }

  final bool reliableEn =
      isUsableSubtitlePath(enSubtitlePath) &&
      !looksLikeScopedEpisodeSubtitle(enSubtitlePath);
  String? zhPath = isUsableSubtitlePath(zhSubtitlePath)
      ? zhSubtitlePath!.trim()
      : null;
  zhPath ??= await existingOfficialBilibiliSubtitle(
    idKey: sourceKey,
    fileName: 'zh.srt',
  );
  final bool hasZh = isUsableSubtitlePath(zhPath);

  return SubtitleCompletionNeed(
    needEnglish: !reliableEn,
    needChinese: !hasZh,
  );
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

  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue();
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
  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue();
  for (final LibraryCourseData course in courses) {
    await enqueueSubtitleCompletionForCourse(course: course, queue: store);
  }
  SubtitleCompletionScheduler.instance.kick();
}
