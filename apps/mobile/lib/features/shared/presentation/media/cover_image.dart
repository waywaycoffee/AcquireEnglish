import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'cover_image_provider.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({
    required this.path,
    required this.fit,
    this.errorBuilder,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    final String normalized = _normalizeRemote(path);
    final ImageProvider<Object>? provider = _isRemote(normalized)
        ? NetworkImage(
            normalized,
            headers: const <String, String>{
              'Referer': 'https://www.bilibili.com',
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            },
          )
        : coverImageProviderForPath(normalized);
    if (provider == null) {
      return _buildFallback(
        context,
        StateError('Unsupported or empty local cover path: $path'),
      );
    }

    // Remote covers: avoid ResizeImage — some Android stacks drop NetworkImage
    // headers / fail decode when wrapped. Local files still use size buckets.
    if (_isRemote(normalized)) {
      return Image(
        image: provider,
        fit: fit,
        errorBuilder: errorBuilder,
        gaplessPlayback: true,
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double logicalSize = math.max(
          constraints.hasBoundedWidth ? constraints.maxWidth : 0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 0,
        );
        final double pixelSize = logicalSize > 0
            ? logicalSize * MediaQuery.devicePixelRatioOf(context)
            : 1024;
        // Bucket sizes to reuse cached thumbnails while resizing the window.
        // Bound the longest edge and preserve the source aspect ratio.
        final int decodeSize = ((pixelSize / 64).ceil() * 64).clamp(64, 2048);
        return Image(
          image: ResizeImage(
            provider,
            width: decodeSize,
            height: decodeSize,
            policy: ResizeImagePolicy.fit,
          ),
          fit: fit,
          errorBuilder: errorBuilder,
          gaplessPlayback: true,
        );
      },
    );
  }

  bool _isRemote(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  String _normalizeRemote(String value) {
    final String trimmed = value.trim();
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('http://')) {
      return 'https://${trimmed.substring('http://'.length)}';
    }
    return trimmed;
  }

  Widget _buildFallback(BuildContext context, Object error) {
    if (errorBuilder != null) {
      return errorBuilder!(context, error, null);
    }
    return const SizedBox.shrink();
  }
}
