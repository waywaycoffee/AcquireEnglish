import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

ImageProvider<Object>? coverImageProviderForPath(String path) {
  if (path.isEmpty) {
    return null;
  }
  if (path.startsWith('assets/')) {
    return AssetImage(path);
  }
  final File file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  return Platform.isWindows ? _UnlockedFileImage(file) : FileImage(file);
}

// Decode from owned bytes on Windows so the engine does not keep the source
// file memory-mapped while a cached thumbnail is alive.
class _UnlockedFileImage extends FileImage {
  const _UnlockedFileImage(super.file);

  @override
  ImageStreamCompleter loadBuffer(FileImage key, DecoderBufferCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _decodeBuffer(decode),
      scale: scale,
      debugLabel: file.path,
    );
  }

  Future<ui.Codec> _decodeBuffer(DecoderBufferCallback decode) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    return decode(buffer);
  }

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _decode(decode),
      scale: scale,
      debugLabel: file.path,
    );
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    return decode(buffer);
  }
}
