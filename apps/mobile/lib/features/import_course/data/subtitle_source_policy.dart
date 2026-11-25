import '../../library/presentation/library_mock_data.dart';

/// SmartSub-style decision: official softsubs optional; hardsub / dirty → ASR.
class SubtitleSourceDecision {
  const SubtitleSourceDecision({
    required this.ignoreAllOfficialSoftsubs,
    required this.ignoreOfficialChinese,
    required this.forceAsr,
    required this.useOfficialEnglish,
    required this.dropLoadedSoftsubs,
    required this.reason,
  });

  /// Hardsub / duration-poisoned: wipe EN+ZH softsubs and force speech.
  final bool ignoreAllOfficialSoftsubs;

  /// Keep EN softsubs when present; never trust JSON ZH (AI-zh / hardsub ZH).
  final bool ignoreOfficialChinese;

  /// Missing or untrusted English → run Whisper/cloud ASR.
  final bool forceAsr;

  /// Reliable official EN may skip Whisper (still optional proofread).
  final bool useOfficialEnglish;

  /// Player should clear currently loaded soft/ASR cues before paint.
  final bool dropLoadedSoftsubs;

  /// Human/log reason (妙幕式可读).
  final String reason;

  SubtitleSourceDecision copyWith({
    bool? ignoreAllOfficialSoftsubs,
    bool? ignoreOfficialChinese,
    bool? forceAsr,
    bool? useOfficialEnglish,
    bool? dropLoadedSoftsubs,
    String? reason,
  }) {
    return SubtitleSourceDecision(
      ignoreAllOfficialSoftsubs:
          ignoreAllOfficialSoftsubs ?? this.ignoreAllOfficialSoftsubs,
      ignoreOfficialChinese:
          ignoreOfficialChinese ?? this.ignoreOfficialChinese,
      forceAsr: forceAsr ?? this.forceAsr,
      useOfficialEnglish: useOfficialEnglish ?? this.useOfficialEnglish,
      dropLoadedSoftsubs: dropLoadedSoftsubs ?? this.dropLoadedSoftsubs,
      reason: reason ?? this.reason,
    );
  }
}

/// Shared subtitle-source policy for import, player open, and completion queue.
abstract final class SubtitleSourcePolicy {
  // Do not match「内嵌字幕」— that usually means soft embedded tracks, not burn-in.
  static final RegExp hardsubHintPattern = RegExp(
    r'中英字幕|双语字幕|硬字幕|双语|英语学习|字幕版|硬字幕版|烧录字幕',
  );

  static bool isHardsubHint({
    LibraryEpisodeItem? episode,
    LibraryCourseData? course,
    String? sourceUrl,
    String? pagePart,
    String? title,
    String? description,
    String? videoAsset,
  }) {
    final String blob =
        '${episode?.title ?? ''} ${course?.title ?? ''} '
        '${course?.description ?? ''} ${description ?? ''} '
        '${title ?? ''} ${sourceUrl ?? ''} ${pagePart ?? ''} '
        '${videoAsset ?? ''} ${episode?.videoAsset ?? ''} '
        '${episode?.sourceUrl ?? ''}';
    return hardsubHintPattern.hasMatch(blob);
  }

  /// Netdisk MKV with no soft/embedded tracks is usually burned-in 硬字幕.
  static bool looksLikeNetdiskHardsub({
    LibraryEpisodeItem? episode,
    LibraryCourseData? course,
    String? videoAsset,
    String? sourceUrl,
    required bool hasSoftsubFiles,
    required bool hasEmbeddedSoftTracks,
  }) {
    if (hasSoftsubFiles || hasEmbeddedSoftTracks) {
      return false;
    }
    if (isHardsubHint(
      episode: episode,
      course: course,
      sourceUrl: sourceUrl,
      videoAsset: videoAsset,
    )) {
      return true;
    }
    final String path =
        '${videoAsset ?? ''} ${episode?.videoAsset ?? ''} '
        '${episode?.sourceUrl ?? ''} ${sourceUrl ?? ''} '
        '${episode?.title ?? ''}';
    final String lower = path.toLowerCase();
    return lower.contains('.mkv') ||
        lower.contains('netdisk') ||
        lower.contains('/api/netdisk/play/');
  }

  /// Episode-level decision before cue bodies are trusted.
  static SubtitleSourceDecision decideEpisode({
    LibraryEpisodeItem? episode,
    LibraryCourseData? course,
    String? sourceUrl,
    String? pagePart,
    String? title,
    String? description,
    String? videoAsset,
  }) {
    // Hardsub / 双语课 still prefer official softsubs when B站 provides them.
    // Only fall back to speech ASR for missing sides — never wipe official CC
    // just because the title mentions 硬字幕/中英字幕.
    if (isHardsubHint(
      episode: episode,
      course: course,
      sourceUrl: sourceUrl,
      pagePart: pagePart,
      title: title,
      description: description,
      videoAsset: videoAsset,
    )) {
      return const SubtitleSourceDecision(
        ignoreAllOfficialSoftsubs: false,
        ignoreOfficialChinese: false,
        forceAsr: false,
        useOfficialEnglish: true,
        dropLoadedSoftsubs: false,
        reason: '硬字幕/双语课：有官方软字幕优先使用；缺侧再语音/翻译补全',
      );
    }
    return const SubtitleSourceDecision(
      ignoreAllOfficialSoftsubs: false,
      ignoreOfficialChinese: false,
      forceAsr: false,
      useOfficialEnglish: true,
      dropLoadedSoftsubs: false,
      reason: '有可靠官方英文字幕时优先使用；缺英文再语音识别',
    );
  }

  /// After softsubs/ASR cues are loaded — decide fill / drop.
  ///
  /// Duration mismatch = classic 合集串台 (wrong episode's SRT under this BV).
  /// Drop those automatically; do not ask the user to「清空/重新识别」.
  static SubtitleSourceDecision refineLoaded({
    required SubtitleSourceDecision base,
    required bool hasReliableEnglish,
    required bool chineseOnlySoft,
    required bool durationMismatch,
    required bool usingAsrSentences,
  }) {
    if (durationMismatch && !usingAsrSentences) {
      return base.copyWith(
        useOfficialEnglish: false,
        forceAsr: true,
        ignoreOfficialChinese: true,
        ignoreAllOfficialSoftsubs: true,
        dropLoadedSoftsubs: true,
        reason: '字幕时长与视频不符（疑似串台），已丢弃并改走语音补全',
      );
    }
    if (hasReliableEnglish || usingAsrSentences) {
      return base.copyWith(
        useOfficialEnglish: hasReliableEnglish,
        forceAsr: !hasReliableEnglish && !usingAsrSentences,
        ignoreOfficialChinese: false,
        ignoreAllOfficialSoftsubs: false,
        dropLoadedSoftsubs: false,
        reason: hasReliableEnglish
            ? '使用官方/已加载英文字幕'
            : '使用已生成的语音字幕',
      );
    }

    if (chineseOnlySoft) {
      return base.copyWith(
        useOfficialEnglish: false,
        forceAsr: true,
        ignoreOfficialChinese: false,
        ignoreAllOfficialSoftsubs: false,
        dropLoadedSoftsubs: false,
        reason: '仅有中文软字幕，英语走语音识别补全（保留中文）',
      );
    }

    return base.copyWith(
      useOfficialEnglish: false,
      forceAsr: true,
      ignoreAllOfficialSoftsubs: false,
      dropLoadedSoftsubs: false,
      reason: '无可靠英文字幕，使用语音识别补全',
    );
  }

  /// Whether to skip a B站 Chinese softsub track during download.
  ///
  /// Always keep platform softsubs (human or AI). Hardsub burned into the
  /// video is unrelated; soft CC on the page must not be deleted so ASR can
  /// "regenerate" Chinese/English.
  static bool shouldSkipOfficialChineseTrack({
    required String lan,
    required String lanDoc,
    required bool isAiTrack,
    required bool hardsubPage,
  }) {
    return false;
  }
}
