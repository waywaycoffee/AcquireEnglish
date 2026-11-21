import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../daily_review/data/word_encounter_store.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/widgets/subtitle_chunk_highlight.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/domain/word_lookup_entry.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/domain/foundation_media.dart';
import '../../words/presentation/learned_vocabulary_provider.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/reading_gloss.dart';
import '../domain/reading_doc.dart';
import 'content_media_provider.dart';
import 'reading_chunk_provider.dart';
import 'reading_library_provider.dart';
import 'reading_text_spans.dart';

const String kReadingShowChineseKey = 'reading_show_inline_chinese_v1';

class ReadingReaderScreen extends ConsumerStatefulWidget {
  const ReadingReaderScreen({required this.docId, super.key});

  final String docId;

  @override
  ConsumerState<ReadingReaderScreen> createState() =>
      _ReadingReaderScreenState();
}

class _ReadingReaderScreenState extends ConsumerState<ReadingReaderScreen> {
  final ScrollController _scroll = ScrollController();
  double _fontSize = 20;
  final double _lineHeight = 1.7;
  bool _dark = false;
  bool _showChinese = true;
  Timer? _saveDebounce;
  bool _opened = false;
  bool _playingRemote = false;
  String? _glossDocId;
  Map<String, String> _hardGlosses = const <String, String>{};
  bool _glossLoading = false;

  @override
  void initState() {
    super.initState();
    if (Hive.isBoxOpen('prefs')) {
      final String? stored = Hive.box<String>('prefs').get(kReadingShowChineseKey);
      if (stored == '0') {
        _showChinese = false;
      } else if (stored == '1') {
        _showChinese = true;
      }
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _persistShowChinese() async {
    if (!Hive.isBoxOpen('prefs')) return;
    await Hive.box<String>('prefs').put(
      kReadingShowChineseKey,
      _showChinese ? '1' : '0',
    );
  }

  Future<void> _ensureGlosses(ReadingDoc doc) async {
    if (_glossDocId == doc.id) return;
    _glossDocId = doc.id;
    if (mounted) setState(() => _glossLoading = true);
    try {
      final ReadingFrequencyLexicon lexicon =
          await ref.read(readingFrequencyLexiconProvider.future);
      final OfflineWordDictionary dictionary =
          ref.read(offlineWordDictionaryProvider);
      final Map<String, String> glosses = await buildHardWordGlosses(
        words: extractReadingWords(doc.plainText),
        lexicon: lexicon,
        dictionary: dictionary,
      );
      if (!mounted || _glossDocId != doc.id) return;
      setState(() {
        _hardGlosses = glosses;
        _glossLoading = false;
      });
    } catch (_) {
      if (!mounted || _glossDocId != doc.id) return;
      setState(() {
        _hardGlosses = const <String, String>{};
        _glossLoading = false;
      });
    }
  }

  Future<void> _playRemoteAudio(FoundationMediaItem item) async {
    final String? url = item.audioUrl;
    if (url == null || url.isEmpty || _playingRemote) return;
    setState(() => _playingRemote = true);
    try {
      await ref.read(wordPronunciationServiceProvider).speak(
            item.key,
            recordedUrl: url,
            allowSynthesisFallback: false,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('朗读音频暂不可用（需已上传到服务器）')),
        );
      }
    } finally {
      if (mounted) setState(() => _playingRemote = false);
    }
  }

  void _scheduleProgressSave(ReadingDoc doc) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!_scroll.hasClients || !mounted) return;
      final double max = _scroll.position.maxScrollExtent;
      final double offset = _scroll.offset;
      final double percent = max <= 0 ? 1.0 : (offset / max).clamp(0.0, 1.0);
      unawaited(
        ref.read(readingLibraryProvider.notifier).updateProgress(
          docId: doc.id,
          offsetChars: (percent * doc.plainText.length).round(),
          percent: percent,
        ),
      );
    });
  }

  String _sentenceAround(String text, int start, int end) {
    int left = start;
    int right = end;
    while (left > 0 && !'.!?'.contains(text[left - 1])) {
      left--;
    }
    while (right < text.length && !'.!?'.contains(text[right])) {
      right++;
    }
    if (right < text.length) right++;
    return text.substring(left, right).trim();
  }

  Future<void> _onWordTap(ReadingDoc doc, String rawWord, String sentence) async {
    final String word = rawWord.toLowerCase().replaceAll(
      RegExp(r"[^a-z'-]"),
      '',
    );
    if (word.length < 2) return;
    final LearningSettingsState settings = ref.read(learningSettingsProvider);
    final bool learned = ref.read(learnedVocabularyProvider).contains(word);
    int? contexts;
    if (learned) {
      try {
        contexts = await WordEncounterStore(
          account: ref.read(studyAccountProvider),
        ).recordContext(word, sentence);
      } catch (_) {
        // Keep dictionary lookup available if the progress write fails.
      }
    }
    if (!mounted) return;
    WordLookupEntry? entry;
    try {
      entry = await ref
          .read(wordLookupServiceProvider)
          .lookupWord(
            rawWord: word,
            contextSentence: sentence,
            settings: settings,
          );
    } catch (_) {
      entry = null;
    }
    if (!mounted) return;
    final String gloss = entry?.definitionCn.trim() ??
        _hardGlosses[word] ??
        '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.paddingOf(ctx).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                word,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              if (contexts != null)
                Text('语境再遇 $contexts/${WordEncounterStore.contextGoal}'),
              if (entry?.phonetic.isNotEmpty ?? false)
                Text(
                  entry!.phonetic,
                  style: const TextStyle(color: Color(0xFF626262)),
                ),
              const SizedBox(height: 8),
              Text(
                gloss.isEmpty ? '暂无释义，仍可加入词书后复习。' : gloss,
                style: const TextStyle(height: 1.45, fontSize: 16),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  final bool ok = ref
                      .read(wordBookProvider.notifier)
                      .addFavoriteWord(
                        rawWord: word,
                        episodeId: doc.episodeId ?? 'reading:${doc.id}',
                        course: '阅读 · ${doc.title}',
                        episode: doc.episodeTitle.isEmpty
                            ? doc.title
                            : doc.episodeTitle,
                        time: '',
                        lineKey: 'reading:${doc.id}:$word',
                        sentence: sentence,
                        chinese: '',
                        generatedDefinition: gloss.isEmpty ? null : gloss,
                      );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(ok ? '已加入词书：$word' : '无法加入：$word'),
                    ),
                  );
                },
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('加入词书'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreenDark,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ReadingLibraryState library = ref.watch(readingLibraryProvider);
    final ReadingDoc? doc = library.docById(widget.docId);
    if (!library.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('阅读')),
        body: const Center(child: Text('找不到这篇读物')),
      );
    }
    if (!_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          ref.read(readingLibraryProvider.notifier).touchOpened(doc.id),
        );
        final ReadingProgress? p = library.progressFor(doc.id);
        if (p != null && p.percent > 0 && _scroll.hasClients) {
          final double max = _scroll.position.maxScrollExtent;
          _scroll.jumpTo((p.percent * max).clamp(0.0, max));
        }
      });
    }
    unawaited(_ensureGlosses(doc));

    final Color bg = _dark ? const Color(0xFF1C1C1E) : AppDesignTokens.appWhite;
    final Color fg = _dark ? const Color(0xFFF2F2F7) : AppDesignTokens.textPrimary;
    final AsyncValue<FoundationMediaManifest> mediaAsync =
        ref.watch(readingContentMediaProvider);
    final FoundationMediaItem? remoteMedia = mediaAsync.maybeWhen(
      data: (FoundationMediaManifest m) =>
          readingMediaForDoc(m, doc.id) ??
          readingMediaForDoc(m, doc.title) ??
          readingMediaForDoc(m, doc.sourceLabel),
      orElse: () => null,
    );
    final SubtitleChunkHighlighter? chunks =
        ref.watch(readingChunkHighlighterProvider).asData?.value;
    final Set<String> learned = ref.watch(learnedVocabularyProvider);

    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      showNavigation: false,
      topBar: PadTopBar(
        title: doc.title,
        description: _showChinese
            ? '语块高亮 · 难词中文（词频>3000）· 点词查义'
            : '语块高亮 · 中文已隐藏 · 点词查义',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          IconButton(
            tooltip: _showChinese ? '隐藏中文' : '显示中文',
            onPressed: () {
              setState(() => _showChinese = !_showChinese);
              unawaited(_persistShowChinese());
            },
            icon: Icon(
              Icons.translate_rounded,
              color: _showChinese ? AppDesignTokens.brandGreenDark : null,
            ),
          ),
          if (remoteMedia?.hasAudio ?? false)
            IconButton(
              tooltip: '播放服务器朗读',
              onPressed: _playingRemote
                  ? null
                  : () => unawaited(_playRemoteAudio(remoteMedia!)),
              icon: Icon(
                _playingRemote
                    ? Icons.hourglass_top_rounded
                    : Icons.volume_up_rounded,
              ),
            ),
          if (doc.sourceType == ReadingSourceType.video &&
              (doc.episodeId ?? '').isNotEmpty)
            TextButton(
              onPressed: () =>
                  context.push('/episodes/${Uri.encodeComponent(doc.episodeId!)}'),
              child: const Text('打开原集'),
            ),
          IconButton(
            tooltip: '字号',
            onPressed: () {
              setState(() {
                _fontSize = _fontSize >= 24 ? 18 : _fontSize + 2;
              });
            },
            icon: const Icon(Icons.format_size_rounded),
          ),
          IconButton(
            tooltip: _dark ? '浅色' : '深色',
            onPressed: () => setState(() => _dark = !_dark),
            icon: Icon(_dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
          ),
        ],
      ),
      body: ColoredBox(
        color: bg,
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
              _scheduleProgressSave(doc);
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _LegendChip(
                        color: SubtitleChunkHighlighter.legendColor(
                          SubtitleChunkKind.phrase,
                        ),
                        label: '词组',
                        dark: _dark,
                      ),
                      _LegendChip(
                        color: SubtitleChunkHighlighter.legendColor(
                          SubtitleChunkKind.chunk,
                        ),
                        label: '语块',
                        dark: _dark,
                      ),
                      _LegendChip(
                        color: SubtitleChunkHighlighter.legendColor(
                          SubtitleChunkKind.usage,
                        ),
                        label: '用法',
                        dark: _dark,
                      ),
                      Text(
                        _showChinese
                            ? (_glossLoading
                                ? '难词释义加载中…'
                                : '词下灰字 = 词频>$kReadingHardWordRankThreshold · 点翻译图标可隐藏')
                            : '中文已隐藏 · 再点翻译图标显示',
                        style: TextStyle(
                          fontSize: 12,
                          color: _dark
                              ? const Color(0xFF9A9AA2)
                              : const Color(0xFF6B6B76),
                        ),
                      ),
                    ],
                  ),
                ),
                Text.rich(
                  TextSpan(
                    children: buildReadingTextSpans(
                      text: doc.plainText,
                      textColor: fg,
                      fontSize: _fontSize,
                      lineHeight: _lineHeight,
                      dark: _dark,
                      showChinese: _showChinese,
                      learnedWords: learned,
                      hardGlosses: _hardGlosses,
                      chunkHighlighter: chunks,
                      onWordTap: (String word, int start, int end) {
                        unawaited(
                          _onWordTap(
                            doc,
                            word,
                            _sentenceAround(doc.plainText, start, end),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.label,
    required this.dark,
  });

  final Color color;
  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: dark ? const Color(0xFFF2F2F7) : const Color(0xFF2A2A32),
        ),
      ),
    );
  }
}
