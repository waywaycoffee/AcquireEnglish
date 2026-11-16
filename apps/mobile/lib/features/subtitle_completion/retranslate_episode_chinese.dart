import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../import_course/data/bilibili_episode_prepare.dart';
import '../import_course/data/bilibili_import_service.dart';
import '../import_course/data/bilibili_multipage.dart';
import '../library/presentation/library_catalog_provider.dart';
import '../library/presentation/library_mock_data.dart';
import '../player/presentation/bilingual_subtitle_helpers.dart';
import '../player/presentation/hardsub_asr_repair.dart';
import '../player/presentation/player_mock_state.dart';
import '../player/presentation/player_subtitle_loader.dart';
import '../player/presentation/subtitle_file_persist.dart';
import '../player/presentation/subtitle_sentence_merge.dart';
import 'spoken_language.dart';
import 'subtitle_completion_enqueue.dart';
import 'subtitle_completion_queue.dart';
import 'subtitle_completion_scheduler.dart';
import 'subtitle_completion_status_hub.dart';

const String _oneShotPrefsKey = 'retranslate_ep02_dirty_zh_v2';

/// Episode 02 from the screenshot course ("如何学得飞快…").
bool _isTargetEpisode02({
  required LibraryCourseData course,
  required LibraryEpisodeItem episode,
}) {
  final String title = episode.title.trim();
  if (title.contains('如何学得飞快')) {
    return true;
  }
  final String num = episode.numberStr.trim().replaceFirst(RegExp(r'^0+'), '');
  if (num != '2') {
    return false;
  }
  final String courseTitle = course.title.trim();
  return courseTitle.contains('英语大脑') ||
      courseTitle.contains('Building Your English') ||
      course.episodes.any(
        (LibraryEpisodeItem e) => e.title.contains('构建你的英语大脑'),
      );
}

/// Wipe Chinese under existing English, then enqueue EN→ZH only.
///
/// Prefers ASR sentence English; falls back to [fallbackEnglishLines] or the
/// episode's `en.srt`. Never uses Chinese→English as the Chinese reset path.
Future<bool> retranslateEpisodeChineseFromEnglish({
  required LibraryCatalogNotifier catalog,
  required LibraryCourseData course,
  required LibraryEpisodeItem episode,
  String? bilibiliCookieHeader,
  SubtitleCompletionQueue? queue,
  List<PlayerSubtitleLine>? fallbackEnglishLines,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  final String episodeId = episode.id.trim();
  if (episodeId.isEmpty) {
    return false;
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

  MergedSubtitleBundle? existing = await loadAsrSentenceSubtitles(
    episodeId: episodeId,
    sourceKey: sourceKey,
    videoFingerprint: videoFileFingerprint(videoPath),
    appSupportDirectory: appSupportDirectory,
  );

  // No ASR bundle — build one from fallback / official EN so EN→ZH can run.
  if (existing == null ||
      existing.sentences.every(
        (SubtitleSentence s) => !looksEnglish(s.english),
      )) {
    List<PlayerSubtitleLine> englishLines = (fallbackEnglishLines ??
            const <PlayerSubtitleLine>[])
        .where((PlayerSubtitleLine line) => looksEnglish(line.english))
        .toList(growable: false);
    if (englishLines.isEmpty && isUsableSubtitlePath(episode.enSubtitleAsset)) {
      try {
        englishLines = await loadSubtitleLines(episode.enSubtitleAsset!);
        englishLines = englishLines
            .where((PlayerSubtitleLine line) => looksEnglish(line.english))
            .toList(growable: false);
      } catch (_) {}
    }
    if (englishLines.isEmpty) {
      // No English at all — must ASR English first, then ZH.
      await enqueueSubtitleCompletionForEpisode(
        episodeId: episodeId,
        videoPath: videoPath,
        zhSubtitlePath: null,
        enSubtitlePath: null,
        sourceUrl: episode.sourceUrl,
        title: episode.title,
        description: course.description,
        course: course,
        episode: episode,
        chip: SubtitleFillChip.chinese,
        forceSpokenLanguage: SpokenLanguage.english,
        queue: queue,
        appSupportDirectory: appSupportDirectory,
      );
      await (queue ?? SubtitleCompletionQueue.shared).prioritizeEpisode(
        episodeId,
      );
      SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
      return true;
    }
    existing = MergedSubtitleBundle(
      sentences: englishLines
          .map(
            (PlayerSubtitleLine line) => SubtitleSentence(
              startMs: line.startMs,
              endMs: line.endMs,
              english: line.english,
              chinese: '',
              fragmentStartMs: <int>[line.startMs],
              fragmentEndMs: <int>[line.endMs],
              words: line.words,
            ),
          )
          .toList(growable: false),
      fragments: const <SubtitleFragment>[],
    );
  }

  final MergedSubtitleBundle cleared = MergedSubtitleBundle(
    sentences: existing.sentences
        .map(
          (SubtitleSentence sentence) => SubtitleSentence(
            startMs: sentence.startMs,
            endMs: sentence.endMs,
            english: sentence.english,
            chinese: '',
            fragmentStartMs: sentence.fragmentStartMs,
            fragmentEndMs: sentence.fragmentEndMs,
            words: sentence.words,
          ),
        )
        .toList(growable: false),
    fragments: existing.fragments
        .map(
          (SubtitleFragment fragment) => SubtitleFragment(
            startMs: fragment.startMs,
            endMs: fragment.endMs,
            english: fragment.english,
            chinese: '',
            words: fragment.words,
          ),
        )
        .toList(growable: false),
  );

  await persistAsrSentenceSubtitles(
    episodeId: episodeId,
    bundle: cleared,
    sourceKey: sourceKey,
    videoFingerprint: videoFileFingerprint(videoPath),
    appSupportDirectory: appSupportDirectory,
  );

  await clearHardsubChineseTranslationMarker(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  );

  final String idKey = (sourceKey ?? '').trim();
  if (idKey.isNotEmpty) {
    try {
      await BilibiliImportService.withCookie(
        bilibiliCookieHeader,
      ).clearOfficialSubtitleFiles(idKey);
    } catch (_) {}
  }

  try {
    await saveManualChineseLocks(
      episodeId: episodeId,
      locks: const <int, String>{},
    );
  } catch (_) {}

  await catalog.relinkEpisodeSubtitleFiles(
    episodeId: episodeId,
    clearChineseIfMissing: true,
  );

  final SubtitleCompletionQueue store = queue ?? SubtitleCompletionQueue.shared;
  // Chinese-only job; ASR English already on disk.
  await store.enqueue(
    episodeId: episodeId,
    videoPath: videoPath!,
    zhPath: null,
    enPath: episode.enSubtitleAsset,
    sourceKey: sourceKey,
    needEnglish: false,
    needChinese: true,
    asrPrimary: 'en',
    force: true,
  );
  await store.prioritizeEpisode(episodeId);

  SubtitleCompletionStatusHub.instance.notifyChanged();
  SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
  return true;
}

/// One-shot: clear ep02 dirty ZH and re-translate from English.
Future<void> runOneShotRetranslateEpisode02Chinese({
  required LibraryCatalogNotifier catalog,
  required List<LibraryCourseData> courses,
  String? bilibiliCookieHeader,
}) async {
  final Box<String> box = Hive.box<String>('prefs');
  if (box.get(_oneShotPrefsKey) == '1') {
    return;
  }

  LibraryCourseData? course;
  LibraryEpisodeItem? episode;
  for (final LibraryCourseData c in courses) {
    for (final LibraryEpisodeItem e in c.episodes) {
      if (_isTargetEpisode02(course: c, episode: e)) {
        course = c;
        episode = e;
        break;
      }
    }
    if (episode != null) {
      break;
    }
  }
  if (course == null || episode == null) {
    return;
  }

  final bool ok = await retranslateEpisodeChineseFromEnglish(
    catalog: catalog,
    course: course,
    episode: episode,
    bilibiliCookieHeader: bilibiliCookieHeader,
  );
  if (ok) {
    await box.put(_oneShotPrefsKey, '1');
    // ignore: avoid_print
    print(
      'subtitle.retranslate ep02 ZH from EN '
      'id=${episode.id} title=${episode.title}',
    );
  }
}
