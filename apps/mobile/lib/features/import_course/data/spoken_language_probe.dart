/// Probe whether a video has audible English speech (not just EN softsubs).
///
/// Current catalog `spokenLanguage` is import-time metadata and is often empty
/// for Feed/auto-cached Bilibili items — it must NOT be treated as audio ASR.
///
/// Planned detection (separate from softsub language):
/// 1. Sample ~30–60s of local audio (or ECS media proxy).
/// 2. Run lightweight language-ID / ASR (on-device whisper.cpp or GPU worker).
/// 3. Persist result on the course/episode (`spokenLanguage=en|zh|mixed|unknown`).
///
/// Until that ships, callers should treat [SpokenLanguageProbeResult.unknown]
/// as "do not assume English speech from captions alone".
enum SpokenLanguageProbeResult {
  english,
  chinese,
  mixed,
  unknown,
}

class SpokenLanguageProbe {
  const SpokenLanguageProbe();

  /// Metadata-only fallback. Does not analyze audio.
  SpokenLanguageProbeResult fromMetadata(String? spokenLanguageHint) {
    final String spoken = (spokenLanguageHint ?? '').trim().toLowerCase();
    if (spoken == 'en' || spoken.startsWith('en')) {
      return SpokenLanguageProbeResult.english;
    }
    if (spoken == 'zh' || spoken.startsWith('zh')) {
      return SpokenLanguageProbeResult.chinese;
    }
    if (spoken == 'auto' || spoken == 'mixed') {
      return SpokenLanguageProbeResult.mixed;
    }
    return SpokenLanguageProbeResult.unknown;
  }

  /// Placeholder for real audio language-ID. Always [unknown] for now.
  Future<SpokenLanguageProbeResult> probeLocalVideo(String? videoPath) async {
    // TODO(speech-lid): sample audio + call ASR/LID pipeline.
    return SpokenLanguageProbeResult.unknown;
  }
}
