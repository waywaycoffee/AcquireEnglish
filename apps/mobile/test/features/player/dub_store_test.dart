import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../../lib/features/player/data/dub_session_store.dart';

void main() {
  test(
    'durable history, scoring updates and selected version survive reload',
    () async {
      final Directory directory = Directory.systemTemp.createTempSync(
        'dub-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final File wav = File('${directory.path}/input.wav')
        ..writeAsBytesSync(<int>[1, 2, 3]);
      final DubSessionStore store = DubSessionStore.forDirectory(directory);
      DubTake take(int version, {int? score}) => DubTake(
        episodeId: 'episode',
        lineId: '0-1000',
        startMs: 0,
        endMs: 1000,
        english: 'Hello',
        userWavPath: wav.path,
        createdAt: DateTime.fromMillisecondsSinceEpoch(version),
        scorePercent: score,
      );
      await store.saveTake(take(1));
      await store.saveTake(take(1, score: 80));
      expect((await store.loadTakes('episode', history: true)).length, 1);
      await store.saveTake(take(2));
      final List<DubTake> history = await store.loadTakes(
        'episode',
        history: true,
      );
      expect(history.length, 2);
      expect(
        (await store.loadTakes('episode')).single.createdAt,
        take(2).createdAt,
      );
      await store.saveTake(history.first);
      final DubSessionStore reopened = DubSessionStore.forDirectory(directory);
      expect((await reopened.loadTakes('episode')).single.scorePercent, 80);
      expect((await reopened.loadTakes('episode', history: true)).length, 2);
      wav.deleteSync();
      expect((await reopened.loadTakes('episode')).single.fileExists, isTrue);
    },
  );
}
