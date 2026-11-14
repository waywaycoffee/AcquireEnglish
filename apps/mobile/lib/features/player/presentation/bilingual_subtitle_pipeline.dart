import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../../settings/presentation/settings_provider.dart';
import '../../shared/data/word_lookup_service.dart';
import 'asr_subtitle_cache.dart';
import 'asr_subtitle_job.dart';
import 'asr_subtitle_service.dart';
import 'bilingual_subtitle_helpers.dart';
import 'ocr_subtitle_sampler.dart';
import 'player_mock_state.dart';
import 'player_subtitle_loader.dart';
import 'subtitle_word_alignment.dart';

export 'bilingual_subtitle_helpers.dart'
    show BilingualPipelinePhase, MissingSubtitleSide, needsBilingualFill;

typedef BilingualLinesGetter = List<PlayerSubtitleLine> Function();
typedef BilingualLinesSetter = void Function(List<PlayerSubtitleLine> lines);
typedef BilingualPhaseListener = void Function(BilingualPipelinePhase phase);
typedef BilingualProgressListener = void Function(String label);
typedef BilingualTranslationFallback = void Function();

/// Orchestrates on-device OCR while playing, then optional AI translate + ASR.
class BilingualSubtitlePipeline {
  BilingualSubtitlePipeline({
    required this.episodeId,
    required this.videoPath,
    required this.settings,
    required this.getLines,
    required this.setLines,
    this.player,
    this.onPhaseChanged,
    this.onProgress,
    this.onNeedTranslationFallback,
    this.slowTimeout = const Duration(seconds: 4),
    // Start ZH→EN quickly so Chinese softsubs are not stuck English-empty
    // while OCR is still hunting hardsubs.
    this.translationFallbackDelay = const Duration(seconds: 2),
    this.minFilledCues = 2,
    this.sampler,
    this.wordLookup = const WordLookupService(),
    this.asrRunner = const AsrSubtitleJobRunner(),
    this.cache = const AsrSubtitleCache(),
    this.supportDirectory,
    this.onBilingualReady,
  });

  final String episodeId;
  final String videoPath;
  final LearningSettingsState settings;
  final BilingualLinesGetter getLines;
  final BilingualLinesSetter setLines;
  final Player? player;
  final BilingualPhaseListener? onPhaseChanged;
  final BilingualProgressListener? onProgress;

  /// Fired when burned-in OCR needs ZH→EN to fill remaining English holes.
  final BilingualTranslationFallback? onNeedTranslationFallback;
  final Duration slowTimeout;

  /// Let on-screen hardsub OCR win before machine ZH→EN kicks in.
  final Duration translationFallbackDelay;
  final int minFilledCues;
  final OcrSubtitleSampler? sampler;
  final WordLookupService wordLookup;
  final AsrSubtitleJobRunner asrRunner;
  final AsrSubtitleCache cache;
  final Future<Directory> Function()? supportDirectory;
  final Future<void> Function(List<PlayerSubtitleLine> lines)? onBilingualReady;

  static final Set<String> _activePipelines = <String>{};

  BilingualPipelinePhase _phase = BilingualPipelinePhase.idle;
  MissingSubtitleSide _missing = MissingSubtitleSide.none;
  OcrSubtitleSampler? _ownedSampler;
  Timer? _slowTimer;
  Timer? _translationFallbackTimer;
  int _filledCount = 0;
  bool _cancelled = false;
  bool _translationFallbackStarted = false;
  bool _ocrProofreadOnly = false;
  bool _asrProofreadStarted = false;
  AsrSubtitleCancellationToken? _asrToken;
  String? _lockKey;

  BilingualPipelinePhase get phase => _phase;
  MissingSubtitleSide get missingSide => _missing;
  bool get showAiCompleteButton => _phase == BilingualPipelinePhase.ocrSlow;
  bool get isBusy =>
      _phase == BilingualPipelinePhase.ocrRunning ||
      _phase == BilingualPipelinePhase.ocrSlow ||
      _phase == BilingualPipelinePhase.translating ||
      _phase == BilingualPipelinePhase.asrProofreading;

  String get statusLabel {
    switch (_phase) {
      case BilingualPipelinePhase.ocrRunning:
        return '正在识别画面字幕…';
      case BilingualPipelinePhase.ocrSlow:
        return '画面字幕收益不足';
      case BilingualPipelinePhase.translating:
        return '正在翻译补全…';
      case BilingualPipelinePhase.asrProofreading:
        return '正在语音校对…';
      case BilingualPipelinePhase.completed:
        return '双语字幕已就绪';
      case BilingualPipelinePhase.cancelled:
        return '已取消';
      case BilingualPipelinePhase.idle:
        return '';
    }
  }

  /// Returns true when monolingual official cues need bilingual fill.
  static bool shouldAutoStart(List<PlayerSubtitleLine> seedLines) {
    return needsBilingualFill(seedLines);
  }

  /// Translate missing English immediately (no OCR / player required).
  ///
  /// Used on course open so Chinese-only official CC becomes bilingual before
  /// the user has to wait for video-ready OCR. Applies each window via
  /// [onLinesUpdated] so the UI can show English primary as soon as the first
  /// batch lands.
  static Future<List<PlayerSubtitleLine>> fillMissingEnglishByTranslation({
    required List<PlayerSubtitleLine> lines,
    required LearningSettingsState settings,
    WordLookupService wordLookup = const WordLookupService(),
    void Function(String label)? onProgress,
    void Function(List<PlayerSubtitleLine> lines)? onLinesUpdated,
    AsrSubtitleCancellationToken? cancellationToken,
    int? prioritizeAroundMs,

    /// Re-read live lines before each window merge so concurrent OCR upgrades
    /// are not wiped by a stale open-course snapshot.
    List<PlayerSubtitleLine> Function()? currentLines,
  }) async {
    final MissingSubtitleSide missing = detectMissingSubtitleSide(lines);
    if (lines.isEmpty ||
        (missing != MissingSubtitleSide.english &&
            missing != MissingSubtitleSide.both)) {
      return lines;
    }
    final AsrSubtitleCancellationToken token =
        cancellationToken ?? AsrSubtitleCancellationToken();
    List<PlayerSubtitleLine> working = List<PlayerSubtitleLine>.of(lines);
    const int window = 6;
    int gainedTotal = 0;
    // Fill near the playhead first so English primary appears immediately.
    final List<int> order = _englishFillWindowStarts(
      length: working.length,
      window: window,
      prioritizeAroundMs: prioritizeAroundMs,
      lines: working,
    );
    int completedWindows = 0;
    for (final int cursor in order) {
      if (token.isCancelled) {
        break;
      }
      // Prefer the latest UI/OCR state as the merge base.
      final List<PlayerSubtitleLine>? live = currentLines?.call();
      if (live != null && live.isNotEmpty) {
        working = _rebaseWorkingOntoLive(working: working, live: live);
      }
      if (!_windowNeedsEnglish(working, cursor, window)) {
        completedWindows += 1;
        continue;
      }
      final int end = cursor + window > working.length
          ? working.length
          : cursor + window;
      onProgress?.call('正在补英文…已完成 $completedWindows/${order.length}');
      final List<PlayerSubtitleLine> slice = working.sublist(cursor, end);
      List<PlayerSubtitleLine> filledSlice = await _translateMissingStatic(
        lines: slice,
        settings: settings,
        wordLookup: wordLookup,
        token: token,
      );
      final bool sliceStillMissing =
          detectMissingSubtitleSide(filledSlice) ==
              MissingSubtitleSide.english ||
          detectMissingSubtitleSide(filledSlice) == MissingSubtitleSide.both;
      if (sliceStillMissing && !token.isCancelled) {
        filledSlice = await _translateMissingStatic(
          lines: filledSlice,
          settings: settings,
          wordLookup: wordLookup,
          token: token,
          forceFreeParallel: true,
        );
      }
      // Patch only this window onto the latest live base.
      final List<PlayerSubtitleLine> base = currentLines?.call() ?? working;
      final List<PlayerSubtitleLine> merged = List<PlayerSubtitleLine>.of(base);
      final int patchEnd = cursor + filledSlice.length;
      if (merged.length < patchEnd) {
        // Length drift (OCR append): fall back to working-sized merge.
        final List<PlayerSubtitleLine> fallback = List<PlayerSubtitleLine>.of(
          working,
        );
        for (
          int i = 0;
          i < filledSlice.length && cursor + i < fallback.length;
          i++
        ) {
          fallback[cursor + i] = _preferBetterEnglish(
            previous: fallback[cursor + i],
            translated: filledSlice[i],
          );
        }
        working = sanitizeSubtitleLanguageFields(fallback);
      } else {
        for (int i = 0; i < filledSlice.length; i++) {
          merged[cursor + i] = _preferBetterEnglish(
            previous: merged[cursor + i],
            translated: filledSlice[i],
          );
        }
        working = sanitizeSubtitleLanguageFields(merged);
      }
      final int gained = countFilledMissingSide(
        before: slice,
        after: filledSlice,
        missing: MissingSubtitleSide.english,
      );
      completedWindows += 1;
      if (gained > 0 ||
          filledSlice.any((PlayerSubtitleLine l) => looksEnglish(l.english))) {
        gainedTotal += gained > 0 ? gained : 1;
        onLinesUpdated?.call(List<PlayerSubtitleLine>.of(working));
      }
    }
    // Second pass for holes the first window pass left empty (network flakes).
    if (!token.isCancelled &&
        (detectMissingSubtitleSide(working) == MissingSubtitleSide.english ||
            detectMissingSubtitleSide(working) == MissingSubtitleSide.both)) {
      onProgress?.call('继续补全剩余英文字幕…');
      final List<PlayerSubtitleLine> live = currentLines?.call() ?? working;
      working = await _translateMissingStatic(
        lines: live,
        settings: settings,
        wordLookup: wordLookup,
        token: token,
        forceFreeParallel: true,
      );
      if (!token.isCancelled) {
        onLinesUpdated?.call(List<PlayerSubtitleLine>.of(working));
      }
    }
    onProgress?.call(
      detectMissingSubtitleSide(working) == MissingSubtitleSide.none
          ? '双语字幕已就绪'
          : (gainedTotal > 0 ||
                    working.any(
                      (PlayerSubtitleLine l) => looksEnglish(l.english),
                    )
                ? '英文字幕仍不完整'
                : '自动翻译未产出英文'),
    );
    return working;
  }

  /// Keep live OCR English when rebasing a translate window.
  static List<PlayerSubtitleLine> _rebaseWorkingOntoLive({
    required List<PlayerSubtitleLine> working,
    required List<PlayerSubtitleLine> live,
  }) {
    if (live.length != working.length) {
      return List<PlayerSubtitleLine>.of(live);
    }
    final List<PlayerSubtitleLine> out = <PlayerSubtitleLine>[];
    for (int i = 0; i < working.length; i++) {
      out.add(_preferBetterEnglish(previous: live[i], translated: working[i]));
    }
    return out;
  }

  /// Prefer existing OCR/official English, but allow MT to upgrade tiny OCR
  /// crumbs (e.g. "video to") so the rest of the episode is not left blank.
  static PlayerSubtitleLine _preferBetterEnglish({
    required PlayerSubtitleLine previous,
    required PlayerSubtitleLine translated,
  }) {
    final bool prevEn = isReliableOcrEnglish(previous.english);
    final bool nextEn =
        looksEnglish(translated.english) && !looksChinese(translated.english);
    final String english;
    if (prevEn && nextEn) {
      english = _englishForCuePair(
        existing: previous.english,
        translated: translated.english,
        chinese: looksChinese(previous.chinese)
            ? previous.chinese
            : translated.chinese,
      );
    } else if (prevEn) {
      english = previous.english;
    } else if (nextEn) {
      english = translated.english;
    } else {
      english = previous.english;
    }
    return PlayerSubtitleLine(
      startTime: previous.startTime,
      english: english,
      chinese: looksChinese(previous.chinese)
          ? previous.chinese
          : (looksChinese(translated.chinese)
                ? translated.chinese
                : previous.chinese),
      startMs: previous.startMs,
      endMs: previous.endMs,
      words: previous.words.isNotEmpty ? previous.words : translated.words,
    );
  }

  static String _englishForCuePair({
    required String existing,
    required String translated,
    required String chinese,
  }) {
    if (!looksChinese(chinese)) {
      if (shouldPreferOcrProof(translated, existing)) {
        return existing;
      }
      return looksEnglish(translated) ? translated : existing;
    }
    if (_sameCueEnglish(existing, translated)) {
      return existing;
    }
    return translated;
  }

  static bool _sameCueEnglish(String existing, String translated) {
    final String left = existing.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final String right = translated.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return left.isNotEmpty && left == right;
  }

  static bool _windowNeedsEnglish(
    List<PlayerSubtitleLine> lines,
    int start,
    int window,
  ) {
    final int end = start + window > lines.length
        ? lines.length
        : start + window;
    for (int i = start; i < end; i++) {
      // Junk OCR (`Uam going…`) still looks like English. Translate it.
      if (!isReliableOcrEnglish(lines[i].english)) {
        return true;
      }
    }
    return false;
  }

  static List<int> _englishFillWindowStarts({
    required int length,
    required int window,
    required List<PlayerSubtitleLine> lines,
    int? prioritizeAroundMs,
  }) {
    if (length <= 0) {
      return const <int>[];
    }
    final List<int> starts = <int>[];
    for (int i = 0; i < length; i += window) {
      starts.add(i);
    }
    if (prioritizeAroundMs == null || starts.length <= 1) {
      return starts;
    }
    int pivotIndex = 0;
    for (int i = 0; i < lines.length; i++) {
      final PlayerSubtitleLine line = lines[i];
      if (prioritizeAroundMs >= line.startMs &&
          prioritizeAroundMs <= line.endMs) {
        pivotIndex = i;
        break;
      }
      if (line.startMs > prioritizeAroundMs) {
        pivotIndex = i;
        break;
      }
      pivotIndex = i;
    }
    final int pivotStart = (pivotIndex ~/ window) * window;
    starts.sort((int a, int b) {
      final int da = (a - pivotStart).abs();
      final int db = (b - pivotStart).abs();
      if (da != db) {
        return da.compareTo(db);
      }
      return a.compareTo(b);
    });
    return starts;
  }

  static Future<List<PlayerSubtitleLine>> _translateMissingStatic({
    required List<PlayerSubtitleLine> lines,
    required LearningSettingsState settings,
    required WordLookupService wordLookup,
    required AsrSubtitleCancellationToken token,
    bool forceFreeParallel = false,
  }) async {
    final MissingSubtitleSide missing = detectMissingSubtitleSide(lines);
    if (missing == MissingSubtitleSide.none) {
      return lines;
    }
    final bool toEnglish =
        missing == MissingSubtitleSide.english ||
        missing == MissingSubtitleSide.both;
    final String targetLanguage = toEnglish ? 'en' : 'zh';
    final List<String> sources = sourceTextsForTranslation(
      lines: lines,
      missing: missing,
    );
    List<String> translations = List<String>.filled(sources.length, '');
    token.throwIfCancelled();
    if (forceFreeParallel || toEnglish) {
      try {
        // Prefer parallel free backends for ZH→EN so Chinese-only B站 tracks
        // become bilingual without requiring a configured AI key.
        final List<String> free = await wordLookup
            .translateSentencesFreeParallel(
              sentences: sources,
              toEnglish: toEnglish,
            );
        for (int i = 0; i < free.length && i < translations.length; i++) {
          translations[i] = free[i];
        }
      } catch (_) {}
      final bool anyFree = translations.any((String t) => t.trim().isNotEmpty);
      if (!anyFree) {
        try {
          final List<String> ai = await wordLookup.translateSentences(
            sentences: sources,
            settings: settings,
            targetLanguage: targetLanguage,
          );
          for (int i = 0; i < ai.length && i < translations.length; i++) {
            translations[i] = ai[i];
          }
        } catch (_) {}
      }
    } else {
      try {
        final List<String> ai = await wordLookup.translateSentences(
          sentences: sources,
          settings: settings,
          targetLanguage: targetLanguage,
        );
        for (int i = 0; i < ai.length && i < translations.length; i++) {
          translations[i] = ai[i];
        }
      } catch (_) {
        final List<String> free = await wordLookup
            .translateSentencesFreeParallel(
              sentences: sources,
              toEnglish: toEnglish,
            );
        for (int i = 0; i < free.length && i < translations.length; i++) {
          translations[i] = free[i];
        }
      }
    }
    // Fill holes with free backends first (avoid slow/broken AI keys).
    for (int i = 0; i < sources.length; i++) {
      token.throwIfCancelled();
      if (translations[i].trim().isNotEmpty) {
        continue;
      }
      final String sentence = sources[i].trim();
      if (sentence.isEmpty) {
        continue;
      }
      final List<String> oneFree = await wordLookup
          .translateSentencesFreeParallel(
            sentences: <String>[sentence],
            toEnglish: toEnglish,
            concurrency: 1,
          );
      String filled = oneFree.isNotEmpty ? oneFree.first.trim() : '';
      if (filled.isEmpty) {
        filled =
            (await wordLookup.translateSentence(
              sentence: sentence,
              settings: settings,
              targetLanguage: targetLanguage,
            ))?.trim() ??
            '';
      }
      if (filled.isEmpty) {
        continue;
      }
      translations[i] = filled;
    }
    return fillMissingSideByTranslation(
      lines: lines,
      missing: missing,
      translations: translations,
    );
  }

  Future<void> startOcr({
    required bool Function() isPlaying,
    required int Function() positionMs,
    bool proofreadExisting = false,
  }) async {
    if (_cancelled) {
      return;
    }
    final List<PlayerSubtitleLine> seed = List<PlayerSubtitleLine>.of(
      getLines(),
    );
    _missing = detectMissingSubtitleSide(seed);
    if (_missing == MissingSubtitleSide.none && !proofreadExisting) {
      _setPhase(BilingualPipelinePhase.completed);
      return;
    }
    final String lockKey = _pipelineLockKey();
    if (!_activePipelines.add(lockKey)) {
      onProgress?.call('双语补全任务已在进行中');
      return;
    }
    _lockKey = lockKey;
    _filledCount = 0;
    final bool chineseTimed = seed.any(
      (PlayerSubtitleLine line) =>
          looksChinese(line.chinese) ||
          (looksChinese(line.english) && !looksEnglish(line.english)),
    );
    // Timed Chinese cues keep the timeline. Never OCR them. Speech (ASR) is
    // the English source — do not ZH→EN in parallel, or paraphrases flood the
    // list and hide audio mismatches for the whole fill.
    if (chineseTimed) {
      try {
        _ocrProofreadOnly = true;
        if (_canRunLocalAsr()) {
          _setPhase(BilingualPipelinePhase.asrProofreading);
          onProgress?.call('正在用语音对齐英文…');
          try {
            await proofreadEnglishWithAsr(force: true);
          } catch (_) {
            // Fall through to translation for remaining holes.
          }
          final MissingSubtitleSide afterAsr = detectMissingSubtitleSide(
            getLines(),
          );
          if (!_cancelled &&
              (afterAsr == MissingSubtitleSide.english ||
                  afterAsr == MissingSubtitleSide.both ||
                  afterAsr == MissingSubtitleSide.chinese)) {
            onProgress?.call('语音对齐后补全缺失侧…');
            _requestTranslationFallback();
          }
        } else if (_missing != MissingSubtitleSide.none) {
          _setPhase(BilingualPipelinePhase.translating);
          onProgress?.call('正在把中文字幕翻译成英文…');
          _requestTranslationFallback();
        } else {
          _setPhase(BilingualPipelinePhase.completed);
          onProgress?.call('双语字幕已就绪');
        }
      } finally {
        _releaseLock();
      }
      return;
    }
    _ocrProofreadOnly =
        proofreadExisting ||
        seed.any(
          (PlayerSubtitleLine line) =>
              looksChinese(line.chinese) ||
              (looksChinese(line.english) && !looksEnglish(line.english)),
        );
    final bool hearVideoOnly =
        proofreadExisting && _missing == MissingSubtitleSide.none;
    if (hearVideoOnly) {
      _setPhase(BilingualPipelinePhase.asrProofreading);
      onProgress?.call('正在用语音对齐英文…');
    } else if (_ocrProofreadOnly) {
      _setPhase(BilingualPipelinePhase.translating);
      onProgress?.call('正在把中文字幕翻译成英文…');
    } else {
      _setPhase(BilingualPipelinePhase.ocrRunning);
      onProgress?.call(statusLabel);
    }

    _slowTimer?.cancel();
    _slowTimer = Timer(slowTimeout, () {
      if (_cancelled) {
        return;
      }
      if ((_phase == BilingualPipelinePhase.ocrRunning ||
              _phase == BilingualPipelinePhase.translating) &&
          _filledCount < minFilledCues) {
        _setPhase(BilingualPipelinePhase.ocrSlow);
        if (_missing == MissingSubtitleSide.chinese) {
          onProgress?.call('画面字幕较慢，可点「AI 补全」');
        } else {
          // Hardsub OCR yielded little English — ask the screen to translate
          // remaining holes (single writer). OCR keeps running to upgrade.
          onProgress?.call('画面英文字幕不足，开始翻译补全…');
          _requestTranslationFallback();
        }
      }
    });

    // OCR-first: burned-in Latin English is more accurate than ZH→EN. Only
    // after [translationFallbackDelay] (or ocrSlow) do we ask for translation.
    // An existing translation is proofread against the video, not replaced
    // by another machine translation.
    _translationFallbackTimer?.cancel();
    if (hearVideoOnly) {
      onProgress?.call('正在用语音对齐英文…');
      unawaited(proofreadEnglishWithAsr());
    }
    _translationFallbackTimer = hearVideoOnly
        ? null
        : Timer(translationFallbackDelay, () {
            if (_cancelled) {
              return;
            }
            final MissingSubtitleSide still = detectMissingSubtitleSide(
              getLines(),
            );
            if (still == MissingSubtitleSide.english ||
                still == MissingSubtitleSide.both) {
              onProgress?.call('画面识别进行中，翻译补其余英文…');
              _requestTranslationFallback();
            }
          });

    final OcrSubtitleSampler active =
        sampler ?? (_ownedSampler ??= OcrSubtitleSampler());
    onProgress?.call(
      hearVideoOnly
          ? '正在用语音对齐英文…'
          : (_ocrProofreadOnly ? '翻译完成后会用语音校对…' : '正在识别画面英文字幕…'),
    );
    await active.start(
      player: player,
      videoPath: videoPath,
      isPlaying: isPlaying,
      positionMs: positionMs,
      onCue: _handleOcrCue,
    );
  }

  void _requestTranslationFallback() {
    if (_cancelled || _translationFallbackStarted) {
      return;
    }
    _translationFallbackStarted = true;
    onNeedTranslationFallback?.call();
  }

  Future<void> _fillEnglishByTranslationKeepOcr() async {
    if (_cancelled) {
      return;
    }
    final AsrSubtitleCancellationToken token = AsrSubtitleCancellationToken();
    try {
      onProgress?.call('正在把中文字幕翻译成英文…');
      _asrToken?.cancel();
      _asrToken = token;
      List<PlayerSubtitleLine> working = List<PlayerSubtitleLine>.of(
        getLines(),
      );
      if (working.isEmpty) {
        return;
      }

      // Translate in small windows so the current cue gets English first,
      // instead of blocking on a full-episode MyMemory batch.
      const int window = 12;
      int cursor = 0;
      int totalGained = 0;
      while (!_cancelled && cursor < working.length) {
        if (detectMissingSubtitleSide(working) == MissingSubtitleSide.none) {
          break;
        }
        final int end = cursor + window > working.length
            ? working.length
            : cursor + window;
        final List<PlayerSubtitleLine> slice = working.sublist(cursor, end);
        final List<PlayerSubtitleLine> filledSlice = await _translateMissing(
          slice,
          token,
        );
        if (_cancelled) {
          return;
        }
        final List<PlayerSubtitleLine> merged = List<PlayerSubtitleLine>.of(
          working,
        );
        for (int i = 0; i < filledSlice.length; i++) {
          merged[cursor + i] = filledSlice[i];
        }
        final int gained = countFilledMissingSide(
          before: working,
          after: merged,
          missing: MissingSubtitleSide.english,
        );
        working = merged;
        if (gained > 0) {
          totalGained += gained;
          _filledCount += gained;
          setLines(working);
          unawaited(_writePartialCache(working));
          onProgress?.call(
            '正在补英文…已完成 ${end.clamp(0, working.length)}/${working.length}',
          );
        }
        cursor = end;
      }

      if (_cancelled) {
        return;
      }
      if (detectMissingSubtitleSide(working) == MissingSubtitleSide.none) {
        onProgress?.call('双语字幕已就绪');
        final Future<void> Function(List<PlayerSubtitleLine> lines)? persist =
            onBilingualReady;
        if (persist != null) {
          unawaited(persist(List<PlayerSubtitleLine>.of(working)));
        }
        // OCR can keep refining hardsubs; mark complete for persistence.
        if (_phase != BilingualPipelinePhase.completed) {
          _setPhase(BilingualPipelinePhase.completed);
        }
      } else if (totalGained > 0) {
        onProgress?.call('已补英文，继续识别画面以提高准确度…');
      } else {
        onProgress?.call('自动翻译未产出英文，继续识别画面字幕…');
      }
    } catch (_) {
      onProgress?.call('自动翻译失败，继续识别画面字幕…');
    } finally {
      if (identical(_asrToken, token)) {
        _asrToken = null;
      }
    }
  }

  Future<void> runAiComplete() async {
    if (_phase == BilingualPipelinePhase.translating ||
        _phase == BilingualPipelinePhase.asrProofreading) {
      return;
    }
    await _stopOcrOnly();
    _cancelled = false;

    final String lockKey = _pipelineLockKey();
    if (_lockKey == null) {
      if (!_activePipelines.add(lockKey)) {
        onProgress?.call('AI 字幕任务已在进行中');
        return;
      }
      _lockKey = lockKey;
    }

    final List<PlayerSubtitleLine> current = List<PlayerSubtitleLine>.of(
      getLines(),
    );
    _missing = detectMissingSubtitleSide(current);
    if (_missing == MissingSubtitleSide.none) {
      _setPhase(BilingualPipelinePhase.completed);
      _releaseLock();
      return;
    }

    final AsrSubtitleCancellationToken token = AsrSubtitleCancellationToken();
    _asrToken?.cancel();
    _asrToken = token;

    try {
      List<PlayerSubtitleLine> working = current;
      if (_missing != MissingSubtitleSide.none) {
        _setPhase(BilingualPipelinePhase.translating);
        onProgress?.call(
          _missing == MissingSubtitleSide.english ? '正在把中文字幕翻译成英文…' : '正在翻译补全…',
        );
        working = await _translateMissing(working, token);
        setLines(working);
      }

      token.throwIfCancelled();
      // Always ASR-proofread when a local MP4 exists: OCR hardsubs often glue
      // words / fragment sentences; Whisper restores complete phrases.
      if (!_canRunLocalAsr()) {
        await _writePartialCache(working);
        if (detectMissingSubtitleSide(working) == MissingSubtitleSide.none) {
          _setPhase(BilingualPipelinePhase.completed);
          onProgress?.call('双语字幕已就绪');
        } else {
          _setPhase(BilingualPipelinePhase.ocrSlow);
          onProgress?.call('本地视频不可用，已尽量翻译补全；可点「重新识别」继续');
        }
        return;
      }

      _setPhase(BilingualPipelinePhase.asrProofreading);
      onProgress?.call('正在语音校对字幕…');

      // Empty reference: a non-empty list is treated as official English and
      // Whisper never runs, so a wrong translation was copied back as-is.
      final String raw = await asrRunner.run(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        referenceSubtitleLines: const <PlayerSubtitleLine>[],
        referenceSignatureOverride: 'pipeline=hear_video',
        forceRegenerate: true,
        cancellationToken: token,
        jobPipeline: 'hear_video',
        onProgress: (AsrSubtitleProgress progress) {
          onProgress?.call(progress.label);
        },
      );

      token.throwIfCancelled();
      final List<PlayerSubtitleLine> asrLines = parseSubtitleLines(raw);
      final List<PlayerSubtitleLine> finalLines;
      if (asrLines.isEmpty) {
        finalLines = working;
      } else if (working.isEmpty ||
          workingEnglishMismatchesAsr(working: working, asrLines: asrLines)) {
        finalLines = rebuildBilingualFromAsrLines(
          working: working,
          asrLines: asrLines,
        );
        onProgress?.call('已按语音时间轴更新字幕');
      } else {
        finalLines = fuseOcrWithAsrLines(working: working, asrLines: asrLines);
      }
      if (finalLines.isNotEmpty) {
        setLines(finalLines);
      }
      await _writePartialCache(finalLines.isNotEmpty ? finalLines : working);
      _setPhase(BilingualPipelinePhase.completed);
      onProgress?.call('双语字幕已就绪');
    } on AsrSubtitleGenerationException catch (error) {
      final bool cancelled =
          token.isCancelled || error.message.contains('取消');
      if (cancelled) {
        _setPhase(BilingualPipelinePhase.cancelled);
        onProgress?.call('已取消');
        return;
      }
      _setPhase(BilingualPipelinePhase.ocrSlow);
      onProgress?.call(humanizeAsrSubtitleError(error));
      rethrow;
    } catch (error) {
      if (token.isCancelled) {
        _setPhase(BilingualPipelinePhase.cancelled);
        onProgress?.call('已取消');
        return;
      }
      _setPhase(BilingualPipelinePhase.ocrSlow);
      onProgress?.call(humanizeAsrSubtitleError(error));
      rethrow;
    } finally {
      if (identical(_asrToken, token)) {
        _asrToken = null;
      }
      _releaseLock();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _asrProofreadStarted = false;
    _slowTimer?.cancel();
    _slowTimer = null;
    _translationFallbackTimer?.cancel();
    _translationFallbackTimer = null;
    _asrToken?.cancel();
    await _stopOcrOnly();
    if (_phase != BilingualPipelinePhase.completed) {
      _setPhase(BilingualPipelinePhase.cancelled);
    }
    _releaseLock();
  }

  Future<void> dispose() async {
    await cancel();
    await _ownedSampler?.dispose();
    _ownedSampler = null;
  }

  void _handleOcrCue(int positionMs, OcrCueText cue) {
    if (_cancelled) {
      return;
    }
    final List<PlayerSubtitleLine> before = getLines();
    final List<PlayerSubtitleLine> after = mergeOcrCueIntoLines(
      lines: before,
      positionMs: positionMs,
      cue: cue,
      proofreadOnly: _ocrProofreadOnly,
    );
    final int gained = countFilledMissingSide(
      before: before,
      after: after,
      missing: _missing,
    );
    // Count OCR English upgrades even when MT already filled the hole —
    // hardsub text should replace machine translation on screen.
    final int ocrEnglishUpgrades = _countOcrEnglishUpgrades(
      before: before,
      after: after,
    );
    if (gained <= 0 &&
        ocrEnglishUpgrades <= 0 &&
        identical(before, after) == false) {
      // Still push merges that only enrich the already-present side lightly.
      final bool changed = !_linesEqual(before, after);
      if (!changed) {
        return;
      }
    }
    if (gained > 0) {
      _filledCount += gained;
    } else if (ocrEnglishUpgrades > 0) {
      _filledCount += ocrEnglishUpgrades;
    }
    setLines(after);
    unawaited(_writePartialCache(after));
    if (_filledCount >= minFilledCues &&
        detectMissingSubtitleSide(after) == MissingSubtitleSide.none) {
      _slowTimer?.cancel();
      _translationFallbackTimer?.cancel();
      unawaited(_finishOcrSuccess());
    } else if (_filledCount >= minFilledCues &&
        _phase == BilingualPipelinePhase.ocrSlow) {
      // Enough yield; keep OCR running silently without nagging AI button.
      onProgress?.call('正在识别画面英文字幕…');
    }
  }

  static int _countOcrEnglishUpgrades({
    required List<PlayerSubtitleLine> before,
    required List<PlayerSubtitleLine> after,
  }) {
    final int n = before.length < after.length ? before.length : after.length;
    int upgrades = 0;
    for (int i = 0; i < n; i++) {
      final String prev = before[i].english.trim();
      final String next = after[i].english.trim();
      if (!looksEnglish(next) || next == prev) {
        continue;
      }
      upgrades += 1;
    }
    return upgrades;
  }

  Future<void> _finishOcrSuccess() async {
    await _stopOcrOnly();
    _translationFallbackTimer?.cancel();
    _translationFallbackTimer = null;
    final List<PlayerSubtitleLine> ready = List<PlayerSubtitleLine>.of(
      getLines(),
    );
    // OCR hardsubs are timed well but often glue words / cut mid-sentence.
    // Follow with ASR whenever the local MP4 is available.
    if (_canRunLocalAsr()) {
      onProgress?.call('画面识别完成，正在语音校对完整句子…');
      try {
        await _proofreadWithAsr(ready);
        return;
      } catch (_) {
        // Fall through to OCR-only completion.
      }
    }
    _setPhase(BilingualPipelinePhase.completed);
    onProgress?.call('双语字幕已就绪');
    if (detectMissingSubtitleSide(getLines()) == MissingSubtitleSide.none) {
      final Future<void> Function(List<PlayerSubtitleLine> lines)? persist =
          onBilingualReady;
      if (persist != null) {
        unawaited(persist(List<PlayerSubtitleLine>.of(getLines())));
      }
    }
    _releaseLock();
  }

  /// Align English to the video with Whisper when a local file exists.
  ///
  /// When speech disagrees with ZH→EN / Chinese timing, ASR owns the timeline.
  Future<void> proofreadEnglishWithAsr({bool force = false}) async {
    if (_cancelled || !_canRunLocalAsr()) {
      return;
    }
    if (_asrProofreadStarted && !force) {
      return;
    }
    if (force) {
      _asrProofreadStarted = false;
      _asrToken?.cancel();
      _asrToken = null;
    }
    final List<PlayerSubtitleLine> working = List<PlayerSubtitleLine>.of(
      getLines(),
    );
    onProgress?.call('正在用语音对齐英文…');
    try {
      await _proofreadWithAsr(working, releaseLock: false, force: force);
    } catch (error) {
      onProgress?.call('语音校对失败：$error');
      rethrow;
    }
  }

  bool _canRunLocalAsr() {
    return !videoPath.startsWith('http://') &&
        !videoPath.startsWith('https://') &&
        File(videoPath).existsSync() &&
        File(videoPath).lengthSync() > 64 * 1024;
  }

  Future<void> _proofreadWithAsr(
    List<PlayerSubtitleLine> working, {
    bool releaseLock = true,
    bool force = false,
  }) async {
    if (_asrProofreadStarted && !force) {
      if (releaseLock) {
        _releaseLock();
      }
      return;
    }
    _asrProofreadStarted = true;
    final AsrSubtitleCancellationToken token = AsrSubtitleCancellationToken();
    _asrToken?.cancel();
    _asrToken = token;
    _setPhase(BilingualPipelinePhase.asrProofreading);
    onProgress?.call('正在语音校对字幕…');
    try {
      // Empty reference: a non-empty list is treated as official English and
      // Whisper never runs, so a wrong translation was copied back as-is.
      final String raw = await asrRunner.run(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        referenceSubtitleLines: const <PlayerSubtitleLine>[],
        referenceSignatureOverride: 'pipeline=hear_video',
        forceRegenerate: true,
        cancellationToken: token,
        jobPipeline: 'hear_video',
        onProgress: (AsrSubtitleProgress progress) {
          onProgress?.call(progress.label);
        },
      );
      token.throwIfCancelled();
      final List<PlayerSubtitleLine> asrLines = parseSubtitleLines(raw);
      final List<PlayerSubtitleLine> live = List<PlayerSubtitleLine>.of(
        getLines(),
      );
      final List<PlayerSubtitleLine> base = live.isNotEmpty ? live : working;
      // hear_video: speech owns the clock. Mismatch / empty working → rebuild.
      final List<PlayerSubtitleLine> finalLines;
      if (asrLines.isEmpty) {
        finalLines = base;
      } else if (base.isEmpty ||
          workingEnglishMismatchesAsr(working: base, asrLines: asrLines)) {
        finalLines = rebuildBilingualFromAsrLines(
          working: base,
          asrLines: asrLines,
        );
        onProgress?.call('已按语音时间轴更新字幕');
      } else {
        finalLines = fuseOcrWithAsrLines(working: base, asrLines: asrLines);
      }
      if (finalLines.isNotEmpty) {
        setLines(finalLines);
      }
      await _writePartialCache(finalLines.isNotEmpty ? finalLines : base);
      _setPhase(BilingualPipelinePhase.completed);
      onProgress?.call('双语字幕已就绪');
      final Future<void> Function(List<PlayerSubtitleLine> lines)? persist =
          onBilingualReady;
      if (persist != null &&
          detectMissingSubtitleSide(
                finalLines.isNotEmpty ? finalLines : base,
              ) ==
              MissingSubtitleSide.none) {
        unawaited(
          persist(
            List<PlayerSubtitleLine>.of(
              finalLines.isNotEmpty ? finalLines : base,
            ),
          ),
        );
      }
    } finally {
      if (identical(_asrToken, token)) {
        _asrToken = null;
      }
      if (releaseLock) {
        _releaseLock();
      }
    }
  }

  Future<void> _stopOcrOnly() async {
    _slowTimer?.cancel();
    _slowTimer = null;
    await sampler?.stop();
    await _ownedSampler?.stop();
  }

  Future<List<PlayerSubtitleLine>> _translateMissing(
    List<PlayerSubtitleLine> lines,
    AsrSubtitleCancellationToken token,
  ) {
    return _translateMissingStatic(
      lines: lines,
      settings: settings,
      wordLookup: wordLookup,
      token: token,
    );
  }

  /// Keep translated/OCR English when ASR returns Chinese-heavy cues.
  List<PlayerSubtitleLine> _mergePreferExistingEnglish(
    List<PlayerSubtitleLine> before,
    List<PlayerSubtitleLine> after,
  ) {
    if (before.isEmpty) {
      return after;
    }
    final List<PlayerSubtitleLine> merged = <PlayerSubtitleLine>[];
    final int n = after.length < before.length ? after.length : before.length;
    for (int i = 0; i < n; i++) {
      final PlayerSubtitleLine prev = before[i];
      final PlayerSubtitleLine next = after[i];
      final bool prevHasEn = looksEnglish(prev.english);
      final bool nextHasEn = looksEnglish(next.english);
      merged.add(
        PlayerSubtitleLine(
          startTime: next.startTime,
          english: nextHasEn
              ? next.english
              : (prevHasEn ? prev.english : next.english),
          chinese: looksChinese(next.chinese)
              ? next.chinese
              : (looksChinese(prev.chinese) ? prev.chinese : next.chinese),
          startMs: next.startMs,
          endMs: next.endMs,
          words: next.words.isNotEmpty ? next.words : prev.words,
        ),
      );
    }
    if (after.length > n) {
      merged.addAll(after.sublist(n));
    } else if (before.length > n) {
      merged.addAll(before.sublist(n));
    }
    return sanitizeSubtitleLanguageFields(merged);
  }

  Future<void> _writePartialCache(List<PlayerSubtitleLine> lines) async {
    try {
      final Directory root =
          await (supportDirectory ?? getApplicationSupportDirectory)();
      final File file = File(
        '${root.path}${Platform.pathSeparator}asr_subtitles'
        '${Platform.pathSeparator}${_safeSegment(episodeId)}'
        '${Platform.pathSeparator}ocr.partial.json',
      );
      await file.parent.create(recursive: true);
      final String content = const JsonEncoder.withIndent('  ').convert(
        <String, Object?>{
          'version': 1,
          'pipeline': 'ocr',
          'episodeId': episodeId,
          'videoPath': videoPath,
          'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
          'lines': lines
              .map(
                (PlayerSubtitleLine line) => <String, Object?>{
                  'startTime': line.startTime,
                  'english': line.english,
                  'chinese': line.chinese,
                  'startMs': line.startMs,
                  'endMs': line.endMs,
                },
              )
              .toList(growable: false),
        },
      );
      await file.writeAsString(content, flush: true);
      // Also promote to words cache when bilingual enough so follow-along works.
      if (detectMissingSubtitleSide(lines) == MissingSubtitleSide.none) {
        final String words = const JsonEncoder.withIndent('  ').convert(
          <String, Object?>{
            'version': 1,
            'language': 'en',
            'pipeline': 'ocr',
            'lines': lines
                .map(
                  (PlayerSubtitleLine line) => <String, Object?>{
                    'startTime': line.startTime,
                    'english': line.english,
                    'chinese': line.chinese,
                    'startMs': line.startMs,
                    'endMs': line.endMs,
                    'words': line.words
                        .map(
                          (PlayerSubtitleWord w) => <String, Object?>{
                            'text': w.text,
                            'startMs': w.startMs,
                            'endMs': w.endMs,
                            if (w.confidence != null)
                              'confidence': w.confidence,
                          },
                        )
                        .toList(growable: false),
                  },
                )
                .toList(growable: false),
          },
        );
        await cache.write(
          episodeId: episodeId,
          videoPath: videoPath,
          content: words,
          settings: settings,
          referenceSignature:
              'pipeline=ocr|${subtitleReferenceSignature(lines)}',
        );
      }
    } catch (_) {}
  }

  void _setPhase(BilingualPipelinePhase next) {
    _phase = next;
    onPhaseChanged?.call(next);
  }

  void _releaseLock() {
    final String? key = _lockKey;
    if (key != null) {
      _activePipelines.remove(key);
      _lockKey = null;
    }
  }

  String _pipelineLockKey() => '$episodeId|$videoPath|bilingual_pipeline';

  String _safeSegment(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp('_+'), '_');
  }

  bool _linesEqual(List<PlayerSubtitleLine> a, List<PlayerSubtitleLine> b) {
    if (identical(a, b)) {
      return true;
    }
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].english != b[i].english ||
          a[i].chinese != b[i].chinese ||
          a[i].startMs != b[i].startMs ||
          a[i].endMs != b[i].endMs) {
        return false;
      }
    }
    return true;
  }
}
