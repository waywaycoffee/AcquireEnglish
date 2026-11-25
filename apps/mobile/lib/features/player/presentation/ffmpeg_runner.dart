import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';

import 'desktop_ffmpeg.dart';

class FfmpegRunResult {
  const FfmpegRunResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// True when a local ffmpeg CLI or the Android/iOS FFmpegKit bundle is usable.
Future<bool> isFfmpegAvailable() async {
  if (kIsWeb) return false;
  if (Platform.isAndroid || Platform.isIOS) return true;
  return (await findDesktopFfmpeg()) != null;
}

/// Compatibility alias used by extract/export call sites.
Future<bool> isMobileFfmpegAvailable() => isFfmpegAvailable();

/// Run ffmpeg with [args] (without the `ffmpeg` binary name).
///
/// Mobile uses the bundled FFmpegKit native libraries; desktop uses the
/// packaged/system CLI discovered by [findDesktopFfmpeg].
Future<FfmpegRunResult> runFfmpeg(List<String> args) async {
  if (kIsWeb) {
    return const FfmpegRunResult(
      exitCode: 127,
      stderr: 'ffmpeg unavailable on web',
    );
  }
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final ReturnCode? code = await session.getReturnCode();
      final String logs = (await session.getAllLogsAsString()) ?? '';
      final int exitCode =
          ReturnCode.isSuccess(code) ? 0 : (code?.getValue() ?? 1);
      return FfmpegRunResult(exitCode: exitCode, stderr: logs);
    } catch (error) {
      return FfmpegRunResult(exitCode: 1, stderr: '$error');
    }
  }
  final String? ffmpeg = await findDesktopFfmpeg();
  if (ffmpeg == null) {
    return const FfmpegRunResult(exitCode: 127, stderr: 'ffmpeg not found');
  }
  try {
    final ProcessResult result = await Process.run(ffmpeg, args);
    final Object? out = result.stdout;
    final Object? err = result.stderr;
    return FfmpegRunResult(
      exitCode: result.exitCode,
      stdout: out is String
          ? out
          : (out is List<int> ? String.fromCharCodes(out) : ''),
      stderr: err is String
          ? err
          : (err is List<int> ? String.fromCharCodes(err) : ''),
    );
  } catch (error) {
    return FfmpegRunResult(exitCode: 1, stderr: '$error');
  }
}
