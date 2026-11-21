import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../player/presentation/ocr_subtitle_sampler.dart';

/// Local JPEG cache of a video frame at [positionMs] for review cards.
class ReviewClipFrameCache {
  const ReviewClipFrameCache();

  Future<File?> resolve({
    required String episodeId,
    required String videoPath,
    required int positionMs,
  }) async {
    final String id = episodeId.trim();
    final String path = videoPath.trim();
    if (id.isEmpty || path.isEmpty || !File(path).existsSync()) {
      return null;
    }
    final int ms = positionMs < 0 ? 0 : positionMs;
    final Directory root = await getApplicationSupportDirectory();
    final Directory dir = Directory('${root.path}/review_frames');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final String safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final File cached = File('${dir.path}/$safeId-$ms.jpg');
    if (cached.existsSync() && cached.lengthSync() > 64) {
      return cached;
    }
    final Uint8List? bytes = await OcrSubtitleSampler.defaultCaptureFrame(
      player: null,
      videoPath: path,
      positionMs: ms,
    );
    if (bytes == null || bytes.isEmpty) return null;
    await cached.writeAsBytes(bytes, flush: true);
    return cached;
  }
}
