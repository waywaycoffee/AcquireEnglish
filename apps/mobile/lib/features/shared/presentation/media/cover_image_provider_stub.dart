import 'package:flutter/widgets.dart';

ImageProvider<Object>? coverImageProviderForPath(String path) {
  if (path.isEmpty) {
    return null;
  }
  if (path.startsWith('assets/')) {
    return AssetImage(path);
  }
  return null;
}
