import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/player/presentation/subtitle_sentence_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeAsrIntoSentences', () {
    test('merges adjacent ASR crumbs into one English sentence', () {
      const List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '17:16',
          english: 'There is',
          chinese: '',
          startMs: 1036000,
          endMs: 1036800,
        ),
        PlayerSubtitleLine(
          startTime: '17:16',
          english: 'a lot of water',
          chinese: '',
          startMs: 1036900,
          endMs: 1039000,
        ),
      ];
      const List<PlayerSubtitleLine> chinese = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '17:16',
          english: '',
          chinese: '是',
          startMs: 1036679,
          endMs: 1037799,
        ),
        PlayerSubtitleLine(
          startTime: '17:19',
          english: '',
          chinese: '地上到处都是水',
          startMs: 1039459,
          endMs: 1044179,
        ),
      ];

      final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
        asrLines: asr,
        chineseLines: chinese,
      );

      expect(bundle.sentences, hasLength(1));
      expect(bundle.sentences.single.english, 'There is a lot of water');
      expect(bundle.sentences.single.chinese, contains('是'));
      expect(bundle.fragments, hasLength(2));
      expect(bundle.fragments.first.chinese, '是');
    });

    test('does not merge across a large pause or sentence end', () {
      const List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:01',
          english: 'Look at that.',
          chinese: '',
          startMs: 1000,
          endMs: 2000,
        ),
        PlayerSubtitleLine(
          startTime: '00:04',
          english: 'And those are calves.',
          chinese: '',
          startMs: 4000,
          endMs: 5500,
        ),
      ];

      final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
        asrLines: asr,
      );

      expect(bundle.sentences, hasLength(2));
      expect(bundle.sentences[0].english, 'Look at that.');
      expect(bundle.sentences[1].english, 'And those are calves.');
    });

    test('joins overlapping Chinese cues onto one sentence', () {
      const List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:10',
          english: 'I am going to cut the tree',
          chinese: '',
          startMs: 10000,
          endMs: 13000,
        ),
      ];
      const List<PlayerSubtitleLine> chinese = <PlayerSubtitleLine>[
        PlayerSubtitleLine(
          startTime: '00:10',
          english: '',
          chinese: '我要去',
          startMs: 10000,
          endMs: 11000,
        ),
        PlayerSubtitleLine(
          startTime: '00:11',
          english: '',
          chinese: '砍树',
          startMs: 11000,
          endMs: 12500,
        ),
      ];

      final MergedSubtitleBundle bundle = mergeAsrIntoSentences(
        asrLines: asr,
        chineseLines: chinese,
      );

      expect(bundle.sentences.single.chinese, '我要去 砍树');
      expect(bundle.sentences.single.fragmentStartMs, <int>[10000, 11000]);
      final Map<int, List<PlayerSubtitleLine>> byStart =
          bundle.fragmentsBySentenceStartMs();
      expect(byStart[10000], hasLength(2));
      expect(byStart[10000]!.first.chinese, '我要去');
    });
  });
}
