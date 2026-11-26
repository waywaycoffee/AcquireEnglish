import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';
import '../../sync/data/acquire_api_client.dart';

import '../../authentication/presentation/account_storage.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../home/presentation/learning_dashboard_provider.dart';
import '../../daily_path/domain/course_plan.dart';
import '../../daily_path/domain/reading_course_splitter.dart';
import '../../daily_path/presentation/course_unit_quiz_screen.dart';
import '../../daily_path/presentation/enable_course_mode_sheet.dart';
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
import '../../words/presentation/learner_level_provider.dart';
import '../../words/presentation/vocab_preview_sheet.dart';
import '../../words/presentation/word_book_provider.dart';
import '../data/reading_continuous_tts.dart';
import '../data/reading_gloss.dart';
import '../data/reading_tts.dart';
import '../data/reading_vocab_lists.dart';
import '../domain/reading_doc.dart';
import '../domain/reading_study_mode.dart';
import 'content_media_provider.dart';
import 'reading_book_prep_provider.dart';
import 'reading_chunk_provider.dart';
import 'reading_digital_human_ball.dart';
import 'reading_library_provider.dart';
import 'reading_page_quiz.dart';
import 'reading_text_spans.dart';
import 'reading_vocab_lists_sheet.dart';

const String kReadingSlowModeKey = 'reading_slow_mode_v1';
const String kReadingSoeEnabledKey = 'reading_soe_enabled_v1';

class ReadingReaderScreen extends ConsumerStatefulWidget {
  const ReadingReaderScreen({required this.docId, this.initialOffset, super.key});

  final String docId;
  final int? initialOffset;

  @override
  ConsumerState<ReadingReaderScreen> createState() =>
      _ReadingReaderScreenState();
}

class _ReadingReaderScreenState extends ConsumerState<ReadingReaderScreen> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _articleTextKey = GlobalKey();

  void _scrollToArticleOffset(int offset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      RenderParagraph? paragraph;
      void findParagraph(RenderObject node) {
        if (node is RenderParagraph) {
          paragraph = node;
        } else if (paragraph == null) {
          node.visitChildren(findParagraph);
        }
      }
      final root = _articleTextKey.currentContext?.findRenderObject();
      if (root == null) return;
      findParagraph(root);
      final text = paragraph;
      if (text == null || offset < 0 || offset >= text.text.toPlainText().length) return;
      final boxes = text.getBoxesForSelection(
        TextSelection(baseOffset: offset, extentOffset: offset + 1),
      );
      final viewport = RenderAbstractViewport.maybeOf(text);
      if (boxes.isEmpty || viewport == null) return;
      final top = viewport.getOffsetToReveal(text, 0).offset + boxes.first.top;
      _scroll.jumpTo((top - 20).clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  double _fontSize = 20;
  final double _lineHeight = 1.7;
  bool _dark = false;
  ReadingStudyMode _mode = ReadingStudyMode.immersion;
  bool _sentenceTranslate = false;
  int _freqThreshold = kReadingDefaultFreqThreshold;
  Timer? _saveDebounce;
  Timer? _readingTick;
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
  Duration _audioPos = Duration.zero;
  Duration _audioDur = Duration.zero;
  int _speakUnitIndex = 0;
  int _speakUnitCount = 0;
  double? _playbackRate;
  bool _audioSeeking = false;
  String? _glossDocId;
  int _glossThreshold = -1;
  int _glossListsSig = -1;
  int _glossPageIndex = -1;
  Map<String, String> _hardGlosses = const <String, String>{};
  final Map<int, Map<String, String>> _glossByPage =
      <int, Map<String, String>>{};
  bool _glossLoading = false;
  /// False until current page has interactive spans (plain Text first).
  bool _interactiveReady = false;
  int _interactivePage = -1;
  int _prepareGeneration = 0;
  bool _prepareScheduled = false;
  double? _unknownRate;
  String _focusedSentence = '';
  int _pageIndex = 0;
  String? _pagedDocId;
  List<String> _pages = const <String>[];
  bool _loadingPageQuiz = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // Warm ECDICT off the critical first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFreqThresholdFromLevel();
      unawaited(
        ref.read(offlineWordDictionaryProvider).ensureLoaded(),
      );
    });
    _readingTick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      ref.read(learningActivityProvider.notifier).recordReadingDuration(
            duration: const Duration(seconds: 20),
          );
    });
  }

  Future<void> _chooseFontSize() async {
    final double? size = await showModalBottomSheet<double>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        minimum: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('阅读字号', style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final double size in <double>[18, 20, 22, 24, 26, 28])
                  ChoiceChip(
                    label: Text(size.toInt().toString()),
                    selected: _fontSize == size,
                    onSelected: (_) => Navigator.of(sheetContext).pop(size),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (size != null && mounted) setState(() => _fontSize = size);
  }

  Widget _buildPageNavigation(ReadingDoc doc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: <Widget>[
          TextButton(
            onPressed: _pageIndex == 0 ? null : () => _openPage(doc, _pageIndex - 1),
            child: const Text('上一节'),
          ),
          Expanded(
            child: Text(
              '第 ${_pageIndex + 1} / ${_pages.length} 节',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _dark ? const Color(0xFF9A9AA2) : const Color(0xFF6B6B76),
              ),
            ),
          ),
          TextButton(
            onPressed: _pageIndex >= _pages.length - 1
                ? null
                : () => _openPage(doc, _pageIndex + 1),
            child: const Text('下一节'),
          ),
        ],
      ),
    );
  }

  void _openPage(ReadingDoc doc, int index) {
    setState(() {
      _pageIndex = index;
      _interactiveReady = false;
      _interactivePage = -1;
      _glossPageIndex = -1;
      final cached = _glossByPage[index];
      if (cached != null) _hardGlosses = cached;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    unawaited(_prepareInteractivePage(doc));
    unawaited(
      ref.read(readingLibraryProvider.notifier).updateProgress(
        docId: doc.id,
        offsetChars: _pageBaseOffset,
        percent: (index + 1) / _pages.length,
      ),
    );
  }

  void _ensurePages(ReadingDoc doc) {
    if (_pagedDocId == doc.id && _pages.isNotEmpty) return;
    _pagedDocId = doc.id;
    // Sync split is fine for short texts; long novels are paged once and cached.
    _pages = splitReadingPages(doc.plainText);
    final initialOffset = widget.initialOffset;
    if (initialOffset != null && _pages.isNotEmpty) {
      int cursor = 0;
      for (int index = 0; index < _pages.length; index++) {
        final start = doc.plainText.indexOf(_pages[index], cursor);
        if (start < 0) break;
        cursor = start + _pages[index].length;
        if (initialOffset < cursor) {
          _pageIndex = index;
          _scrollToArticleOffset(initialOffset - start);
          return;
        }
      }
    }
    _restorePageFromProgress(doc);
  }

  void _restorePageFromProgress(ReadingDoc doc) {
    final ReadingProgress? progress = ref
        .read(readingLibraryProvider)
        .progressFor(doc.id);
    if (progress != null && doc.plainText.isNotEmpty && _pages.isNotEmpty) {
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
    _readingTick?.cancel();
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

  void _syncFreqThresholdFromLevel() {
    final int next = ref.read(adaptiveReadingFreqThresholdProvider);
    syncAdaptiveFreqThresholdToPrefs(next);
    if (!mounted || next == _freqThreshold) return;
    setState(() => _freqThreshold = next);
    _invalidateGlosses(clearCache: true, dropInteractive: false);
    final ReadingDoc? live =
        ref.read(readingLibraryProvider).docById(widget.docId);
    if (live != null) unawaited(_ensureGlosses(live));
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
    final ReadingTtsGender current = _ttsGender.asBookPairVoice;
    final selected = await showModalBottomSheet<ReadingTtsGender>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '朗读音色',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
            for (final ReadingTtsGender voice
                in ReadingTtsGenderX.selectableBookVoices)
              ListTile(
                title: Text(voice.labelCn),
                trailing: voice == current
                    ? Icon(
                        Icons.check_rounded,
                        color: AppDesignTokens.brandGreenDark,
                      )
                    : null,
                onTap: () => Navigator.pop(context, voice),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final ReadingTtsGender next = selected.asBookPairVoice;
    await _stopContinuous();
    if (!mounted) return;
    setState(() => _ttsGender = next);
    await saveReadingTtsGender(next);
  }

  double get _effectiveRate {
    final double base =
        _playbackRate ?? ref.read(learningSettingsProvider).ttsRate;
    return _slowMode ? (base * 0.55).clamp(0.5, 1.0) : base.clamp(0.5, 3.0);
  }

  /// Cloud CosyVoice MP3 already has natural pacing. Slowing media_kit below
  /// ~0.85 chops the last syllable; keep UI "慢读" labels but clamp decode rate.
  double get _cloudPlaybackRate => _effectiveRate.clamp(0.85, 1.8);

  String get _rateLabel {
    final double rate = _effectiveRate;
    final String raw = rate == rate.roundToDouble()
        ? rate.toStringAsFixed(0)
        : rate.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
              RegExp(r'\.$'),
              '',
            );
    return '${raw}×';
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
      _audioPos = Duration.zero;
      _audioDur = Duration.zero;
      _speakUnitIndex = 0;
      _speakUnitCount = 0;
      _audioSeeking = false;
    });
  }

  Future<void> _seekReadingAudio(double fraction) async {
    final Player? player = _readingAudio;
    if (player == null) return;
    final Duration dur = player.state.duration;
    if (dur <= Duration.zero) return;
    final Duration target = Duration(
      milliseconds: (dur.inMilliseconds * fraction.clamp(0.0, 1.0)).round(),
    );
    await player.seek(target);
    if (!mounted) return;
    setState(() {
      _audioPos = target;
      _audioDur = dur;
      _audioSeeking = false;
    });
  }

  Future<void> _applyPlaybackRate(double rate) async {
    final double next = rate.clamp(ttsRateOptions.first, ttsRateOptions.last);
    if (!mounted) return;
    setState(() {
      _playbackRate = next;
      _slowMode = false;
    });
    ref.read(learningSettingsProvider.notifier).setTtsRate(next);
    unawaited(_persistPrefs());
    final Player? player = _readingAudio;
    if (player != null) {
      try {
        await player.setRate(_cloudPlaybackRate);
      } catch (_) {}
    }
  }

  Future<void> _openReadingSpeedSheet() async {
    final double current = _effectiveRate;
    final double? picked = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _dark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext ctx) {
        final double maxHeight = MediaQuery.sizeOf(ctx).height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 12),
                Text(
                  '朗读语速',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: _dark ? Colors.white : const Color(0xFF1A1520),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (final double rate in ttsRateOptions)
                        ListTile(
                          title: Text('${rate}×'),
                          trailing: (current - rate).abs() < 0.01
                              ? Icon(
                                  Icons.check_rounded,
                                  color: AppDesignTokens.brandGreenDark,
                                )
                              : null,
                          onTap: () => Navigator.pop(ctx, rate),
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    await _applyPlaybackRate(picked);
  }

  /// Ask ECS / 5060 Ti to pre-generate this page into shared+personal packs.
  Future<void> _enqueuePageSpeechPregen(ReadingDoc doc) async {
    final String page = _pageText.trim();
    if (page.isEmpty) return;
    try {
      await ref.read(acquireApiClientProvider).enqueueReadingSpeechPregen(
            docId: doc.id,
            text: page,
            voice: _ttsGender.aliyunVoiceId,
            pageIndex: _pageIndex,
          );
      // Warm the next page in the background too.
      final int next = _pageIndex + 1;
      if (next < _pages.length) {
        final String nextText = _pages[next].trim();
        if (nextText.isNotEmpty) {
          unawaited(
            ref.read(acquireApiClientProvider).enqueueReadingSpeechPregen(
                  docId: doc.id,
                  text: nextText,
                  voice: _ttsGender.aliyunVoiceId,
                  pageIndex: next,
                ),
          );
        }
      }
    } catch (_) {
      // Prefetch is best-effort; playback can still synth on demand.
    }
  }

  Future<void> _playContinuous(ReadingDoc doc) async {
    if (_continuousPlaying) {
      await _stopContinuous();
      return;
    }
    if (readingDocNeedsCloudPrep(doc)) {
      final ReadingBookPrepStatus? prep =
          ref.read(readingBookPrepProvider(doc.id)).asData?.value;
      if (prep == null || !prep.ready) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              prep == null
                  ? '云端 AI 朗读还在确认中，可先阅读正文'
                  : '朗读预处理中：${prep.progressLabel}（可先阅读）',
            ),
          ),
        );
        return;
      }
    }
    final int generation = ++_continuousGeneration;
    // Never tokenize / synth the whole novel — page-scoped only (crash fix).
    _ensurePages(doc);
    final List<ReadingSpeakUnit> units = splitReadingSpeakUnits(_pageText);
    if (units.isEmpty) return;
    setState(() {
      _continuousPlaying = true;
      _speakUnitIndex = 0;
      _speakUnitCount = units.length;
      _audioPos = Duration.zero;
      _audioDur = Duration.zero;
      _audioSeeking = false;
    });
    unawaited(_enqueuePageSpeechPregen(doc));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pages.length > 1
                ? '朗读本节（${_pageIndex + 1}/${_pages.length}）· 后台预生成到服务器'
                : '正在准备朗读…已缓存句可直接播',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    final String voiceId = _ttsGender.aliyunVoiceId;
    final Player player = Player();
    _readingAudio = player;
    Future<String>? prefetch;
    try {
      for (int i = 0; i < units.length; i++) {
        if (!mounted || generation != _continuousGeneration) return;
        final ReadingSpeakUnit unit = units[i];
        if (mounted) {
          setState(() {
            _speakUnitIndex = i;
            _audioPos = Duration.zero;
            _audioDur = Duration.zero;
          });
        }
        final Future<String> urlFuture =
            prefetch ??
            ref
                .read(acquireApiClientProvider)
                .readingSpeech(unit.text, voiceId)
                .timeout(const Duration(seconds: 20));
        // Prefetch next sentence while this one plays (same-text requests coalesce).
        prefetch = i + 1 < units.length
            ? ref
                  .read(acquireApiClientProvider)
                  .readingSpeech(units[i + 1].text, voiceId)
                  .timeout(const Duration(seconds: 20))
            : null;
        final String url = await urlFuture;
        if (!mounted || generation != _continuousGeneration) return;
        final Completer<void> done = Completer<void>();
        _readingDone = done;
        bool started = false;
        bool finishing = false;
        final Duration endGrace = pronunciationEndGraceFor(unit.text);
        // Keep CosyVoice tails audible: media_kit can fire completed during
        // open, and OEM decode often drops the last syllable at raw EOS.
        void scheduleFinish() {
          if (done.isCompleted || finishing) return;
          finishing = true;
          unawaited(() async {
            await Future<void>.delayed(endGrace);
            if (!done.isCompleted) done.complete();
          }());
        }

        final StreamSubscription<bool> playing = player.stream.playing.listen((
          bool value,
        ) {
          if (value) {
            started = true;
            return;
          }
          if (started) scheduleFinish();
        });
        final StreamSubscription<bool> completed = player.stream.completed
            .listen((bool value) {
              if (value && started) scheduleFinish();
            });
        final StreamSubscription<String> errors = player.stream.error.listen((
          String error,
        ) {
          if (!done.isCompleted) done.completeError(StateError(error));
        });
        final int pageWordBase = unit.firstWordIndex;
        final StreamSubscription<Duration> position = player.stream.position
            .listen((Duration position) {
              if (!mounted || generation != _continuousGeneration) {
                if (!done.isCompleted) done.complete();
                return;
              }
              final Duration total = player.state.duration;
              final int durationMs = total.inMilliseconds;
              if (durationMs <= 0) return;
              // Relative word positions are estimated within the real audio duration.
              final int local =
                  (position.inMilliseconds / durationMs * unit.wordCount)
                      .floor()
                      .clamp(0, unit.wordCount - 1);
              if (_audioSeeking) {
                setState(() => _highlightWordIndex = pageWordBase + local);
                return;
              }
              setState(() {
                _audioPos = position;
                _audioDur = total;
                _highlightWordIndex = pageWordBase + local;
              });
            });
        try {
          await player.open(Media(url));
          final double cloudRate = _cloudPlaybackRate;
          if ((cloudRate - 1.0).abs() > 0.02) {
            await player.setRate(cloudRate);
          }
          await done.future.timeout(
            const Duration(minutes: 3) + endGrace,
          );
        } finally {
          if (identical(_readingDone, done)) _readingDone = null;
          await playing.cancel();
          await completed.cancel();
          await errors.cancel();
          await position.cancel();
        }
      }
    } catch (_) {
      if (mounted && generation == _continuousGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('朗读暂不可用，已改为后台生成，稍后再点播放')));
      }
    } finally {
      if (identical(_readingAudio, player)) _readingAudio = null;
      try {
        await player.dispose();
      } catch (_) {}
      if (mounted && generation == _continuousGeneration) {
        setState(() {
          _continuousPlaying = false;
          _highlightWordIndex = null;
          _audioPos = Duration.zero;
          _audioDur = Duration.zero;
          _speakUnitIndex = 0;
          _speakUnitCount = 0;
          _audioSeeking = false;
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

  void _invalidateGlosses({
    bool clearCache = false,
    bool dropInteractive = true,
  }) {
    _glossDocId = null;
    _glossPageIndex = -1;
    if (dropInteractive) {
      _interactiveReady = false;
      _interactivePage = -1;
    }
    if (clearCache) {
      _glossByPage.clear();
      _hardGlosses = const <String, String>{};
    }
  }

  Future<Map<String, String>> _buildPageGlosses({
    required ReadingDoc doc,
    required int pageIndex,
    required ReadingFrequencyLexicon lexicon,
    required OfflineWordDictionary dictionary,
    required ReadingVocabLists lists,
    required Set<String> known,
  }) async {
    if (pageIndex < 0 || pageIndex >= _pages.length) {
      return const <String, String>{};
    }
    final Map<String, String>? cached = _glossByPage[pageIndex];
    if (cached != null &&
        _glossDocId == doc.id &&
        _glossThreshold == _freqThreshold) {
      return cached;
    }
    final List<String> tokens = extractReadingWordTokens(_pages[pageIndex]);
    final Map<String, String> glosses = await buildHardWordGlosses(
      words: tokens.toSet(),
      lexicon: lexicon,
      dictionary: dictionary,
      threshold: _freqThreshold,
      known: known,
      focus: lists.focus,
    );
    _glossByPage[pageIndex] = glosses;
    return glosses;
  }

  Future<void> _ensureGlosses(ReadingDoc doc) async {
    final ReadingVocabLists lists = ref.read(readingVocabListsProvider);
    final Set<String> learned = ref.read(learnedVocabularyProvider);
    final int listsSig = _listsSignature(lists, learned);
    _ensurePages(doc);
    final int page = _pageIndex;
    if (_glossDocId == doc.id &&
        _glossThreshold == _freqThreshold &&
        _glossListsSig == listsSig &&
        _glossPageIndex == page &&
        _glossByPage.containsKey(page)) {
      _hardGlosses = _glossByPage[page]!;
      return;
    }
    final bool settingsChanged = _glossDocId != doc.id ||
        _glossThreshold != _freqThreshold ||
        _glossListsSig != listsSig;
    if (settingsChanged) {
      _glossByPage.clear();
    }
    _glossDocId = doc.id;
    _glossThreshold = _freqThreshold;
    _glossListsSig = listsSig;
    _glossPageIndex = page;
    if (mounted) setState(() => _glossLoading = true);
    try {
      final ReadingFrequencyLexicon lexicon = await ref.read(
        readingFrequencyLexiconProvider.future,
      );
      final OfflineWordDictionary dictionary = ref.read(
        offlineWordDictionaryProvider,
      );
      await dictionary.ensureLoaded();
      final Set<String> known = effectiveKnownWords(
        lists: lists,
        learned: learned,
      );
      final Map<String, String> glosses = await _buildPageGlosses(
        doc: doc,
        pageIndex: page,
        lexicon: lexicon,
        dictionary: dictionary,
        lists: lists,
        known: known,
      );
      final List<String> tokens = extractReadingWordTokens(
        page < _pages.length ? _pages[page] : '',
      );
      final double rate = unknownWordRate(
        words: tokens,
        lexicon: lexicon,
        threshold: _freqThreshold,
        known: known,
        focus: lists.focus,
      );
      if (!mounted || _glossDocId != doc.id || _pageIndex != page) return;
      setState(() {
        _hardGlosses = glosses;
        _unknownRate = rate;
        _glossLoading = false;
      });
      // Prefetch the next page while the user reads.
      final int next = page + 1;
      if (next < _pages.length && !_glossByPage.containsKey(next)) {
        unawaited(
          _buildPageGlosses(
            doc: doc,
            pageIndex: next,
            lexicon: lexicon,
            dictionary: dictionary,
            lists: lists,
            known: known,
          ),
        );
      }
    } catch (_) {
      if (!mounted || _glossDocId != doc.id) return;
      setState(() {
        _hardGlosses = const <String, String>{};
        _unknownRate = null;
        _glossLoading = false;
      });
    }
  }

  void _schedulePrepareInteractive(ReadingDoc doc) {
    if (_prepareScheduled) return;
    if (_interactiveReady && _interactivePage == _pageIndex) return;
    _prepareScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareScheduled = false;
      if (!mounted) return;
      unawaited(_prepareInteractivePage(doc));
    });
  }

  /// Plain text first; enable taps ASAP. Glosses fill in without blocking open
  /// (ECDICT + hard-word pass used to stall 绿野仙踪 on「正在打开」).
  Future<void> _prepareInteractivePage(ReadingDoc doc) async {
    final int gen = ++_prepareGeneration;
    final int page = _pageIndex;
    if (_interactiveReady && _interactivePage == page) return;
    _ensurePages(doc);
    unawaited(_enqueuePageSpeechPregen(doc));
    // Yield so the plain-text frame can paint before heavy span build.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || gen != _prepareGeneration || _pageIndex != page) return;
    setState(() {
      _interactiveReady = true;
      _interactivePage = page;
    });
    unawaited(_ensureGlosses(doc));
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

  List<String> _sentencesForPageQuiz() {
    String raw = _pageText.trim();
    List<String> sentences = splitReadingSentences(raw)
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .take(30)
        .toList(growable: false);
    if (sentences.length < 2 &&
        _pageIndex + 1 < _pages.length &&
        _pages[_pageIndex + 1].trim().isNotEmpty) {
      raw = '$raw\n${_pages[_pageIndex + 1].trim()}';
      sentences = splitReadingSentences(raw)
          .map((String s) => s.trim())
          .where((String s) => s.isNotEmpty)
          .take(30)
          .toList(growable: false);
    }
    return sentences;
  }

  List<String> _targetWordsForPageQuiz() {
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    void add(String raw) {
      final String key = normalizeWord(raw);
      if (key.length < 2 || !seen.add(key)) return;
      out.add(key);
    }

    for (final String w in ref.read(readingVocabListsProvider).focus) {
      add(w);
      if (out.length >= 20) return out;
    }
    for (final String w in _hardGlosses.keys) {
      add(w);
      if (out.length >= 20) return out;
    }
    return out;
  }

  Future<ReadingPageQuizBundle?> _preparePageComprehensionQuiz(
    ReadingDoc doc,
  ) async {
    if (_loadingPageQuiz) return null;
    if (!ref.read(authSessionProvider).isLoggedIn) {
      throw StateError('请先登录后再使用 AI 伴读出题');
    }
    final List<String> sentences = _sentencesForPageQuiz();
    if (sentences.length < 2) {
      throw StateError('本节内容太短，翻到内容更完整的一页再试');
    }
    final List<String> targetWords = _targetWordsForPageQuiz();
    final String topic = '${doc.displayTitle} · 第 ${_pageIndex + 1} 节';
    await _pauseReadingForLookup();
    if (!mounted) return null;
    setState(() => _loadingPageQuiz = true);
    try {
      try {
        final List<Map<String, dynamic>> raw = await ref
            .read(acquireApiClientProvider)
            .generateReadingQuiz(
              sentences: sentences,
              targetWords: targetWords,
            );
        final List<CourseQuizItem> quiz = raw
            .map(CourseQuizItem.fromJson)
            .where((CourseQuizItem item) => item.options.length == 4)
            .toList(growable: false);
        if (quiz.isNotEmpty) {
          return ReadingPageQuizBundle(
            quiz: quiz,
            sentences: sentences,
            topic: topic,
          );
        }
      } catch (_) {
        // Fall through to local grounded items so伴读出题 still works offline/API-slow.
      }
      final List<CourseQuizItem> fallback = buildReadingPageQuizFallback(
        sentences: sentences,
        targetWords: targetWords,
      );
      if (fallback.isEmpty) return null;
      return ReadingPageQuizBundle(
        quiz: fallback,
        sentences: sentences,
        topic: topic,
        fromFallback: true,
      );
    } finally {
      if (mounted) setState(() => _loadingPageQuiz = false);
    }
  }

  Future<void> _openPreparedPageQuiz(
    ReadingDoc doc,
    ReadingPageQuizBundle bundle,
  ) async {
    if (!mounted || bundle.quiz.isEmpty) return;
    if (bundle.fromFallback && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DeepSeek 暂不可用，已用本节原文生成练习题')),
      );
    }
    final CourseQuizResult? result = await Navigator.of(context).push(
      MaterialPageRoute<CourseQuizResult>(
        builder: (_) => CourseUnitQuizScreen(
          topic: bundle.topic,
          quiz: bundle.quiz,
          sentences: bundle.sentences,
        ),
      ),
    );
    if (!mounted || result == null) return;
    final double accuracy =
        result.total <= 0 ? 0 : result.correct / result.total;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '本节理解题 ${result.correct}/${result.total}'
          '${accuracy >= 0.75 ? ' · 很棒' : ''}',
        ),
      ),
    );
    if (accuracy >= 0.7) {
      try {
        await ref.read(acquireApiClientProvider).commerceEarnPoints(
              reason: 'reading_quiz_pass',
              meta: <String, dynamic>{
                'accuracy': accuracy,
                'content_id': '${doc.id}:p$_pageIndex',
                'duration_ratio': 1.0,
              },
            );
      } catch (_) {}
    }
  }

  Future<void> _refreshReadingGlosses(ReadingDoc doc) async {
    _invalidateGlosses(clearCache: true, dropInteractive: false);
    if (mounted) setState(() {});
    await _ensureGlosses(doc);
  }

  /// After lookup: keep Chinese under the word until the learner 斩掉 it.
  Future<void> _markLookedUpWordForGloss({
    required ReadingDoc doc,
    required String lexeme,
  }) async {
    final ReadingVocabLists lists = ref.read(readingVocabListsProvider);
    if (lists.isKnown(lexeme)) return;
    await ref.read(readingVocabListsProvider.notifier).markFocus(lexeme);
    if (!mounted) return;
    await _refreshReadingGlosses(doc);
  }

  /// Manual 斩: hide inline Chinese for this word from now on.
  Future<void> _slashWordTranslation({
    required ReadingDoc doc,
    required String lexeme,
  }) async {
    await ref.read(readingVocabListsProvider.notifier).markKnown(lexeme);
    if (!mounted) return;
    await _refreshReadingGlosses(doc);
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
    unawaited(_markLookedUpWordForGloss(doc: doc, lexeme: lexeme));
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
        final bool alreadySlashed =
            ref.read(readingVocabListsProvider).isKnown(lexeme);
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
                      onPressed: alreadySlashed
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              unawaited(
                                _slashWordTranslation(
                                  doc: doc,
                                  lexeme: lexeme,
                                ).then((_) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '已斩掉：$lexeme · 不再显示中文',
                                      ),
                                    ),
                                  );
                                }),
                              );
                            },
                      icon: Icon(
                        alreadySlashed
                            ? Icons.check_circle_rounded
                            : Icons.content_cut_rounded,
                      ),
                      label: Text(alreadySlashed ? '已斩' : '斩掉'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        unawaited(
                          ref
                              .read(readingVocabListsProvider.notifier)
                              .markFocus(lexeme)
                              .then((_) => _refreshReadingGlosses(doc))
                              .then((_) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('继续显示中文：$lexeme'),
                                  ),
                                );
                              }),
                        );
                      },
                      icon: const Icon(Icons.translate_rounded),
                      label: const Text('显示中文'),
                    ),
                  ],
                ),
                WordLookupPopupCard(
                  rawWord: lexeme,
                  contextSentence: sentence,
                  episodeId: doc.episodeId ?? 'reading:${doc.id}',
                  fallbackDefinitionCn: fallback.isEmpty ? null : fallback,
                  maxHeight: maxH,
                  // Never let device/Edge/CosyVoice “偷跑”; reading uses book voice only.
                  allowSynthesisFallback: false,
                  onClose: () => Navigator.pop(ctx),
                  onPronounce: () {
                    unawaited(
                      ref.read(wordPronunciationServiceProvider).stop(),
                    );
                  },
                  pronounceOverride: (String text, {String language = 'en-US'}) async {
                    if (language.toLowerCase().startsWith('zh')) {
                      // Chinese gloss: stay silent rather than OEM TTS.
                      return;
                    }
                    await _speakReading(text);
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

    // Do not auto-speak on long-press — that felt like “AI 语音偷跑”.
    // User explicitly taps「朗读」below when they want audio.

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
                    '自动生词阈值（随水平）',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '按估计词汇量自动对齐 i+1：高亮 / 词下中文为词频 > $_freqThreshold。'
                    '水平变化后会自动更新；也可临时拖动。',
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
                              _invalidateGlosses(clearCache: true);
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
    ref.listen<int>(adaptiveReadingFreqThresholdProvider, (int? prev, int next) {
      if (prev == next) return;
      syncAdaptiveFreqThresholdToPrefs(next);
      if (!mounted || next == _freqThreshold) return;
      setState(() => _freqThreshold = next);
      // Keep the page interactive; only refresh glosses (avoid reopen loop).
      _invalidateGlosses(clearCache: true, dropInteractive: false);
      final ReadingDoc? live = ref.read(readingLibraryProvider).docById(widget.docId);
      if (live != null) unawaited(_ensureGlosses(live));
    });
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
    // Keep watching long-novel TTS prep so continuous read can use it when
    // ready — but never block the first paint of the book text.
    if (readingDocNeedsCloudPrep(doc)) {
      ref.watch(readingBookPrepProvider(doc.id));
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
    _schedulePrepareInteractive(doc);

    final bool showChinese = _mode.showInlineChinese;
    final bool useInteractive =
        _interactiveReady && _interactivePage == _pageIndex;
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
        title: doc.displayTitle,
        trailing: const SizedBox.shrink(),
        description: !useInteractive
            ? '正在打开 · 可先阅读，标注稍后出现'
            : (_mode == ReadingStudyMode.immersion
                ? '沉浸 · ${_ttsGender.labelCn} · 连续朗读${_slowMode ? ' · 慢读' : ''}$rateLabel'
                : '精读 · ${_ttsGender.labelCn} · 难词(>$_freqThreshold)${_slowMode ? ' · 慢读' : ''}$rateLabel'),
        leading: PadBackButton(onPressed: () => context.pop()),
        actions: <Widget>[
          IconButton(
            tooltip: '阅读字号（当前 ${_fontSize.toInt()}）',
            onPressed: _chooseFontSize,
            icon: const Icon(Icons.format_size_rounded),
          ),
          IconButton(
            tooltip: '选择朗读音色（当前：${_ttsGender.labelCn}）',
            onPressed: () => unawaited(_toggleTtsGender()),
            icon: Icon(
              _ttsGender.asBookPairVoice == ReadingTtsGender.female
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
                  final Player? player = _readingAudio;
                  if (player != null) {
                    unawaited(player.setRate(_cloudPlaybackRate));
                  }
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
                case 'theme':
                  setState(() => _dark = !_dark);
                case 'episode':
                  if ((doc.episodeId ?? '').isNotEmpty) {
                    context.push(
                      '/episodes/${Uri.encodeComponent(doc.episodeId!)}',
                    );
                  }
                case 'course_mode':
                  unawaited(
                    showEnableCourseModeSheet(
                      context: context,
                      ref: ref,
                      type: CoursePlanType.reading,
                      sourceId: doc.id,
                      title: doc.title,
                      plainText: doc.plainText,
                    ),
                  );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'voice_female',
                child: Text(
                  _ttsGender == ReadingTtsGender.female
                      ? '女声 · 龙安风悦有感情（当前）'
                      : '女声 · 龙安风悦有感情',
                ),
              ),
              PopupMenuItem<String>(
                value: 'voice_male',
                child: Text(
                  _ttsGender == ReadingTtsGender.male
                      ? '男声 · 龙泽有感情（当前）'
                      : '男声 · 龙泽有感情',
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
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'course_mode',
                child: Text('开启课程学习模式'),
              ),
            ],
          ),
        ],
      ),
      body: ReadingDigitalHumanBallHost(
        doc: doc,
        focusedSentence: _focusedSentence,
        onPreparePageQuiz: () => _preparePageComprehensionQuiz(doc),
        onOpenPageQuiz: (ReadingPageQuizBundle bundle) =>
            _openPreparedPageQuiz(doc, bundle),
        child: ColoredBox(
          color: bg,
          child: Stack(
            children: <Widget>[
              NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification n) {
              if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
                _scheduleProgressSave(doc);
              }
              return false;
            },
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(
                22,
                12,
                22,
                _continuousPlaying ? 132 : 40,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    doc.displayTitle,
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
                                SubtitleChunkKind.vocab,
                              ),
                              label: '生词',
                              dark: _dark,
                            ),
                          ],
                          Text(
                            showChinese
                                ? (_glossLoading
                                      ? '难词释义加载中…'
                                      : '词下灰字 = 难词/查词 · 斩掉后不再显示 · 双击语块 · 长按整句')
                                : '沉浸模式 · 查词仍可显示中文 · 斩掉后隐藏 · 点词查释义',
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
                  if (_pages.length > 1) _buildPageNavigation(doc),
                  if (!useInteractive)
                    Text(
                      _pageText,
                      key: _articleTextKey,
                      style: TextStyle(
                        color: fg,
                        fontSize: _fontSize,
                        height: _lineHeight,
                        fontFamily: 'Georgia',
                      ),
                    )
                  else
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
                        forceGlossWords:
                            ref.watch(readingVocabListsProvider).focus,
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
                    key: _articleTextKey,
                  ),
                  if (_pages.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: _buildPageNavigation(doc),
                    ),
                ],
              ),
            ),
          ),
              if (_continuousPlaying)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ReadingAudioBar(
                    dark: _dark,
                    position: _audioPos,
                    duration: _audioDur,
                    unitIndex: _speakUnitIndex,
                    unitCount: _speakUnitCount,
                    rateLabel: _rateLabel,
                    onStop: () => unawaited(_stopContinuous()),
                    onSeekChanged: (double value) {
                      final Duration dur = _audioDur;
                      if (dur <= Duration.zero) return;
                      setState(() {
                        _audioSeeking = true;
                        _audioPos = Duration(
                          milliseconds:
                              (dur.inMilliseconds * value.clamp(0.0, 1.0))
                                  .round(),
                        );
                      });
                    },
                    onSeekEnd: (double value) {
                      unawaited(_seekReadingAudio(value));
                    },
                    onOpenSpeed: () => unawaited(_openReadingSpeedSheet()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatReadingClock(Duration value) {
  final int total = value.inMilliseconds < 0 ? 0 : value.inSeconds;
  final int m = total ~/ 60;
  final int s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

class _ReadingAudioBar extends StatelessWidget {
  const _ReadingAudioBar({
    required this.dark,
    required this.position,
    required this.duration,
    required this.unitIndex,
    required this.unitCount,
    required this.rateLabel,
    required this.onStop,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onOpenSpeed,
  });

  final bool dark;
  final Duration position;
  final Duration duration;
  final int unitIndex;
  final int unitCount;
  final String rateLabel;
  final VoidCallback onStop;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onOpenSpeed;

  @override
  Widget build(BuildContext context) {
    final Color surface = dark ? const Color(0xFF242428) : Colors.white;
    final Color ink = dark ? const Color(0xFFF2F2F7) : const Color(0xFF1A1520);
    final Color muted = dark ? const Color(0xFF9A9AA2) : const Color(0xFF6B6B76);
    final double progress = duration.inMilliseconds <= 0
        ? 0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final String unitLabel = unitCount <= 0
        ? '朗读中'
        : '句 ${unitIndex + 1}/$unitCount';

    return Material(
      elevation: 10,
      color: surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconButton(
                    tooltip: '停止朗读',
                    onPressed: onStop,
                    icon: Icon(
                      Icons.stop_circle_outlined,
                      color: AppDesignTokens.brandGreenDark,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      unitLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onOpenSpeed,
                    style: TextButton.styleFrom(
                      foregroundColor: AppDesignTokens.brandGreenDark,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '语速 $rateLabel',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              Row(
                children: <Widget>[
                  Text(
                    _formatReadingClock(position),
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 12,
                        ),
                        activeTrackColor: AppDesignTokens.brandGreenDark,
                        inactiveTrackColor: muted.withValues(alpha: 0.28),
                        thumbColor: AppDesignTokens.brandGreenDark,
                      ),
                      child: Slider(
                        value: progress,
                        onChanged: duration.inMilliseconds <= 0
                            ? null
                            : onSeekChanged,
                        onChangeEnd: duration.inMilliseconds <= 0
                            ? null
                            : onSeekEnd,
                      ),
                    ),
                  ),
                  Text(
                    _formatReadingClock(duration),
                    style: TextStyle(
                      color: muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
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
