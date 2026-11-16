import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'bilingual_subtitle_helpers.dart';
import 'player_mock_state.dart';
import 'subtitle_file_persist.dart';
import 'subtitle_sentence_merge.dart';

/// Build an ASR-style sentence bundle from edited player lines.
MergedSubtitleBundle bundleFromEditedLines(List<PlayerSubtitleLine> lines) {
  final List<PlayerSubtitleLine> usable = lines
      .where(
        (PlayerSubtitleLine line) =>
            line.endMs > line.startMs &&
            (line.english.trim().isNotEmpty || line.chinese.trim().isNotEmpty),
      )
      .toList(growable: false)
    ..sort(
      (PlayerSubtitleLine a, PlayerSubtitleLine b) =>
          a.startMs.compareTo(b.startMs),
    );
  final List<SubtitleSentence> sentences = <SubtitleSentence>[];
  final List<SubtitleFragment> fragments = <SubtitleFragment>[];
  for (final PlayerSubtitleLine line in usable) {
    sentences.add(
      SubtitleSentence(
        startMs: line.startMs,
        endMs: line.endMs,
        english: line.english.trim(),
        chinese: line.chinese.trim(),
        fragmentStartMs: <int>[line.startMs],
        fragmentEndMs: <int>[line.endMs],
      ),
    );
    fragments.add(
      SubtitleFragment(
        startMs: line.startMs,
        endMs: line.endMs,
        english: line.english.trim(),
        chinese: line.chinese.trim(),
      ),
    );
  }
  return MergedSubtitleBundle(sentences: sentences, fragments: fragments);
}

/// Remerge crumb-like cues into fuller English sentences for editing.
List<PlayerSubtitleLine> remergeEnglishSentences(
  List<PlayerSubtitleLine> lines,
) {
  if (lines.length < 2) {
    return List<PlayerSubtitleLine>.from(lines);
  }
  final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
    asrLines: lines,
    chineseLines: lines,
  );
  if (bundle.sentences.isEmpty) {
    return List<PlayerSubtitleLine>.from(lines);
  }
  return bundle.sentenceLines;
}

/// Persist hand-edited bilingual lines so ASR reload + player both see them.
Future<PersistedBilingualSubtitleFiles?> persistManualSubtitleEdits({
  required String episodeId,
  required List<PlayerSubtitleLine> lines,
  String? sourceKey,
  String? videoPath,
  Future<Directory> Function()? appSupportDirectory,
}) async {
  final Future<Directory> Function() support =
      appSupportDirectory ?? getApplicationSupportDirectory;
  final List<PlayerSubtitleLine> usable = lines
      .where(
        (PlayerSubtitleLine line) =>
            line.endMs > line.startMs &&
            (looksEnglish(line.english) || looksChinese(line.chinese)),
      )
      .toList(growable: false);
  if (usable.isEmpty) {
    return null;
  }

  final Map<int, String> enLocks = <int, String>{};
  final Map<int, String> zhLocks = <int, String>{};
  for (final PlayerSubtitleLine line in usable) {
    if (looksEnglish(line.english)) {
      enLocks[line.startMs] = line.english.trim();
    }
    if (looksChinese(line.chinese)) {
      zhLocks[line.startMs] = line.chinese.trim();
    }
  }
  await saveManualEnglishLocks(
    episodeId: episodeId,
    locks: enLocks,
    appSupportDirectory: support,
  );
  await saveManualChineseLocks(
    episodeId: episodeId,
    locks: zhLocks,
    appSupportDirectory: support,
  );

  final MergedSubtitleBundle bundle = bundleFromEditedLines(usable);
  return persistAsrSentenceSubtitles(
    episodeId: episodeId,
    bundle: bundle,
    sourceKey: sourceKey,
    videoFingerprint: videoFileFingerprint(videoPath),
    origin: asrSentencesOrigin,
    appSupportDirectory: support,
  );
}
