import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'subtitle_file_persist.dart';

enum ManualSubtitleDestructiveAction { delete, overwrite }

/// True when this episode has any hand-edited EN/ZH lock on disk or in memory.
Future<bool> episodeHasManualSubtitleEdits({
  required String episodeId,
  Map<int, String>? englishLocks,
  Map<int, String>? chineseLocks,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  if ((englishLocks?.isNotEmpty ?? false) ||
      (chineseLocks?.isNotEmpty ?? false)) {
    return true;
  }
  final Map<int, String> en = await loadManualEnglishLocks(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  if (en.isNotEmpty) {
    return true;
  }
  final Map<int, String> zh = await loadManualChineseLocks(
    episodeId: episodeId,
    appSupportDirectory: appSupportDirectory,
  );
  return zh.isNotEmpty;
}

bool lineHasManualSubtitleEdit({
  required int startMs,
  required Map<int, String> englishLocks,
  required Map<int, String> chineseLocks,
}) {
  return (englishLocks[startMs] ?? '').trim().isNotEmpty ||
      (chineseLocks[startMs] ?? '').trim().isNotEmpty;
}

Future<void> clearManualSubtitleLocks({
  required String episodeId,
  Future<Directory> Function() appSupportDirectory =
      getApplicationSupportDirectory,
}) async {
  await saveManualEnglishLocks(
    episodeId: episodeId,
    locks: const <int, String>{},
    appSupportDirectory: appSupportDirectory,
  );
  await saveManualChineseLocks(
    episodeId: episodeId,
    locks: const <int, String>{},
    appSupportDirectory: appSupportDirectory,
  );
}

/// Strong confirm when wiping hand-edited subtitles. Returns false if cancelled.
Future<bool> confirmManualSubtitleDestructiveAction(
  BuildContext context, {
  required ManualSubtitleDestructiveAction action,
  bool forSingleLine = false,
}) async {
  final String verb = action == ManualSubtitleDestructiveAction.delete
      ? '删除'
      : '覆盖';
  final String subject = forSingleLine ? '本句' : '本视频';
  final bool? confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => AlertDialog(
      title: Text('$subject已手工改过字幕'),
      content: Text('是否$verb？$verb后不可恢复。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('仍然$verb'),
        ),
      ],
    ),
  );
  return confirmed == true;
}
