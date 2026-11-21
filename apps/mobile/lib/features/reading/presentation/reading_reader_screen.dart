import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';
import '../../sync/data/acquire_api_client.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../daily_review/data/word_encounter_store.dart';
import '../../daily_review/presentation/foundation_media_video_sheet.dart';
import '../../learning_modules/assessment_panel.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/presentation/widgets/ai_grammar_analysis_sheet.dart';
import '../../player/presentation/widgets/subtitle_chunk_highlight.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import '../../shared/data/word_pronunciation_service.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../../shared/presentation/word_lookup_popup.dart';
import '../../words/data/offline_word_dictionary.dart';
import '../../words/domain/foundation_media.dart';
import '../../words/presentation/foundation_media_provider.dart';
import '../../words/presentation/learned_vocabulary_provider.dart';
import '../../words/presentation/vocab_preview_sheet.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/reading_continuous_tts.dart';
import '../data/reading_gloss.dart';
import '../data/reading_tts.dart';
import '../data/reading_vocab_lists.dart';
import '../domain/reading_doc.dart';
import '../domain/reading_study_mode.dart';
import 'content_media_provider.dart';
import 'reading_chunk_provider.dart';
import 'reading_digital_human_ball.dart';
import 'reading_library_provider.dart';
import 'reading_text_spans.dart';
import 'reading_vocab_lists_sheet.dart';

const String kReadingSlowModeKey = 'reading_slow_mode_v1';
const String kReadingSoeEnabledKey = 'reading_soe_enabled_v1';

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
  ReadingStudyMode _mode = ReadingStudyMode.immersion;
  bool _sentenceTranslate = false;
  int _freqThreshold = kReadingDefaultFreqThreshold;
  Timer? _saveDebounce;
  bool _opened = false;
  bool _playingRemote = false;
  bool _speakingSentence = false;
  bool _continuousPlaying = false;
  bool _slowMode = false;
  bool _soeEnabled = false;
  ReadingTtsGender _ttsGender = ReadingTtsGender.female;
  int? _highlightWordIndex;
  int _continuousGeneration = 0;
  Player? _readingAudio;
  Completer<void>? _readingDone;
  String? _glossDocId;
  int _glossThreshold = -1;
  int _glossListsSig = -1;
  Map<String, String> _hardGlosses = const <String, String>{};
  bool _glossLoading = false;
  double? _unknownRate;
  String _focusedSentence = '';
  int _pageIndex = 0;
  String? _pagedDocId;
  List<String> _pages = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  void _ensurePages(ReadingDoc doc) {
    if (_pagedDocId == doc.id && _pages.isNotEmpty) return;
    _pagedDocId = doc.id;
    _pages = splitReadingPages(doc.plainText);
    final ReadingProgress? progress = ref
        .read(readingLibraryProvider)
        .progressFor(doc.id);
    if (progress != null && doc.plainText.isNotEmpty) {
      final int offset = progress.offsetChars.clamp(0, doc.plainText.length);
      int acc = 0;
      int page = 0;
      for (int i = 0; i < _pages.length; i++) {
        acc += _pages[i].length;
        if (offset <= acc) {
          page = i;
          break;
        }
        page = i;
      }
      _pageIndex = page.clamp(0, _pages.length - 1);
    } else {
      _pageIndex = 0;
    }
  }

  String get _pageText {
    if (_pages.isEmpty) return '';
    return _pages[_pageIndex.clamp(0, _pages.length - 1)];
  }

  int get _pageBaseOffset {
    int offset = 0;
    final int end = _pageIndex.clamp(0, _pages.length);
    for (int i = 0; i < end; i++) {
      offset += _pages[i].length;
    }
    return offset;
  }

  void _loadPrefs() {
    if (!Hive.isBoxOpen('prefs')) return;
    final Box<String> prefs = Hive.box<String>('prefs');
    _mode = ReadingStudyModeX.fromStorage(prefs.get(kReadingStudyModeKey));
    // Migrate legacy chinese toggle if mode key missing.
    if (prefs.get(kReadingStudyModeKey) == null) {
      final String? legacy = prefs.get('reading_show_inline_chinese_v1');
      if (legacy == '1') {
        _mode = ReadingStudyMode.intensive;
      } else if (legacy == '0') {
        _mode = ReadingStudyMode.immersion;
      }
    }
    _sentenceTranslate = prefs.get(kReadingSentenceTranslateKey) == '1';
    _slowMode = prefs.get(kReadingSlowModeKey) == '1';
    _soeEnabled = prefs.get(kReadingSoeEnabledKey) == '1';
    _ttsGender = ReadingTtsGenderX.fromStorage(prefs.get(kReadingTtsGenderKey));
    final int? thr = int.tryParse(prefs.get(kReadingFreqThresholdKey) ?? '');
    if (thr != null && kReadingFreqThresholdBands.contains(thr)) {
      _freqThreshold = thr;
    }
  }

  @override
  void dispose() {
    _continuousGeneration += 1;
    if (_readingDone?.isCompleted == false) _readingDone!.complete();
    unawaited(_readingAudio?.stop());
    _saveDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _persistPrefs() async {
    if (!Hive.isBoxOpen('prefs')) return;
    final Box<String> prefs = Hive.box<String>('prefs');
    await prefs.put(kReadingStudyModeKey, _mode.storageValue);
    await prefs.put(
      kReadingSentenceTranslateKey,
      _sentenceTranslate ? '1' : '0',
    );
    await prefs.put(kReadingFreqThresholdKey, '$_freqThreshold');
    await prefs.put(kReadingSlowModeKey, _slowMode ? '1' : '0');
    await prefs.put(kReadingSoeEnabledKey, _soeEnabled ? '1' : '0');
    await prefs.put(kReadingTtsGenderKey, _ttsGender.storageValue);
  }

  Future<void> _speakReading(String text, {double? rate}) async {
    try {
      await speakReadingText(
        ref,
        text,
        rate: rate ?? _effectiveRate,
        gender: _ttsGender,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('阿里云朗读暂不可用，请检查登录与网络后重试')),
      );
    }
  }

  Future<void> _toggleTtsGender() async {
    final selected = await showModalBottomSheet<ReadingTtsGender>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final voice in ReadingTtsGender.values)
                ListTile(
                  title: Text(voice.labelCn),
                  trailing: voice == _ttsGender
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(context, voice),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    await _stopContinuous();
    if (!mounted) return;
    setState(() => _ttsGender = selected);
    await saveReadingTtsGender(selected);
  }

  double get _effectiveRate {
    final double base = ref.read(learningSettingsProvider).ttsRate;
    return _slowMode ? (base * 0.55).clamp(0.5, 1.0) : base.clamp(0.5, 1.8);
  }

  Future<void> _stopContinuous() async {
    _continuousGeneration += 1;
    if (_readingDone?.isCompleted == false) _readingDone!.complete();
    unawaited(_readingAudio?.stop());
    await ref.read(wordPronunciationServiceProvider).stop();
    if (!mounted) return;
    setState(() {
      _continuousPlaying = false;
      _highlightWordIndex = null;
    });
  }

  Future<void> _playContinuous(ReadingDoc doc) async {
    if (_continuousPlaying) {
      await _stopContinuous();
      return;
    }
    final int generation = ++_continuousGeneration;
    final List<ReadingSpeakUnit> units = splitReadingSpeakUnits(doc.plainText);
    if (units.isEmpty) return;
    setState(() => _continuousPlaying = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('正在生成朗读音频…首句稍候，后续句会预取'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    final double rate = _effectiveRate;
    final String voiceId = _ttsGender.aliyunVoiceId;
    final player = Player();
    _readingAudio = player;
    Future<String>? prefetch;
    try {
      for (int i = 0; i < units.length; i++) {
        if (!mounted || generation != _continuousGeneration) return;
        final ReadingSpeakUnit unit = units[i];
        final Future<String> urlFuture =
            prefetch ??
            ref
                .read(acquireApiClientProvider)
                .readingSpeech(unit.text, voiceId);
        // Prefetch next sentence while this one plays (same-text requests coalesce).
        prefetch = i + 1 < units.length
            ? ref
                  .read(acquireApiClientProvider)
                  .readingSpeech(units[i + 1].text, voiceId)
            : null;
        final String url = await urlFuture;
        if (!mounted || generation != _continuousGeneration) return;
        final done = Completer<void>();
        _readingDone = done;
        final completed = player.stream.completed.listen((value) {
          if (value && !done.isCompleted) done.complete();
        });
        final errors = player.stream.error.listen((error) {
          if (!done.isCompleted) done.completeError(StateError(error));
        });
        final position = player.stream.position.listen((position) {
          if (!mounted || generation != _continuousGeneration) {
            if (!done.isCompleted) done.complete();
            return;
          }
          final duration = player.state.duration.inMilliseconds;
          if (duration <= 0) return;
          // Relative word positions are estimated within the real audio duration.
          final local = (position.inMilliseconds / duration * unit.wordCount)
              .floor()
              .clamp(0, unit.wordCount - 1);
          setState(() => _highlightWordIndex = unit.firstWordIndex + local);
        });
        try {
          await player.open(Media(url));
          await player.setRate(rate);
          await done.future.timeout(const Duration(minutes: 3));
        } finally {
          if (identical(_readingDone, done)) _readingDone = null;
          await completed.cancel();
          await errors.cancel();
          await position.cancel();
        }
      }
    } catch (_) {
      if (mounted && generation == _continuousGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('阿里云朗读暂不可用，请检查网络后重试')));
      }
    } finally {
      if (identical(_readingAudio, player)) _readingAudio = null;
      await player.dispose();
      if (mounted && generation == _continuousGeneration) {
        setState(() {
          _continuousPlaying = false;
          _highlightWordIndex = null;
        });
      }
    }
  }

  Future<void> _openMouthVideo(String lexeme) async {
    final FoundationMediaManifest manifest = await ref.read(
      foundationMediaManifestProvider.future,
    );
    final String key = normalizeWord(lexeme);
    FoundationMediaItem? hit;
    for (final String book in const <String>[
      'foundation_ipa_48',
      'foundation_phonics',
      'phonics_jolly',
      'ipa',
    ]) {
      hit = manifest.lookup(book, key);
      if (hit?.hasVideo ?? false) break;
      hit = null;
    }
    // Fall back: any item whose key matches.
    if (hit == null) {
      final String want = FoundationMediaManifest.normKey(key);
      for (final FoundationMediaItem item in manifest.items) {
        if (FoundationMediaManifest.normKey(item.key) == want &&
            item.hasVideo) {
          hit = item;
          break;
        }
      }
    }
    if (!mounted) return;
    if (hit == null || !(hit.hasVideo)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无该词/音素的口型视频（需已上传到服务器）')));
      return;
    }
    await showFoundationMediaVideoSheet(
      context,
      title: '口型示范 · $key',
      videoUrl: hit.videoUrl!,
    );
  }

  int _listsSignature(ReadingVocabLists lists, Set<String> learned) {
    final List<String> knownSorted = lists.known.toList()..sort();
    final List<String> focusSorted = lists.focus.toList()..sort();
    return Object.hash(
      Object.hashAll(knownSorted),
      Object.hashAll(focusSorted),
      learned.length,
    );
  }

  Future<void> _ensureGlosses(ReadingDoc doc) async {
    final ReadingVocabLists lists = ref.read(readingVocabListsProvider);
    final Set<String> learned = ref.read(learnedVocabularyProvider);
    final int listsSig = _listsSignature(lists, learned);
    if (_glossDocId == doc.id &&
        _glossThreshold == _freqThreshold &&
        _glossListsSig == listsSig) {
      return;
    }
    _glossDocId = doc.id;
    _glossThreshold = _freqThreshold;
    _glossListsSig = listsSig;
    if (mounted) setState(() => _glossLoading = true);
    try {
      final ReadingFrequencyLexicon lexicon = await ref.read(
        readingFrequencyLexiconProvider.future,
      );
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      final Set<String> known = effectiveKnownWords(
        lists: lists,
        learned: learned,
      );
      // Gloss against the visible page only — full novels are too large.
      _ensurePages(doc);
      final List<String> tokens = extractReadingWordTokens(_pageText);
      final Map<String, String> glosses = await buildHardWordGlosses(
        words: tokens.toSet(),
        lexicon: lexicon,
        dictionary: dictionary,
        threshold: _freqThreshold,
        known: known,
        focus: lists.focus,
      );
      final double rate = unknownWordRate(
        words: tokens,
        lexicon: lexicon,
        threshold: _freqThreshold,
        known: known,
        focus: lists.focus,
      );
      if (!mounted || _glossDocId != doc.id) return;
      setState(() {
        _hardGlosses = glosses;
        _unknownRate = rate;
        _glossLoading = false;
      });
    } catch (_) {
      if (!mounted || _glossDocId != doc.id) return;
      setState(() {
        _hardGlosses = const <String, String>{};
        _unknownRate = null;
        _glossLoading = false;
      });
    }
  }

  Future<void> _playRemoteAudio(FoundationMediaItem item) async {
    final String? url = item.audioUrl;
    if (url == null || url.isEmpty || _playingRemote) return;
    setState(() => _playingRemote = true);
    try {
      await ref
          .read(wordPronunciationServiceProvider)
          .speak(item.key, recordedUrl: url, allowSynthesisFallback: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('朗读音频暂不可用（需已上传到服务器）')));
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
        ref
            .read(readingLibraryProvider.notifier)
            .updateProgress(
              docId: doc.id,
              offsetChars: (percent * doc.plainText.length).round(),
              percent: percent,
            ),
      );
    });
  }

  Future<void> _recordLearnedContext(String rawWord, String sentence) async {
    final String word = normalizeWord(rawWord);
    if (word.isEmpty || sentence.trim().isEmpty) return;
    try {
      await WordEncounterStore(
        account: ref.read(studyAccountProvider),
      ).recordContext(word, sentence);
    } catch (_) {}
  }

  Future<String> _translateSentenceQuiet(String sentence) async {
    final String text = sentence.trim();
    if (text.isEmpty) return '';
    try {
      final String? zh = await ref
          .read(wordLookupServiceProvider)
          .translateSentence(
            sentence: text,
            settings: ref.read(learningSettingsProvider),
          )
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      return (zh ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _favoriteFromReading({
    required ReadingDoc doc,
    required String lexeme,
    required String sentence,
    String? definitionCn,
  }) async {
    final String chinese = await _translateSentenceQuiet(sentence);
    if (!mounted) return;
    final bool ok = ref.read(wordBookProvider.notifier).addFavoriteWord(
          rawWord: lexeme,
          episodeId: doc.episodeId ?? 'reading:${doc.id}',
          course: '阅读 · ${doc.title}',
          episode: doc.episodeTitle.isEmpty ? doc.title : doc.episodeTitle,
          time: '',
          lineKey: 'reading:${doc.id}:$lexeme',
          sentence: sentence,
          chinese: chinese,
          generatedDefinition: (definitionCn ?? '').trim().isEmpty
              ? null
              : definitionCn!.trim(),
        );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法加入：$lexeme')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已收藏 $lexeme · 正在生成 AI 解析')),
    );
    await showVocabPreviewSheet(context, word: lexeme);
  }

  Future<void> _pauseReadingForLookup() async {
    // Opening a word/sentence card should not compete with continuous TTS.
    await _stopContinuous();
    if (_speakingSentence && mounted) {
      setState(() => _speakingSentence = false);
    }
  }

  Future<void> _showLookupCard({
    required ReadingDoc doc,
    required String rawLexeme,
    required String sentence,
  }) async {
    final String lexeme = rawLexeme.trim();
    if (lexeme.length < 2) return;
    await _pauseReadingForLookup();
    if (!mounted) return;
    if (sentence.trim().isNotEmpty) {
      setState(() => _focusedSentence = sentence.trim());
    }
    unawaited(_recordLearnedContext(lexeme, sentence));
    if (!mounted) return;
    final String fallback =
        _hardGlosses[normalizeWord(lexeme)] ??
        _hardGlosses[lexeme.toLowerCase()] ??
        '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        final double maxH = MediaQuery.sizeOf(ctx).height * 0.62;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              MediaQuery.paddingOf(ctx).bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    TextButton.icon(
                      onPressed: () {
                        unawaited(
                          _speakReading(
                            lexeme,
                            rate: (_effectiveRate * 0.7).clamp(0.5, 1.0),
                          ),
                        );
                      },
                      icon: const Icon(Icons.slow_motion_video_rounded),
                      label: const Text('慢读'),
                    ),
                    TextButton.icon(
                      onPressed: () => unawaited(_openMouthVideo(lexeme)),
                      icon: const Icon(Icons.face_retouching_natural_outlined),
                      label: const Text('口型'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        unawaited(
                          ref
                              .read(readingVocabListsProvider.notifier)
                              .markKnown(lexeme),
                        );
                        setState(() => _glossDocId = null);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已加入白名单：$lexeme')),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('已会'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        unawaited(
                          ref
                              .read(readingVocabListsProvider.notifier)
                              .markFocus(lexeme),
                        );
                        setState(() => _glossDocId = null);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已加入黑名单：$lexeme')),
                        );
                      },
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('生词'),
                    ),
                  ],
                ),
                WordLookupPopupCard(
                  rawWord: lexeme,
                  contextSentence: sentence,
                  episodeId: doc.episodeId ?? 'reading:${doc.id}',
                  fallbackDefinitionCn: fallback.isEmpty ? null : fallback,
                  maxHeight: maxH,
                  onClose: () => Navigator.pop(ctx),
                  // Side-effect only: card already speaks via WordPronunciationService.
                  // Calling _speakReading here doubled audio (CosyVoice + dictionary TTS).
                  onPronounce: () {
                    unawaited(
                      ref.read(wordPronunciationServiceProvider).stop(),
                    );
                  },
                  onFavorite: (String? definitionCn) {
                    Navigator.pop(ctx);
                    unawaited(
                      _favoriteFromReading(
                        doc: doc,
                        lexeme: lexeme,
                        sentence: sentence,
                        definitionCn: definitionCn,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSentenceLongPress({
    required ReadingDoc doc,
    required int start,
    required int end,
  }) async {
    final ({int start, int end, String text}) bounds = sentenceBounds(
      doc.plainText,
      start,
      end,
    );
    final String sentence = bounds.text;
    if (sentence.isEmpty) return;
    await _pauseReadingForLookup();
    if (!mounted) return;
    setState(() => _focusedSentence = sentence);

    String? zh;
    if (_sentenceTranslate) {
      try {
        zh = await ref
            .read(wordLookupServiceProvider)
            .translateSentence(
              sentence: sentence,
              settings: ref.read(learningSettingsProvider),
            );
      } catch (_) {
        zh = null;
      }
    }
    if (!mounted) return;

    // Auto-speak when long-pressing a sentence.
    unawaited(() async {
      if (!mounted) return;
      setState(() => _speakingSentence = true);
      try {
        await _speakReading(sentence);
      } finally {
        if (mounted) setState(() => _speakingSentence = false);
      }
    }());

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
              const Text(
                '整句',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                sentence,
                style: const TextStyle(height: 1.45, fontSize: 16),
              ),
              if ((zh ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  zh!.trim(),
                  style: const TextStyle(
                    height: 1.4,
                    fontSize: 15,
                    color: Color(0xFF4A4A52),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _speakingSentence
                    ? null
                    : () async {
                        setState(() => _speakingSentence = true);
                        try {
                          await _speakReading(sentence);
                        } finally {
                          if (mounted) {
                            setState(() => _speakingSentence = false);
                          }
                        }
                      },
                icon: Icon(
                  _speakingSentence
                      ? Icons.hourglass_top_rounded
                      : Icons.volume_up_rounded,
                ),
                label: Text(_speakingSentence ? '朗读中…' : '再读一遍'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppDesignTokens.brandGreenDark,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  final bool next = !_sentenceTranslate;
                  setState(() => _sentenceTranslate = next);
                  unawaited(_persistPrefs());
                  Navigator.pop(ctx);
                  if (next) {
                    unawaited(
                      _onSentenceLongPress(doc: doc, start: start, end: end),
                    );
                  }
                },
                child: Text(_sentenceTranslate ? '句译：开（点此关闭）' : '句译：关（点此开启）'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  unawaited(
                    showAiGrammarAnalysisSheet(
                      context,
                      english: sentence,
                      chinese: (zh ?? '').trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('句子语法解析'),
              ),
              if (_soeEnabled) ...<Widget>[
                const SizedBox(height: 12),
                AssessmentPanel(reference: sentence),
              ] else
                TextButton(
                  onPressed: () {
                    setState(() => _soeEnabled = true);
                    unawaited(_persistPrefs());
                    Navigator.pop(ctx);
                    unawaited(
                      _onSentenceLongPress(doc: doc, start: start, end: end),
                    );
                  },
                  child: const Text('开启跟读评测（可选）'),
                ),
            ],
          ),
        );
      },
    );
  }

  void _addHardWordsToBook(ReadingDoc doc) {
    int added = 0;
    final List<String> enrolled = <String>[];
    for (final MapEntry<String, String> e in _hardGlosses.entries.take(25)) {
      final bool ok = ref
          .read(wordBookProvider.notifier)
          .addFavoriteWord(
            rawWord: e.key,
            episodeId: doc.episodeId ?? 'reading:${doc.id}',
            course: '阅读难词 · ${doc.title}',
            episode: doc.title,
            time: '',
            lineKey: 'reading:${doc.id}:hard:${e.key}',
            sentence: '',
            chinese: e.value,
            generatedDefinition: e.value,
          );
      if (ok) {
        added += 1;
        if (ref.read(wordBookProvider.notifier).enrollForReview(e.key)) {
          enrolled.add(e.key);
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0
              ? '没有可加入的难词'
              : '已加入 $added 个难词到复习'
                  '${enrolled.isEmpty ? '' : '（${enrolled.length} 个已入队）'}',
        ),
      ),
    );
  }

  void _openFreqSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModal) {
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
                  const Text(
                    '自动生词阈值',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '高亮 / 词下中文：词频排名 > $_freqThreshold',
                    style: const TextStyle(color: Color(0xFF626262)),
                  ),
                  Slider(
                    value: kReadingFreqThresholdBands
                        .indexOf(_freqThreshold)
                        .clamp(0, kReadingFreqThresholdBands.length - 1)
                        .toDouble(),
                    min: 0,
                    max: (kReadingFreqThresholdBands.length - 1).toDouble(),
                    divisions: kReadingFreqThresholdBands.length - 1,
                    label: '$_freqThreshold',
                    onChanged: (double v) {
                      final int next = kReadingFreqThresholdBands[v.round()];
                      setModal(() => _freqThreshold = next);
                      setState(() {
                        _freqThreshold = next;
                        _glossDocId = null;
                      });
                      unawaited(_persistPrefs());
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final int band in kReadingFreqThresholdBands)
                        ChoiceChip(
                          label: Text('${band ~/ 1000}k'),
                          selected: _freqThreshold == band,
                          onSelected: (_) {
                            setModal(() => _freqThreshold = band);
                            setState(() {
                              _freqThreshold = band;
                              _glossDocId = null;
                            });
                            unawaited(_persistPrefs());
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      unawaited(showReadingVocabListsSheet(context, ref));
                    },
                    icon: const Icon(Icons.rule_folder_outlined),
                    label: const Text('管理黑白名单'),
                  ),
                ],
              ),
            );
          },
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
    _ensurePages(doc);
    if (!_opened) {
      _opened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          ref.read(readingLibraryProvider.notifier).touchOpened(doc.id),
        );
        if (_scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      });
    }
    unawaited(_ensureGlosses(doc));

    final bool showChinese = _mode.showInlineChinese;
    final Color bg = readingBackgroundColor(_dark);
    final Color fg = readingForegroundColor(_dark);
    final AsyncValue<FoundationMediaManifest> mediaAsync = ref.watch(
      readingContentMediaProvider,
    );
    final FoundationMediaItem? remoteMedia = mediaAsync.maybeWhen(
      data: (FoundationMediaManifest m) =>
          readingMediaForDoc(m, doc.id) ??
          readingMediaForDoc(m, doc.title) ??
          readingMediaForDoc(m, doc.sourceLabel),
      orElse: () => null,
    );
    final SubtitleChunkHighlighter? chunks = ref
        .watch(readingChunkHighlighterProvider)
        .asData
        ?.value;
    final Set<String> learned = ref.watch(learnedVocabularyProvider);
    final String rateLabel = _unknownRate == null
        ? ''
        : ' · 生词率 ${(_unknownRate! * 100).toStringAsFixed(1)}%';

    return PadScaffold(
      currentDestination: AppNavDestination.reading,
      showContinueLearning: false,
      showNavigation: false,
      topBar: PadTopBar(
        title: doc.title,
        trailing: const SizedBox.shrink(),
        description: _mode == ReadingStudyMode.immersion
            ? '沉浸 · ${_ttsGender.labelCn} · 连续朗读${_slowMode ? ' · 慢读' : ''}$rateLabel'
            : '精读 · ${_ttsGender.labelCn} · 难词(>$_freqThreshold)${_slowMode ? ' · 慢读' : ''}$rateLabel',
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          IconButton(
            tooltip: '选择朗读音色（当前：${_ttsGender.labelCn}）',
            onPressed: () => unawaited(_toggleTtsGender()),
            icon: Icon(
              _ttsGender == ReadingTtsGender.female ||
                      _ttsGender == ReadingTtsGender.luna ||
                      _ttsGender == ReadingTtsGender.nora ||
                      _ttsGender == ReadingTtsGender.ivy
                  ? Icons.woman_rounded
                  : Icons.man_rounded,
              color: AppDesignTokens.brandGreenDark,
            ),
          ),
          IconButton(
            tooltip: _continuousPlaying ? '停止朗读' : '连续朗读',
            onPressed: () => unawaited(_playContinuous(doc)),
            icon: Icon(
              _continuousPlaying
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline_rounded,
              color: _continuousPlaying ? AppDesignTokens.brandGreenDark : null,
            ),
          ),
          IconButton(
            tooltip: _mode == ReadingStudyMode.immersion ? '切换精读' : '切换沉浸',
            onPressed: () {
              setState(() {
                _mode = _mode == ReadingStudyMode.immersion
                    ? ReadingStudyMode.intensive
                    : ReadingStudyMode.immersion;
              });
              unawaited(_persistPrefs());
            },
            icon: Icon(
              _mode == ReadingStudyMode.immersion
                  ? Icons.menu_book_outlined
                  : Icons.auto_stories_rounded,
              color: _mode == ReadingStudyMode.intensive
                  ? AppDesignTokens.brandGreenDark
                  : null,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (String value) {
              switch (value) {
                case 'voice_female':
                  setState(() => _ttsGender = ReadingTtsGender.female);
                  unawaited(saveReadingTtsGender(_ttsGender));
                case 'voice_male':
                  setState(() => _ttsGender = ReadingTtsGender.male);
                  unawaited(saveReadingTtsGender(_ttsGender));
                case 'slow':
                  setState(() => _slowMode = !_slowMode);
                  unawaited(_persistPrefs());
                case 'freq':
                  _openFreqSheet();
                case 'hard':
                  _addHardWordsToBook(doc);
                case 'remote':
                  if (remoteMedia != null) {
                    unawaited(_playRemoteAudio(remoteMedia));
                  }
                case 'lists':
                  unawaited(showReadingVocabListsSheet(context, ref));
                case 'font':
                  setState(() {
                    _fontSize = _fontSize >= 24 ? 18 : _fontSize + 2;
                  });
                case 'theme':
                  setState(() => _dark = !_dark);
                case 'episode':
                  if ((doc.episodeId ?? '').isNotEmpty) {
                    context.push(
                      '/episodes/${Uri.encodeComponent(doc.episodeId!)}',
                    );
                  }
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'voice_female',
                child: Text(
                  _ttsGender == ReadingTtsGender.female
                      ? '女声 · 龙安风悦（当前）'
                      : '女声 · 龙安风悦',
                ),
              ),
              PopupMenuItem<String>(
                value: 'voice_male',
                child: Text(
                  _ttsGender == ReadingTtsGender.male
                      ? '男声 · 龙书（当前）'
                      : '男声 · 龙书',
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'slow',
                child: Text(_slowMode ? '关闭慢读' : '慢读模式'),
              ),
              const PopupMenuItem<String>(
                value: 'freq',
                child: Text('词频阈值 / 名单'),
              ),
              const PopupMenuItem<String>(value: 'lists', child: Text('黑白名单')),
              if (_hardGlosses.isNotEmpty)
                const PopupMenuItem<String>(
                  value: 'hard',
                  child: Text('难词进词书'),
                ),
              if (remoteMedia?.hasAudio ?? false)
                PopupMenuItem<String>(
                  value: 'remote',
                  enabled: !_playingRemote,
                  child: Text(_playingRemote ? '朗读中…' : '服务器朗读'),
                ),
              const PopupMenuItem<String>(value: 'font', child: Text('字号')),
              PopupMenuItem<String>(
                value: 'theme',
                child: Text(_dark ? '浅色' : '深色'),
              ),
              if (doc.sourceType == ReadingSourceType.video &&
                  (doc.episodeId ?? '').isNotEmpty)
                const PopupMenuItem<String>(
                  value: 'episode',
                  child: Text('打开原集'),
                ),
            ],
          ),
        ],
      ),
      body: ReadingDigitalHumanBallHost(
        doc: doc,
        focusedSentence: _focusedSentence,
        child: ColoredBox(
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
                  Text(
                    doc.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      height: 1.25,
                      fontFamily: 'Georgia',
                      color: fg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${doc.level} · ${doc.wordCount} words',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_mode.showChunkLegend || showChinese)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          if (_mode.showChunkLegend) ...<Widget>[
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
                          ],
                          Text(
                            showChinese
                                ? (_glossLoading
                                      ? '难词释义加载中…'
                                      : '词下灰字 = 词频>$_freqThreshold · 双击语块 · 长按整句')
                                : '沉浸模式 · 点词/双击语块/长按整句',
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
                  if (_pages.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: <Widget>[
                          TextButton(
                            onPressed: _pageIndex <= 0
                                ? null
                                : () {
                                    setState(() {
                                      _pageIndex -= 1;
                                      _glossDocId = null;
                                    });
                                    if (_scroll.hasClients) {
                                      _scroll.jumpTo(0);
                                    }
                                    unawaited(_ensureGlosses(doc));
                                    unawaited(
                                      ref
                                          .read(readingLibraryProvider.notifier)
                                          .updateProgress(
                                            docId: doc.id,
                                            offsetChars: _pageBaseOffset,
                                            percent: (_pageIndex + 1) /
                                                _pages.length,
                                          ),
                                    );
                                  },
                            child: const Text('上一节'),
                          ),
                          Expanded(
                            child: Text(
                              '第 ${_pageIndex + 1} / ${_pages.length} 节',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _dark
                                    ? const Color(0xFF9A9AA2)
                                    : const Color(0xFF6B6B76),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _pageIndex >= _pages.length - 1
                                ? null
                                : () {
                                    setState(() {
                                      _pageIndex += 1;
                                      _glossDocId = null;
                                    });
                                    if (_scroll.hasClients) {
                                      _scroll.jumpTo(0);
                                    }
                                    unawaited(_ensureGlosses(doc));
                                    unawaited(
                                      ref
                                          .read(readingLibraryProvider.notifier)
                                          .updateProgress(
                                            docId: doc.id,
                                            offsetChars: _pageBaseOffset,
                                            percent: (_pageIndex + 1) /
                                                _pages.length,
                                          ),
                                    );
                                  },
                            child: const Text('下一节'),
                          ),
                        ],
                      ),
                    ),
                  Text.rich(
                    TextSpan(
                      children: buildReadingTextSpans(
                        text: _pageText,
                        textColor: fg,
                        fontSize: _fontSize,
                        lineHeight: _lineHeight,
                        dark: _dark,
                        showChinese: showChinese,
                        showChunks: true,
                        learnedWords: learned,
                        hardGlosses: _hardGlosses,
                        chunkHighlighter: chunks,
                        onWordTap: (String word, int start, int end) {
                          final String sentence = sentenceBounds(
                            _pageText,
                            start,
                            end,
                          ).text;
                          unawaited(
                            _showLookupCard(
                              doc: doc,
                              rawLexeme: word,
                              sentence: sentence,
                            ),
                          );
                        },
                        onWordLongPress: (String word, int start, int end) {
                          unawaited(
                            _onSentenceLongPress(
                              doc: doc,
                              start: _pageBaseOffset + start,
                              end: _pageBaseOffset + end,
                            ),
                          );
                        },
                        onChunkDoubleTap: (String phrase, int start, int end) {
                          final String sentence = sentenceBounds(
                            _pageText,
                            start,
                            end,
                          ).text;
                          unawaited(
                            _showLookupCard(
                              doc: doc,
                              rawLexeme: phrase,
                              sentence: sentence,
                            ),
                          );
                        },
                        onChunkLongPress: (String phrase, int start, int end) {
                          unawaited(
                            _onSentenceLongPress(
                              doc: doc,
                              start: _pageBaseOffset + start,
                              end: _pageBaseOffset + end,
                            ),
                          );
                        },
                        highlightWordIndex: _highlightWordIndex,
                      ),
                    ),
                  ),
                ],
              ),
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
