import 'dart:io';

/// Containers AVFoundation / MediaCodec usually handle well without FFmpeg.
bool prefersNativeMediaTools(String path) {
  final String lower = path.trim().toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.3gp') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav');
}

/// MKV / WebM / etc. — prefer FFmpegKit first (especially on iOS).
bool prefersFfmpegMediaTools(String path) => !prefersNativeMediaTools(path);

bool isLocalMediaFile(String path) {
  final String trimmed = path.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return false;
  }
  return File(trimmed).existsSync();
}
