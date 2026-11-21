import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../daily_review/domain/daily_review.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../daily_review/presentation/review_clip_player_sheet.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/ocr_subtitle_sampler.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../domain/word_review_settings.dart';
import 'word_book_provider.dart';
import 'word_video_relink.dart';

class _FavoriteColors {
  const _FavoriteColors({required this.dark});

  final bool dark;
  Color get background =>
      dark ? const Color(0xFF111318) : const Color(0xFFF7F8F4);
  Color get surface => dark ? const Color(0xFF242832) : Colors.white;
  Color get accentSurface =>
      dark ? const Color(0xFF202A24) : const Color(0xFFE9F3E2);
  Color get accent => dark ? const Color(0xFFB8F174) : const Color(0xFF397A2B);
  Color get text => dark ? Colors.white : const Color(0xFF203026);
  Color get secondary =>
      dark ? const Color(0xFFAAB0BB) : const Color(0xFF657267);
}

/// The saved word book contains exactly the words the learner bookmarked.
class FavoriteWordBookScreen extends ConsumerStatefulWidget {
  const FavoriteWordBookScreen({super.key});

  @override
  ConsumerState<FavoriteWordBookScreen> createState() =>
      _FavoriteWordBookScreenState();
}

class _FavoriteWordBookScreenState
    extends ConsumerState<FavoriteWordBookScreen> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final List<WordEntry> allSaved = ref
        .watch(wordBookProvider)
        .where((WordEntry word) => word.favorite)
        .toList(growable: false);
    final List<WordEntry> saved = allSaved
        .where(
          (WordEntry word) =>
              word.word.toLowerCase().contains(query.trim().toLowerCase()),
        )
        .toList(growable: false);
    final Map<String, ReviewRecord> records = ref
        .watch(dailyReviewProvider)
        .records;
    final _FavoriteColors colors = _FavoriteColors(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return PadScaffold(
      currentDestination: AppNavDestination.review,
      topBar: PadTopBar(
        title: '收藏词本',
        description: '原样保留收藏的生词 · 共 ${allSaved.length} 词',
      ),
      body: ColoredBox(
        color: colors.background,
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (String value) => setState(() => query = value),
                  decoration: InputDecoration(
                    hintText: '搜索收藏的单词',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.accentSurface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${allSaved.length} 个收藏',
                        style: TextStyle(
                          color: colors.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '点词查看真实场景',
                        style: TextStyle(color: colors.secondary),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: saved.isEmpty
                    ? Center(
                        child: Text(
                          query.isEmpty
                              ? '还没有收藏生词，阅读或看视频时点收藏即可加入。'
                              : '没有找到匹配的收藏词。',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: saved.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final WordEntry word = saved[index];
                          final int reviews = favoriteWordReviewCount(
                            word,
                            records,
                          );
                          final int scenes = favoriteWordSceneCount(word);
                          return Material(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      FavoriteWordDetailScreen(word: word.word),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      word.word,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            color: colors.text,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      word.primaryGloss.isEmpty
                                          ? '暂无释义'
                                          : word.primaryGloss,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: colors.secondary),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '背诵 $reviews 次   ·   见过 $scenes 个场景',
                                      style: TextStyle(
                                        color: colors.accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (word
                                        .occurrences
                                        .isNotEmpty) ...<Widget>[
                                      const SizedBox(height: 6),
                                      Text(
                                        '${word.occurrences.first.course} · ${word.occurrences.first.earliestContext?.time ?? word.occurrences.first.time}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: colors.secondary),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int favoriteWordReviewCount(WordEntry word, Map<String, ReviewRecord> records) {
  final int current = WordPracticeMode.values.fold<int>(
    0,
    (int count, WordPracticeMode mode) =>
        count + (records[vocabFsrsKey(word.word, mode)]?.reviews ?? 0),
  );
  return current > 0
      ? current
      : (records[legacyWordFsrsKey(word.word)]?.reviews ?? word.repetitions);
}

/// One scene per distinct video/article/book (not every timeline hit).
int favoriteWordSceneCount(WordEntry word) =>
    favoriteWordDistinctScenes(word).length;

/// Same-video repeats collapse to the earliest timeline hit only.
List<({WordOccurrence occurrence, WordContext scene})>
favoriteWordDistinctScenes(WordEntry word) {
  final Map<String, ({WordOccurrence occurrence, WordContext scene})> byKey =
      <String, ({WordOccurrence occurrence, WordContext scene})>{};
  for (final WordOccurrence occurrence in word.occurrences) {
    final WordContext? scene = occurrence.earliestContext;
    if (scene == null) continue;
    final String dedupeKey = occurrence.episodeId.trim().isNotEmpty
        ? occurrence.episodeId.trim()
        : '${occurrence.course.trim()}|${occurrence.episode.trim()}';
    final ({WordOccurrence occurrence, WordContext scene})? existing =
        byKey[dedupeKey];
    if (existing == null) {
      byKey[dedupeKey] = (occurrence: occurrence, scene: scene);
      continue;
    }
    final int? existingMs = WordOccurrence.contextStartMs(existing.scene);
    final int? nextMs = WordOccurrence.contextStartMs(scene);
    if (nextMs != null && (existingMs == null || nextMs < existingMs)) {
      byKey[dedupeKey] = (occurrence: occurrence, scene: scene);
    }
  }
  return byKey.values.toList(growable: false);
}

int favoriteSceneClipStartMs(int positionMs) => positionMs < 0 ? 0 : positionMs;

class FavoriteWordDetailScreen extends ConsumerWidget {
  const FavoriteWordDetailScreen({required this.word, super.key});
  final String word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WordEntry? entry = ref
        .watch(wordBookProvider)
        .where((WordEntry item) => item.word == word && item.favorite)
        .firstOrNull;
    final _FavoriteColors colors = _FavoriteColors(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('收藏词本')),
        body: const Center(child: Text('这个词已从收藏词本移除。')),
      );
    }
    final int reviews = favoriteWordReviewCount(
      entry,
      ref.watch(dailyReviewProvider).records,
    );
    final int scenes = favoriteWordSceneCount(entry);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('收藏词详情'),
        backgroundColor: colors.background,
        foregroundColor: colors.text,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Text(
            entry.word,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              if ((entry.phonetic ?? '').isNotEmpty) entry.phonetic!,
              if (entry.primaryGloss.isNotEmpty) entry.primaryGloss,
            ].join('   '),
            style: TextStyle(color: colors.secondary),
          ),
          const SizedBox(height: 16),
          Card(
            color: colors.accentSurface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '背诵 $reviews 次     ·     见过 $scenes 个场景',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: colors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '见过的场景',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 10),
          if (scenes == 0) const Text('这个词暂无带时间轴的场景。'),
          for (final ({WordOccurrence occurrence, WordContext scene}) item
              in favoriteWordDistinctScenes(entry))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _FavoriteSceneCard(
                occurrence: item.occurrence,
                scene: item.scene,
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoriteSceneCard extends ConsumerWidget {
  const _FavoriteSceneCard({required this.occurrence, required this.scene});
  final WordOccurrence occurrence;
  final WordContext scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<WordVideoCandidate> videos = resolveWordVideoCandidates(
      courses: ref.watch(libraryCatalogProvider),
      occurrence: occurrence,
    );
    final String? videoPath = occurrence.mediaKind == '视频' && videos.length == 1
        ? videos.single.episode.videoAsset
        : null;
    final int? positionMs = WordOccurrence.contextStartMs(scene);
    final _FavoriteColors colors = _FavoriteColors(
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    return Card(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (videoPath != null && positionMs != null) ...<Widget>[
              _SceneFrame(
                key: ValueKey<String>('$videoPath:$positionMs'),
                videoPath: videoPath,
                positionMs: positionMs,
              ),
              const SizedBox(height: 10),
            ],
            Text(
              '${occurrence.course} · ${occurrence.episode} · ${scene.time}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.secondary),
            ),
            const SizedBox(height: 6),
            Text(
              scene.sentence,
              style: TextStyle(fontWeight: FontWeight.w700, color: colors.text),
            ),
            if (scene.chinese.isNotEmpty)
              Text(scene.chinese, style: TextStyle(color: colors.secondary)),
            if (videoPath != null && positionMs != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: colors.accent),
                  onPressed: () => showReviewClipPlayerSheet(
                    context,
                    title: '${occurrence.course} · ${scene.time}',
                    videoPath: videoPath,
                    startMs: favoriteSceneClipStartMs(positionMs),
                    durationMs: 4000,
                  ),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: Text(
                    '从时间点播放 4 秒',
                    style: TextStyle(color: colors.accent),
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('原视频不可用，已保留原句和时间点。'),
              ),
          ],
        ),
      ),
    );
  }
}

class _SceneFrame extends StatefulWidget {
  const _SceneFrame({
    required this.videoPath,
    required this.positionMs,
    super.key,
  });
  final String videoPath;
  final int positionMs;

  @override
  State<_SceneFrame> createState() => _SceneFrameState();
}

class _SceneFrameState extends State<_SceneFrame> {
  Uint8List? image;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_capture());
  }

  Future<void> _capture() async {
    final Player player = Player();
    try {
      await player.open(Media(widget.videoPath), play: false);
      await player.seek(Duration(milliseconds: widget.positionMs));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final Uint8List? captured = await OcrSubtitleSampler.defaultCaptureFrame(
        player: player,
        videoPath: widget.videoPath,
        positionMs: widget.positionMs,
      );
      if (mounted) setState(() => image = captured);
    } catch (_) {
      // An old saved video may have moved; the sentence and time remain useful.
    } finally {
      await player.dispose();
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: image != null
          ? Image.memory(image!, fit: BoxFit.cover)
          : ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              child: Center(
                child: loading
                    ? const CircularProgressIndicator()
                    : const Text('暂无时间点截图'),
              ),
            ),
    ),
  );
}
