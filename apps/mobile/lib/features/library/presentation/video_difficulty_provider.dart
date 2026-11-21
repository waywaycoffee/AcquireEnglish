import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/player_mock_state.dart';
import '../../player/presentation/player_subtitle_loader.dart';
import '../../reading/data/reading_gloss.dart';
import '../data/video_difficulty_store.dart';
import '../domain/video_difficulty.dart';
import 'library_catalog_provider.dart';
import 'library_mock_data.dart';

class VideoDifficultyState {
  const VideoDifficultyState({
    this.byCourseId = const <String, VideoDifficultyEstimate>{},
    this.scanning = false,
  });

  final Map<String, VideoDifficultyEstimate> byCourseId;
  final bool scanning;

  VideoDifficultyEstimate? operator [](String courseId) => byCourseId[courseId];

  VideoDifficultyState copyWith({
    Map<String, VideoDifficultyEstimate>? byCourseId,
    bool? scanning,
  }) {
    return VideoDifficultyState(
      byCourseId: byCourseId ?? this.byCourseId,
      scanning: scanning ?? this.scanning,
    );
  }
}

final NotifierProvider<VideoDifficultyNotifier, VideoDifficultyState>
    videoDifficultyProvider =
    NotifierProvider<VideoDifficultyNotifier, VideoDifficultyState>(
  VideoDifficultyNotifier.new,
);

class VideoDifficultyNotifier extends Notifier<VideoDifficultyState> {
  final VideoDifficultyStore _store = const VideoDifficultyStore();
  int _scanGeneration = 0;
  bool _bootstrapped = false;

  @override
  VideoDifficultyState build() {
    ref.listen<List<LibraryCourseData>>(libraryCatalogProvider, (
      List<LibraryCourseData>? previous,
      List<LibraryCourseData> next,
    ) {
      unawaited(_scanCourses(next));
    });
    unawaited(Future<void>.microtask(_bootstrap));
    return const VideoDifficultyState();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final Map<String, VideoDifficultyEstimate> cached = await _store.load();
    if (cached.isNotEmpty) {
      state = state.copyWith(byCourseId: cached);
    }
    await _scanCourses(ref.read(libraryCatalogProvider));
  }

  Future<void> refresh() => _scanCourses(ref.read(libraryCatalogProvider));

  Future<void> _scanCourses(List<LibraryCourseData> courses) async {
    final int generation = ++_scanGeneration;
    final ReadingFrequencyLexicon lexicon =
        await ref.read(readingFrequencyLexiconProvider.future);
    if (generation != _scanGeneration) return;

    state = state.copyWith(scanning: true);
    final Map<String, VideoDifficultyEstimate> next =
        Map<String, VideoDifficultyEstimate>.from(state.byCourseId);
    bool changed = false;

    for (final LibraryCourseData course in courses) {
      if (generation != _scanGeneration) return;
      final List<LibraryEpisodeItem> samples = _pickSubtitleEpisodes(course);
      if (samples.isEmpty) {
        continue;
      }
      final String fingerprint = difficultyFingerprint(
        samples.map(
          (LibraryEpisodeItem e) =>
              '${e.id}:${e.enSubtitleAsset ?? ''}:${e.cnSubtitleAsset ?? ''}',
        ),
      );
      final VideoDifficultyEstimate? existing = next[course.id];
      if (existing != null &&
          existing.fingerprint == fingerprint &&
          existing.tokenCount > 0) {
        continue;
      }

      final StringBuffer buffer = StringBuffer();
      int cueCount = 0;
      for (final LibraryEpisodeItem episode in samples) {
        final String? path = _englishSubtitlePath(episode);
        if (path == null || path.isEmpty) continue;
        try {
          final List<PlayerSubtitleLine> lines = await loadSubtitleLines(path);
          for (final PlayerSubtitleLine line in lines) {
            final String english = line.english.trim();
            if (english.isEmpty) continue;
            buffer.writeln(english);
            cueCount += 1;
            if (cueCount >= 450) break;
          }
        } catch (_) {
          // Skip unreadable tracks; keep scanning other episodes.
        }
        if (cueCount >= 450) break;
      }

      if (cueCount < 8) {
        continue;
      }

      final VideoDifficultyEstimate estimate = estimateVideoDifficulty(
        englishText: buffer.toString(),
        topFrequencyWords: lexicon.topWords,
        fingerprint: fingerprint,
      );
      next[course.id] = estimate;
      changed = true;
      state = state.copyWith(
        byCourseId: Map<String, VideoDifficultyEstimate>.from(next),
      );
    }

    if (generation != _scanGeneration) return;
    if (changed) {
      await _store.save(next);
    }
    state = state.copyWith(
      byCourseId: next,
      scanning: false,
    );
  }

  List<LibraryEpisodeItem> _pickSubtitleEpisodes(LibraryCourseData course) {
    return course.episodes
        .where((LibraryEpisodeItem e) => _englishSubtitlePath(e) != null)
        .take(3)
        .toList(growable: false);
  }

  String? _englishSubtitlePath(LibraryEpisodeItem episode) {
    final String? en = episode.enSubtitleAsset?.trim();
    if (en != null && en.isNotEmpty) return en;
    for (final LibrarySubtitleTrackItem track in episode.subtitleTracks) {
      final String code = track.languageCode.toLowerCase();
      if (code.startsWith('en') || code.contains('english')) {
        final String path = track.path.trim();
        if (path.isNotEmpty) return path;
      }
    }
    return null;
  }
}

/// Resolved CEFR for filter / badge: estimate first, then catalog level tag.
String? resolvedCourseCefr(
  LibraryCourseData course,
  VideoDifficultyEstimate? estimate,
) {
  if (estimate != null && estimate.tokenCount > 0) {
    return estimate.cefr;
  }
  return parseCefrLevel(course.level);
}

String displayCourseLevel(
  LibraryCourseData course,
  VideoDifficultyEstimate? estimate,
) {
  if (estimate != null && estimate.tokenCount > 0) {
    return estimate.displayLabel;
  }
  final String tagged = course.level.trim();
  if (tagged.isNotEmpty) return tagged;
  return '未评级';
}
