import 'dart:io';

import 'package:common_learn_english/features/player/data/dub_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'concurrent completed takes count once each, including a scoring retry',
    () async {
      final Directory folder = await Directory.systemTemp.createTemp(
        'dub-count',
      );
      addTearDown(() => folder.delete(recursive: true));
      final File wav = await File(
        '${folder.path}/test.wav',
      ).writeAsBytes(<int>[1]);
      final DubSessionStore store = DubSessionStore.forDirectory(folder);
      DubTake take(int id, {int? score}) => DubTake(
        episodeId: 'episode-a',
        lineId: '1000-2000',
        startMs: 1000,
        endMs: 2000,
        english: 'Hello.',
        userWavPath: wav.path,
        createdAt: DateTime.utc(2026, 11, 20, 8, 0, id),
        scorePercent: score,
      );

      await Future.wait(<Future<void>>[
        store.saveTake(take(1)),
        store.saveTake(take(2)),
        store.saveTake(take(1, score: 95)),
      ]);
      final List<DubTake> history = await store.loadTakes(
        'episode-a',
        history: true,
      );
      expect(history, hasLength(2));
      expect(
        history
            .singleWhere((DubTake value) => value.createdAt.second == 1)
            .scorePercent,
        95,
      );
    },
  );
}
