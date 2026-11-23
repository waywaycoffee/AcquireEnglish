/// Compact progress for FAB / system overlay.
///
/// Format: `已完成{done}（{current%}%）/{total}`
/// e.g. `已完成3（7%）/16`
String formatSubtitleFillCompactLabel({
  required int doneCount,
  required int totalCount,
  required int currentPercent,
}) {
  final int total = totalCount < 1 ? 1 : totalCount;
  final int done = doneCount.clamp(0, total);
  final int pct = currentPercent.clamp(0, 99);
  return '已完成$done（$pct%）/$total';
}

double subtitleFillOverallProgress({
  required int doneCount,
  required int totalCount,
  required double currentFraction,
}) {
  final int total = totalCount < 1 ? 1 : totalCount;
  final double frac = currentFraction.clamp(0.0, 0.99);
  return ((doneCount.clamp(0, total) + frac) / total).clamp(0.05, 0.99);
}

/// Parse live worker labels like `语音识别 1/14 段（7%）` into 0–1.
/// Prefers explicit `（N%）` / `N%` over bare `a/b` fractions.
double progressFractionFromSubtitleLabel(String label) {
  final String live = label.trim();
  if (live.isEmpty) {
    return 0.08;
  }
  // Shared/cloud cache ready — not local Whisper progress.
  if (isSubtitleSharedCacheReadyLabel(live)) {
    return 1.0;
  }
  if (live.contains('云端正在翻译')) {
    return 0.72;
  }
  if (live.contains('云端正在识别')) {
    return 0.42;
  }
  if (live.contains('云端生成重试')) {
    return 0.22;
  }
  if (live.contains('云端排队') || live.contains('推送云端') || live.contains('云端生成字幕')) {
    return 0.15;
  }
  if (live.contains('云端字幕已完成')) {
    return 0.95;
  }
  final RegExpMatch? pct =
      RegExp(r'（(\d{1,3})%）').firstMatch(live) ??
      RegExp(r'(?<![0-9:])(\d{1,3})%').firstMatch(live);
  if (pct != null) {
    final int value = int.tryParse(pct.group(1) ?? '') ?? 0;
    return (value / 100).clamp(0.0, 0.99);
  }
  // `1/14 段` — segment progress inside one episode (not job counts).
  final RegExpMatch? segments = RegExp(
    r'(\d+)\s*/\s*(\d+)\s*段',
  ).firstMatch(live);
  if (segments != null) {
    final int done = int.tryParse(segments.group(1) ?? '') ?? 0;
    final int total = int.tryParse(segments.group(2) ?? '') ?? 0;
    if (total > 0) {
      return (done / total).clamp(0.0, 0.99);
    }
  }
  return 0.08;
}

/// Honest copy when Bilibili shared/cloud subtitle cache fully satisfies needs.
const String kSubtitleSharedCacheReadyLabel = '字幕已就绪（秒开）';

/// Transparent hint that a verified shared pack was used (not local Whisper).
const String kSubtitleSharedCacheHintLabel = '已使用校验字幕缓存以加快导入';

/// Combined ready + hint for status chips / course banner.
const String kSubtitleSharedCacheReadyDetailLabel =
    '$kSubtitleSharedCacheReadyLabel · $kSubtitleSharedCacheHintLabel';

/// Partial shared hit: cache helped, local fill still running for the rest.
const String kSubtitleSharedCachePartialLabel =
    '已使用校验字幕缓存，正在补齐其余字幕…';

/// Looking up shared pack before cloud generation (not local ASR progress).
const String kSubtitleSharedCacheLookupLabel = '正在检查校验字幕缓存…';

/// Local still missing after shared lookup — durable ECS GPU job accepted.
const String kSubtitleCloudGenerationQueuedLabel = '云端排队生成字幕中…';

/// Map ECS GPU job `state` (+ optional worker message) to a user-visible label.
String labelForGpuSubtitleJobState(
  String? state, {
  String? progressMessage,
  double? progressPct,
}) {
  final String live = (progressMessage ?? '').trim();
  if (live.isNotEmpty) {
    if (progressPct != null && progressPct > 0 && progressPct < 1) {
      final int pct = (progressPct * 100).round().clamp(1, 99);
      if (!live.contains('%') && !live.contains('（')) {
        return '$live（$pct%）';
      }
    }
    return live;
  }
  switch ((state ?? '').trim().toLowerCase()) {
    case 'transcribing':
      return '云端正在识别英文字幕…';
    case 'translating':
      return '云端正在翻译中文字幕…';
    case 'retry':
      return '云端生成重试中…';
    case 'completed':
      return '云端字幕已完成，正在同步…';
    case 'failed':
      return '云端字幕生成失败';
    case 'queued':
    default:
      return kSubtitleCloudGenerationQueuedLabel;
  }
}

/// Prefer worker `progress_pct` when present; otherwise coarse state buckets.
double progressFractionForGpuSubtitleJobState(
  String? state, {
  double? progressPct,
}) {
  if (progressPct != null && progressPct.isFinite) {
    return progressPct.clamp(0.05, 0.99);
  }
  switch ((state ?? '').trim().toLowerCase()) {
    case 'transcribing':
      return 0.42;
    case 'translating':
      return 0.72;
    case 'completed':
      return 0.95;
    case 'retry':
      return 0.22;
    case 'failed':
      return 0.0;
    case 'queued':
    default:
      return 0.15;
  }
}

bool isSubtitleCloudGenerationQueuedLabel(String? label) {
  final String live = (label ?? '').trim();
  return live.contains('推送云端生成') ||
      live.contains('云端排队生成') ||
      live.contains('云端生成字幕') ||
      live.contains('云端正在识别') ||
      live.contains('云端正在翻译') ||
      live.contains('云端生成重试');
}

bool isSubtitleSharedCacheReadyLabel(String? label) {
  final String live = (label ?? '').trim();
  if (live.isEmpty) {
    return false;
  }
  // Exclude in-progress shared-cache messages (lookup / partial fill).
  if (live.contains('正在补齐') || live.contains('正在检查')) {
    return false;
  }
  return live.contains('秒开') ||
      (live.contains('校验字幕缓存') && live.contains('已就绪'));
}

bool isSubtitleFillTerminalLabel(String? label) {
  final String live = (label ?? '').trim();
  if (live.isEmpty) {
    return false;
  }
  // Cloud queued is waiting, not a finished fill.
  if (isSubtitleCloudGenerationQueuedLabel(live)) {
    return false;
  }
  return live.contains('已补全') ||
      live.contains('失败') ||
      isSubtitleSharedCacheReadyLabel(live);
}
