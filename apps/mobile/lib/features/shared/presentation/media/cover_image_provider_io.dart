import 'dart:io';

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
  return FileImage(file);
}
