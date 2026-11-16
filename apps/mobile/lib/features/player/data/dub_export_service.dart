import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../presentation/desktop_ffmpeg.dart';
import 'dub_session_store.dart';

const MethodChannel _audioToolsChannel = MethodChannel(
  'com.shadowing.english/audio_tools',
);

class DubExportResult {
  const DubExportResult({
    required this.outputPath,
    required this.usedAccompaniment,
    required this.duckedDialogue,
  });

  final String outputPath;
  final bool usedAccompaniment;
  final bool duckedDialogue;
}

/// Exports a dubbed MP4 for a time range or the full set of takes.
class DubExportService {
  const DubExportService();

  Future<DubExportResult> export({
    required String episodeId,
    required String videoSource,
    required List<DubTake> takes,
    int? rangeStartMs,
    int? rangeEndMs,
    String? accompanimentPath,
  }) async {
    if (takes.isEmpty) {
      throw StateError('还没有配音录音可导出。');
    }
    if (videoSource.isEmpty || !File(videoSource).existsSync()) {
      throw StateError('本地视频不可用，无法导出配音。');
    }
    final List<DubTake> scoped = takes.where((DubTake take) {
      if (rangeStartMs == null || rangeEndMs == null) {
        return true;
      }
      return take.endMs > rangeStartMs && take.startMs < rangeEndMs;
    }).toList(growable: false);
    if (scoped.isEmpty) {
      throw StateError('所选范围内没有配音。');
    }

    final int startMs = rangeStartMs ??
        scoped.map((DubTake t) => t.startMs).reduce((int a, int b) => a < b ? a : b);
    final int endMs = rangeEndMs ??
        scoped.map((DubTake t) => t.endMs).reduce((int a, int b) => a > b ? a : b);
    final Directory temp = await getTemporaryDirectory();
    final String output =
        '${temp.path}/dub-$episodeId-$startMs-$endMs-${DateTime.now().millisecondsSinceEpoch}.mp4';

    final bool hasAccomp =
        accompanimentPath != null && File(accompanimentPath).existsSync();

    if (!kIsWeb && Platform.isAndroid) {
      final String? nativePath = await _exportAndroid(
        videoSource: videoSource,
        outputPath: output,
        startMs: startMs,
        endMs: endMs,
        takes: scoped,
        accompanimentPath: hasAccomp ? accompanimentPath : null,
      );
      if (nativePath != null && File(nativePath).existsSync()) {
        return DubExportResult(
          outputPath: nativePath,
          usedAccompaniment: hasAccomp,
          duckedDialogue: !hasAccomp,
        );
      }
    }

    final String? ffmpeg = await findDesktopFfmpeg();
    if (ffmpeg == null) {
      throw StateError('当前设备无法导出配音视频（缺少 FFmpeg / 原生混音）。');
    }
    await _exportWithFfmpeg(
      ffmpeg: ffmpeg,
      videoSource: videoSource,
      outputPath: output,
      startMs: startMs,
      endMs: endMs,
      takes: scoped,
      accompanimentPath: hasAccomp ? accompanimentPath : null,
    );
    return DubExportResult(
      outputPath: output,
      usedAccompaniment: hasAccomp,
      duckedDialogue: !hasAccomp,
    );
  }

  Future<String?> _exportAndroid({
    required String videoSource,
    required String outputPath,
    required int startMs,
    required int endMs,
    required List<DubTake> takes,
    String? accompanimentPath,
  }) async {
    try {
      final Object? result = await _audioToolsChannel.invokeMethod<Object?>(
        'exportDubbedVideo',
        <String, Object?>{
          'sourcePath': videoSource,
          'outputPath': outputPath,
          'startMs': startMs,
          'endMs': endMs,
          'accompanimentPath': accompanimentPath,
          'takes': takes
              .map(
                (DubTake t) => <String, Object?>{
                  'startMs': t.startMs,
                  'endMs': t.endMs,
                  'wavPath': t.userWavPath,
                },
              )
              .toList(growable: false),
        },
      );
      if (result is String && result.isNotEmpty) {
        return result;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _exportWithFfmpeg({
    required String ffmpeg,
    required String videoSource,
    required String outputPath,
    required int startMs,
    required int endMs,
    required List<DubTake> takes,
    String? accompanimentPath,
  }) async {
    final Directory temp = await getTemporaryDirectory();
    final String filterScript =
        '${temp.path}/dub-filter-${DateTime.now().microsecondsSinceEpoch}.txt';

    // Build amix graph: base (accomp or ducked original) + each take delayed.
    final StringBuffer filter = StringBuffer();
    final List<String> args = <String>[
      '-hide_banner',
      '-loglevel',
      'error',
      '-y',
      '-ss',
      (startMs / 1000).toStringAsFixed(3),
      '-t',
      ((endMs - startMs) / 1000).toStringAsFixed(3),
      '-i',
      videoSource,
    ];
    int inputIndex = 1;
    if (accompanimentPath != null) {
      args.addAll(<String>[
        '-ss',
        (startMs / 1000).toStringAsFixed(3),
        '-t',
        ((endMs - startMs) / 1000).toStringAsFixed(3),
        '-i',
        accompanimentPath,
      ]);
      filter.write('[$inputIndex:a]aformat=sample_rates=44100:channel_layouts=stereo[base];');
      inputIndex += 1;
    } else {
      // Duck original audio inside each take window.
      final StringBuffer volumeExpr = StringBuffer();
      for (int i = 0; i < takes.length; i++) {
        final DubTake take = takes[i];
        final double a = ((take.startMs - startMs) / 1000).clamp(0, 1e9);
        final double b = ((take.endMs - startMs) / 1000).clamp(0, 1e9);
        if (i > 0) {
          volumeExpr.write('+');
        }
        volumeExpr.write(
          'between(t\\,$a\\,$b)',
        );
      }
      filter.write(
        '[0:a]volume=\'if(${volumeExpr.isEmpty ? '0' : volumeExpr},0.05,1)\':eval=frame,aformat=sample_rates=44100:channel_layouts=stereo[base];',
      );
    }

    final List<String> mixLabels = <String>['[base]'];
    for (final DubTake take in takes) {
      args.addAll(<String>['-i', take.userWavPath]);
      final int delayMs = (take.startMs - startMs).clamp(0, 1 << 30);
      filter.write(
        '[$inputIndex:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay=$delayMs|$delayMs[t$inputIndex];',
      );
      mixLabels.add('[t$inputIndex]');
      inputIndex += 1;
    }
    filter.write(
      '${mixLabels.join('')}amix=inputs=${mixLabels.length}:duration=longest:dropout_transition=0[aout]',
    );
    await File(filterScript).writeAsString(filter.toString(), flush: true);

    args.addAll(<String>[
      '-filter_complex_script',
      filterScript,
      '-map',
      '0:v:0',
      '-map',
      '[aout]',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-shortest',
      outputPath,
    ]);

    final ProcessResult result = await Process.run(ffmpeg, args);
    try {
      await File(filterScript).delete();
    } catch (_) {}
    if (result.exitCode != 0 || !File(outputPath).existsSync()) {
      final String err = '${result.stderr}'.trim();
      throw StateError(err.isEmpty ? 'FFmpeg 导出配音失败。' : 'FFmpeg 导出失败：$err');
    }
  }
}
