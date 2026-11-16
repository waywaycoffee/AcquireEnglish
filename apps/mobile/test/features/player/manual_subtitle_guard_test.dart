import 'dart:io';

import 'package:common_learn_english/features/player/presentation/manual_subtitle_guard.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_file_persist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('manual-subtitle-guard-');
  });

  tearDown(() async {
    if (tempRoot.existsSync()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<Directory> support() async => tempRoot;

  test('detects in-memory locks without reading disk', () async {
    final bool has = await episodeHasManualSubtitleEdits(
      episodeId: 'ep-1',
      englishLocks: <int, String>{1000: 'Hello'},
      chineseLocks: const <int, String>{},
      appSupportDirectory: support,
    );
    expect(has, isTrue);
  });

  test('detects disk locks and clears them', () async {
    await saveManualEnglishLocks(
      episodeId: 'ep-2',
      locks: <int, String>{2000: 'World'},
      appSupportDirectory: support,
    );
    expect(
      await episodeHasManualSubtitleEdits(
        episodeId: 'ep-2',
        appSupportDirectory: support,
      ),
      isTrue,
    );
    await clearManualSubtitleLocks(
      episodeId: 'ep-2',
      appSupportDirectory: support,
    );
    expect(
      await episodeHasManualSubtitleEdits(
        episodeId: 'ep-2',
        appSupportDirectory: support,
      ),
      isFalse,
    );
  });

  test('lineHasManualSubtitleEdit checks both sides', () {
    expect(
      lineHasManualSubtitleEdit(
        startMs: 1,
        englishLocks: const <int, String>{},
        chineseLocks: <int, String>{1: '你好'},
      ),
      isTrue,
    );
    expect(
      lineHasManualSubtitleEdit(
        startMs: 2,
        englishLocks: const <int, String>{1: 'Hi'},
        chineseLocks: const <int, String>{},
      ),
      isFalse,
    );
  });
}
