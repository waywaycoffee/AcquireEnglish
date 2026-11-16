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
