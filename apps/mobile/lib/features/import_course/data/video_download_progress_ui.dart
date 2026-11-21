import 'bilibili_collection_download.dart';
import 'netdisk_local_download.dart';

/// Unified active video-download snapshot for FAB / system overlay.
class ActiveVideoDownload {
  const ActiveVideoDownload({
    required this.courseId,
    required this.message,
    required this.progress,
    required this.compactLabel,
  });

  final String courseId;
  final String message;
  final double progress;
  final String compactLabel;
}

/// Prefer bilibili 合集 download; fall back to netdisk local download.
ActiveVideoDownload? resolveActiveVideoDownload({
  BilibiliCollectionDownloadProgress? bilibili,
  NetdiskDownloadProgress? netdisk,
}) {
  if (bilibili != null && !bilibili.done) {
    return ActiveVideoDownload(
      courseId: bilibili.courseId,
      message: bilibili.message,
      progress: bilibili.progress.clamp(0.0, 1.0),
      compactLabel: formatVideoDownloadCompactLabel(
        message: bilibili.message,
        progress: bilibili.progress,
        successCount: bilibili.successCount,
      ),
    );
  }
  if (netdisk != null && !netdisk.done) {
    return ActiveVideoDownload(
      courseId: netdisk.courseId,
      message: netdisk.message,
      progress: netdisk.progress.clamp(0.0, 1.0),
      compactLabel: formatVideoDownloadCompactLabel(
        message: netdisk.message,
        progress: netdisk.progress,
        current: netdisk.current,
        total: netdisk.total,
      ),
    );
  }
  return null;
}

/// Compact pill text, e.g. `3/10（45%）` or `45%`.
String formatVideoDownloadCompactLabel({
  required String message,
  required double progress,
  int successCount = 0,
  int current = 0,
  int total = 0,
}) {
  final int pct = (progress.clamp(0.0, 1.0) * 100).round().clamp(0, 99);
  final RegExpMatch? frac = RegExp(r'（\s*(\d+)\s*/\s*(\d+)\s*）').firstMatch(
    message,
  );
  if (frac != null) {
    final int cur = int.tryParse(frac.group(1) ?? '') ?? 0;
    final int tot = int.tryParse(frac.group(2) ?? '') ?? 0;
    if (tot > 0) {
      return '$cur/$tot（$pct%）';
    }
  }
  if (total > 0 && current > 0) {
    return '$current/$total（$pct%）';
  }
  final RegExpMatch? slash = RegExp(r'(\d+)\s*/\s*(\d+)\s*集').firstMatch(
    message,
  );
  if (slash != null) {
    final int cur = int.tryParse(slash.group(1) ?? '') ?? 0;
    final int tot = int.tryParse(slash.group(2) ?? '') ?? 0;
    if (tot > 0) {
      return '$cur/$tot（$pct%）';
    }
  }
  if (successCount > 0) {
    return '已下$successCount（$pct%）';
  }
  return '下载 $pct%';
}
