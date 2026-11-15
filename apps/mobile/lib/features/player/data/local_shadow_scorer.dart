import 'dart:io';

import '../../settings/presentation/settings_provider.dart';
import '../domain/shadow_word_overlap.dart';
import '../presentation/local_whisper_asr.dart';
import 'voice_practice_client.dart';

/// On-device shadowing score: local Whisper transcript + word-overlap.
class LocalShadowScorer {
  const LocalShadowScorer();

  Future<VoiceShadowResult> score({
    required LearningSettingsState settings,
    required String referenceText,
    required String audioPath,
    LocalWhisperProgress? onProgress,
  }) async {
    final String reference = referenceText.trim();
    if (reference.isEmpty) {
      throw StateError('没有可对照的英文句子。');
    }
    final File file = File(audioPath);
    if (!file.existsSync()) {
      throw StateError('录音文件不存在。');
    }
    final Map<String, Object?> raw = await LocalWhisperAsr.instance.transcribeChunk(
      file: file,
      settings: settings,
      offsetMs: 0,
      language: 'en',
      onProgress: onProgress,
    );
    final String transcript = _transcriptFromWhisper(raw);
    final ShadowWordOverlap overlap = ShadowWordOverlap.compare(
      reference,
      transcript,
    );
    return VoiceShadowResult(
      id: 'local-${DateTime.now().millisecondsSinceEpoch}',
      referenceText: reference,
      transcript: transcript,
      duration: 0,
      mock: false,
      overlap: VoiceShadowOverlap(
        score: overlap.score,
        precision: overlap.precision,
        recall: overlap.recall,
        missingWords: overlap.missingWords,
        extraWords: overlap.extraWords,
        referenceWords: overlap.referenceWords,
        hypothesisWords: overlap.hypothesisWords,
      ),
      label: '本地 Whisper · 词重叠反馈（非官方发音分）',
    );
  }

  /// Soft fallback when ASR / cloud scoring is unavailable.
  VoiceShadowResult durationHeuristic({
    required String referenceText,
    required int referenceMs,
    required int recordingMs,
  }) {
    final String reference = referenceText.trim();
    final int refMs = referenceMs <= 0 ? 1 : referenceMs;
    final double ratio = recordingMs / refMs;
    // Prefer near 0.7–1.3× reference length as a rough “said something”.
    final double score;
    if (recordingMs < 300) {
      score = 0;
    } else if (ratio >= 0.7 && ratio <= 1.35) {
      score = 0.55;
    } else if (ratio >= 0.45 && ratio <= 1.8) {
      score = 0.35;
    } else {
      score = 0.15;
    }
    final List<String> refWords = ShadowWordOverlap.tokenize(reference);
    return VoiceShadowResult(
      id: 'duration-${DateTime.now().millisecondsSinceEpoch}',
      referenceText: reference,
      transcript: '',
      duration: recordingMs / 1000.0,
      mock: true,
      overlap: VoiceShadowOverlap(
        score: score,
        precision: score,
        recall: score,
        missingWords: refWords,
        extraWords: const <String>[],
        referenceWords: refWords.length,
        hypothesisWords: 0,
      ),
      label: '时长粗评（未识别内容）· 请检查本地 Whisper 模型或 Voice 地址',
    );
  }

  static String _transcriptFromWhisper(Map<String, Object?> raw) {
    final Object? linesRaw = raw['lines'];
    if (linesRaw is! List) {
      return '';
    }
    final List<String> parts = <String>[];
    for (final Object? item in linesRaw) {
      if (item is! Map) {
        continue;
      }
      final String english = '${item['english'] ?? ''}'.trim();
      final String chinese = '${item['chinese'] ?? ''}'.trim();
      final String text = english.isNotEmpty ? english : chinese;
      if (text.isNotEmpty) {
        parts.add(text);
      }
    }
    return parts.join(' ').trim();
  }
}
