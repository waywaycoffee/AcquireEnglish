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
import '../../phrases/presentation/phrase_book_provider.dart';
import '../domain/vocab_card_kind.dart';
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
  String _query = '';
  String _sourceQuery = '';
  String _kind = '全部';
  String _scene = '全部场景';
  DateTimeRange? _range;

  bool _matches(String text, String query) => query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .every(text.toLowerCase().contains);

  bool _matchesDate(DateTime? date) {
    final DateTimeRange? range = _range;
    if (range == null) return true;
    if (date == null) return false;
    final DateTime day = DateUtils.dateOnly(date.toLocal());
    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  bool _matchesSource(String scene, String title) =>
      (_scene == '全部场景' || _scene == scene) && _matches(title, _sourceQuery);

  Future<void> _pickDateRange() async {
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (mounted && range != null) setState(() => _range = range);
  }

  @override
  Widget build(BuildContext context) {
    final List<_SavedItem> items = <_SavedItem>[];
    for (final WordEntry word in ref.watch(wordBookProvider)) {
      if (!word.favorite) continue;
      final String kind = switch (word.kind) {
        VocabCardKind.word => '单词',
        VocabCardKind.phrase => '短语',
        VocabCardKind.pattern => '句子',
      };
      if (_kind != '全部' && _kind != kind) continue;
      if (!_matches('${word.word} ${word.primaryGloss}', _query)) continue;
      final DateTime? date = word.collectedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(word.collectedAtMs!);
      if (!_matchesDate(date)) continue;
      final sources = word.occurrences.where(
        (item) => _matchesSource(
          item.mediaKind == '文章' ? '阅读' : item.mediaKind,
          '${item.course} ${item.episode} ${item.videoFileName ?? ''}',
        ),
      );
      final WordOccurrence? source = sources.firstOrNull;
      if (source == null &&
          (_scene != '全部场景' || _sourceQuery.trim().isNotEmpty))
        continue;
      items.add((
        title: word.word,
        translation: word.primaryGloss,
        kind: kind,
        source: source == null ? '' : '${source.course} · ${source.episode}',
        date: date,
        word: word.word,
      ));
    }
    for (final PhraseEntry phrase in ref.watch(phraseBookProvider)) {
      final String kind =
          reviewKindForPhraseEntry(phrase) == ReviewKind.sentence ? '句子' : '短语';
      if (_kind != '全部' && _kind != kind) continue;
      if (!_matches('${phrase.english} ${phrase.chinese}', _query)) continue;
      final String id = phrase.episodeId ?? '';
      final String scene = id.startsWith('scene:') || phrase.course == '数字人识物'
          ? '拍照'
          : id.startsWith('reading:') || phrase.course.startsWith('阅读')
          ? '阅读'
          : id.isNotEmpty
          ? '视频'
          : '其他';
      if (!_matchesSource(scene, '${phrase.course} ${phrase.episode}'))
        continue;
      final DateTime? date = DateTime.tryParse(phrase.collectedAt ?? '');
      if (!_matchesDate(date)) continue;
      items.add((
        title: phrase.english,
        translation: phrase.chinese,
        kind: kind,
        source: [
          phrase.course,
          phrase.episode,
        ].where((name) => name.isNotEmpty).join(' · '),
        date: date,
        word: null,
      ));
    }
    items.sort(
      (a, b) => (b.date?.millisecondsSinceEpoch ?? 0).compareTo(
        a.date?.millisecondsSinceEpoch ?? 0,
      ),
    );

    final MaterialLocalizations locale = MaterialLocalizations.of(context);
    return PadScaffold(
      currentDestination: AppNavDestination.home,
      topBar: PadTopBar(title: '收藏词本', description: '单词、短语和句子'),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.isEmpty ? 2 : items.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    labelText: '搜单词、短语或句子',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                TextField(
                  onChanged: (value) => setState(() => _sourceQuery = value),
                  decoration: const InputDecoration(
                    labelText: '按来源名称搜索',
                    hintText: '输入部分视频名或文章名',
                    prefixIcon: Icon(Icons.video_library_outlined),
                  ),
                ),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    DropdownButton<String>(
                      value: _kind,
                      onChanged: (value) => setState(() => _kind = value!),
                      items: [
                        for (final label in ['全部', '单词', '短语', '句子'])
                          DropdownMenuItem(value: label, child: Text(label)),
                      ],
                    ),
                    DropdownButton<String>(
                      value: _scene,
                      onChanged: (value) => setState(() => _scene = value!),
                      items: [
                        for (final label in [
                          '全部场景',
                          '拍照',
                          '视频',
                          '阅读',
                          '书籍',
                          '其他',
                        ])
                          DropdownMenuItem(value: label, child: Text(label)),
                      ],
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.date_range, size: 16),
                      label: Text(
                        _range == null
                            ? '收藏时间'
                            : '${locale.formatShortDate(_range!.start)} – ${locale.formatShortDate(_range!.end)}',
                      ),
                      onPressed: _pickDateRange,
                    ),
                    if (_range != null)
                      IconButton(
                        tooltip: '清除时间筛选',
                        onPressed: () => setState(() => _range = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                Text('${items.length} 条收藏'),
                const SizedBox(height: 8),
              ],
            );
          }
          if (items.isEmpty) return const ListTile(title: Text('没有匹配的收藏'));
          final _SavedItem item = items[index - 1];
          return Card(
            child: ListTile(
              title: Text(item.title),
              subtitle: Text(
                <String>[
                  if (item.translation.isNotEmpty) item.translation,
                  [
                    if (item.source.isNotEmpty) item.source,
                    if (item.date != null)
                      locale.formatShortDate(item.date!.toLocal()),
                  ].join(' · '),
                ].where((line) => line.isNotEmpty).join('\n'),
              ),
              trailing: Text(item.kind),
              onTap: () {
                if (item.word != null) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          FavoriteWordDetailScreen(word: item.word!),
                    ),
                  );
                } else {
                  showDialog<void>(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      title: Text(item.kind),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          [
                            item.title,
                            item.translation,
                            item.source,
                          ].where((line) => line.isNotEmpty).join('\n\n'),
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}

typedef _SavedItem = ({
  String title,
  String translation,
  String kind,
  String source,
  DateTime? date,
  String? word,
});

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
                '见过 $scenes 个场景',
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
