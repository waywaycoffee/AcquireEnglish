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
    this.slowTimeout = const Duration(seconds: 12),
    this.minFilledCues = 2,
    this.sampler,
    this.wordLookup = const WordLookupService(),
    this.asrRunner = const AsrSubtitleJobRunner(),
    this.cache = const AsrSubtitleCache(),
    this.supportDirectory,
  });

  final String episodeId;
  final String videoPath;
  final LearningSettingsState settings;
  final BilingualLinesGetter getLines;
  final BilingualLinesSetter setLines;
  final Player? player;
  final BilingualPhaseListener? onPhaseChanged;
  final BilingualProgressListener? onProgress;
  final Duration slowTimeout;
  final int minFilledCues;
  final OcrSubtitleSampler? sampler;
  final WordLookupService wordLookup;
  final AsrSubtitleJobRunner asrRunner;
  final AsrSubtitleCache cache;
  final Future<Directory> Function()? supportDirectory;

  static final Set<String> _activePipelines = <String>{};

  BilingualPipelinePhase _phase = BilingualPipelinePhase.idle;
  MissingSubtitleSide _missing = MissingSubtitleSide.none;
  OcrSubtitleSampler? _ownedSampler;
  Timer? _slowTimer;
  int _filledCount = 0;
  bool _cancelled = false;
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

  Future<void> startOcr({
    required bool Function() isPlaying,
    required int Function() positionMs,
  }) async {
    if (_cancelled) {
      return;
    }
    final List<PlayerSubtitleLine> seed = List<PlayerSubtitleLine>.of(getLines());
    _missing = detectMissingSubtitleSide(seed);
    if (_missing == MissingSubtitleSide.none) {
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
    _setPhase(BilingualPipelinePhase.ocrRunning);
    onProgress?.call(statusLabel);

    _slowTimer?.cancel();
    _slowTimer = Timer(slowTimeout, () {
      if (_cancelled) {
        return;
      }
      if (_phase == BilingualPipelinePhase.ocrRunning &&
          _filledCount < minFilledCues) {
        _setPhase(BilingualPipelinePhase.ocrSlow);
        onProgress?.call('画面字幕较慢，可点「AI 补全」');
      }
    });

    final OcrSubtitleSampler active =
        sampler ?? (_ownedSampler ??= OcrSubtitleSampler());
    await active.start(
      player: player,
      videoPath: videoPath,
      isPlaying: isPlaying,
      positionMs: positionMs,
      onCue: _handleOcrCue,
    );
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
    _asrToken = token;

    try {
      List<PlayerSubtitleLine> working = current;
      if (_missing == MissingSubtitleSide.chinese ||
          _missing == MissingSubtitleSide.both) {
        _setPhase(BilingualPipelinePhase.translating);
        onProgress?.call('正在翻译补全…');
        working = await _translateMissing(working, token);
        setLines(working);
      }

      token.throwIfCancelled();
      _setPhase(BilingualPipelinePhase.asrProofreading);
      onProgress?.call('正在语音校对…');

      final List<PlayerSubtitleLine> referenceForAsr =
          usableReferenceSubtitles(working);
      final String raw = await asrRunner.run(
        episodeId: episodeId,
        videoPath: videoPath,
        settings: settings,
        referenceSubtitleLines: referenceForAsr.isNotEmpty
            ? referenceForAsr
            : working,
        referenceSignatureOverride:
            'pipeline=ai_complete|${subtitleReferenceSignature(working)}',
        forceRegenerate: true,
        cancellationToken: token,
        jobPipeline: 'ai_complete',
        onProgress: (AsrSubtitleProgress progress) {
          onProgress?.call(progress.label);
        },
      );

      token.throwIfCancelled();
      final List<PlayerSubtitleLine> finalLines = parseSubtitleLines(raw);
      if (finalLines.isNotEmpty) {
        setLines(finalLines);
      }
      await _writePartialCache(finalLines.isNotEmpty ? finalLines : working);
      _setPhase(BilingualPipelinePhase.completed);
      onProgress?.call('双语字幕已就绪');
    } on AsrSubtitleGenerationException catch (error) {
      final bool cancelled =
          _asrToken?.isCancelled == true || error.message.contains('取消');
      if (cancelled) {
        _setPhase(BilingualPipelinePhase.cancelled);
        onProgress?.call('已取消');
        return;
      }
      _setPhase(BilingualPipelinePhase.ocrSlow);
      onProgress?.call(humanizeAsrSubtitleError(error));
      rethrow;
    } catch (error) {
      if (_asrToken?.isCancelled == true) {
        _setPhase(BilingualPipelinePhase.cancelled);
        onProgress?.call('已取消');
        return;
      }
      _setPhase(BilingualPipelinePhase.ocrSlow);
      onProgress?.call(humanizeAsrSubtitleError(error));
      rethrow;
    } finally {
      _asrToken = null;
      _releaseLock();
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _slowTimer?.cancel();
    _slowTimer = null;
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
    );
    final int gained = countFilledMissingSide(
      before: before,
      after: after,
      missing: _missing,
    );
    if (gained <= 0 && identical(before, after) == false) {
      // Still push merges that only enrich the already-present side lightly.
      final bool changed = !_linesEqual(before, after);
      if (!changed) {
        return;
      }
    }
    if (gained > 0) {
      _filledCount += gained;
    }
    setLines(after);
    unawaited(_writePartialCache(after));
    if (_filledCount >= minFilledCues &&
        detectMissingSubtitleSide(after) == MissingSubtitleSide.none) {
      _slowTimer?.cancel();
      unawaited(_finishOcrSuccess());
    } else if (_filledCount >= minFilledCues &&
        _phase == BilingualPipelinePhase.ocrSlow) {
      // Enough yield; keep OCR running silently without nagging AI button.
      onProgress?.call('正在识别画面字幕…');
    }
  }

  Future<void> _finishOcrSuccess() async {
    await _stopOcrOnly();
    _setPhase(BilingualPipelinePhase.completed);
    onProgress?.call('双语字幕已就绪');
    _releaseLock();
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
  ) async {
    final MissingSubtitleSide missing = detectMissingSubtitleSide(lines);
    if (missing == MissingSubtitleSide.none ||
        missing == MissingSubtitleSide.english) {
      // EN fill is handled by ASR; WordLookupService is EN→ZH only.
      return lines;
    }
    final List<String> sources = sourceTextsForTranslation(
      lines: lines,
      missing: missing,
    );
    final List<String> translations = <String>[];
    const int batch = 40;
    for (int offset = 0; offset < sources.length; offset += batch) {
      token.throwIfCancelled();
      final int end = offset + batch > sources.length
          ? sources.length
          : offset + batch;
      final List<String> chunk = sources.sublist(offset, end);
      final List<int> nonemptyIndexes = <int>[];
      final List<String> nonemptyTexts = <String>[];
      for (int i = 0; i < chunk.length; i++) {
        final String text = chunk[i].trim();
        if (text.isEmpty) {
          continue;
        }
        nonemptyIndexes.add(i);
        nonemptyTexts.add(text);
      }
      try {
        final List<String> translated = nonemptyTexts.isEmpty
            ? const <String>[]
            : await wordLookup.translateSentences(
                sentences: nonemptyTexts,
                settings: settings,
              );
        final List<String> filled = List<String>.filled(chunk.length, '');
        for (int i = 0; i < nonemptyIndexes.length; i++) {
          filled[nonemptyIndexes[i]] =
              i < translated.length ? translated[i].trim() : '';
        }
        translations.addAll(filled);
      } catch (_) {
        for (final String sentence in chunk) {
          token.throwIfCancelled();
          if (sentence.trim().isEmpty) {
            translations.add('');
            continue;
          }
          final String? one = await wordLookup.translateSentence(
            sentence: sentence,
            settings: settings,
          );
          translations.add(one ?? '');
        }
      }
    }
    return fillMissingSideByTranslation(
      lines: lines,
      missing: missing,
      translations: translations,
    );
  }

  Future<void> _writePartialCache(List<PlayerSubtitleLine> lines) async {
    try {
      final Directory root = await (supportDirectory ??
          getApplicationSupportDirectory)();
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
                            if (w.confidence != null) 'confidence': w.confidence,
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
          referenceSignature: 'pipeline=ocr|${subtitleReferenceSignature(lines)}',
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
