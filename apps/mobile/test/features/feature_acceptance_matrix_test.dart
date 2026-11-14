import 'dart:io';

import 'package:common_learn_english/features/import_course/data/bilibili_course_builder.dart';
import 'package:common_learn_english/features/import_course/data/bilibili_import_service.dart';
import 'package:common_learn_english/features/player/data/oral_coach_pipeline_client.dart';
import 'package:common_learn_english/features/player/presentation/bilingual_subtitle_helpers.dart';
import 'package:common_learn_english/features/player/presentation/player_mock_state.dart';
import 'package:common_learn_english/features/settings/presentation/settings_provider.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_enqueue.dart';
import 'package:common_learn_english/features/subtitle_completion/subtitle_completion_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// Product feature acceptance matrix (unit-level).
///
/// Each group maps to a user-facing capability that must stay green.
void main() {
  group('F01 设置默认与生产地址', () {
    test('默认 LiveKit / 陪练管线指向生产托管', () {
      final LearningSettingsState defaults = LearningSettingsState.defaults();
      expect(
        defaults.liveKitUrl,
        contains('acquireenglish-e5la1koz.livekit.cloud'),
      );
      expect(
        defaults.oralCoachPipelineUrl,
        'https://acquireenglish.curlhairai.com/coach',
      );
      expect(defaults.usesOralCoachPipeline, isTrue);
    });

    test('拼写错误的管线域名会被纠正为 curlhairai', () {
      const String broken =
          'https://acquireenglish.caurlhairai.com/coach';
      expect(
        fixCurlhairaiTypoHost(broken),
        'https://acquireenglish.curlhairai.com/coach',
      );
      expect(fixCurlhairaiTypoHost(''), isEmpty);
      expect(
        fixCurlhairaiTypoHost('https://acquireenglish.curlhairai.com/'),
        'https://acquireenglish.curlhairai.com/',
      );
    });
  });

  group('F02 导入时检查中英字幕缺失', () {
    late Directory temp;
    late SubtitleCompletionQueue queue;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('ae-f02-');
      queue = SubtitleCompletionQueue(appSupportDirectory: () async => temp);
    });

    tearDown(() {
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    });

    File fakeVideo(String name) {
      final File video = File('${temp.path}/$name');
      video.writeAsBytesSync(List<int>.filled(65 * 1024, 1));
      return video;
    }

    test('缺英文有中文 → 入队 needEnglish', () async {
      final File video = fakeVideo('a.mp4');
      final File zh = File('${temp.path}/zh.srt')
        ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\n你好\n');
      await enqueueSubtitleCompletionForEpisode(
        episodeId: 'f02-en',
        videoPath: video.path,
        zhSubtitlePath: zh.path,
        queue: queue,
        appSupportDirectory: () async => temp,
      );
      final SubtitleCompletionJob job = (await queue.loadJobs()).single;
      expect(job.needEnglish, isTrue);
      expect(job.needChinese, isFalse);
    });

    test('缺中文有英文 → 入队 needChinese', () async {
      final File video = fakeVideo('b.mp4');
      final File en = File('${temp.path}/official/en.srt')
        ..createSync(recursive: true)
        ..writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
      await enqueueSubtitleCompletionForEpisode(
        episodeId: 'f02-zh',
        videoPath: video.path,
        enSubtitlePath: en.path,
        queue: queue,
        appSupportDirectory: () async => temp,
      );
      final SubtitleCompletionJob job = (await queue.loadJobs()).single;
      expect(job.needEnglish, isFalse);
      expect(job.needChinese, isTrue);
    });

    test('中英皆缺 → 两边同时入队', () async {
      final File video = fakeVideo('c.mp4');
      await enqueueSubtitleCompletionForEpisode(
        episodeId: 'f02-both',
        videoPath: video.path,
        force: true,
        queue: queue,
        appSupportDirectory: () async => temp,
      );
      final SubtitleCompletionJob job = (await queue.loadJobs()).single;
      expect(job.needEnglish, isTrue);
      expect(job.needChinese, isTrue);
    });

    test('导入成功文案区分缺英文 / 缺中文 / 皆缺', () {
      String hintFor({String? en, String? zh, String? note}) {
        return bilibiliImportSuccessHint(
          BilibiliImportResult(
            idKey: 'BVtest',
            title: 't',
            watchUrl: 'https://www.bilibili.com/video/BVtest',
            durationMinutes: 10,
            author: 'o',
            localVideoPath: '/tmp/v.mp4',
            enSubtitlePath: en,
            cnSubtitlePath: zh,
            subtitleNote: note,
          ),
        );
      }

      expect(hintFor(en: '/e.srt', zh: '/z.srt'), contains('中英官方字幕'));
      expect(hintFor(en: '/e.srt'), contains('缺中文'));
      expect(hintFor(zh: '/z.srt'), contains('缺英文'));
      expect(hintFor(), contains('中英皆缺'));
    });
  });

  group('F03 字幕与语音不一致时按 ASR 时间轴更新', () {
    test('workingEnglishMismatchesAsr 识别 ZH→EN 串台', () {
      final List<PlayerSubtitleLine> working = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:10',
          english: 'How many bowls do they have?',
          chinese: '它们有多少个碗',
          startMs: 10000,
          endMs: 12000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:12',
          english: 'Totally unrelated sentence here',
          chinese: '完全无关',
          startMs: 12000,
          endMs: 14000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:14',
          english: 'Another wrong paraphrase line',
          chinese: '又一错句',
          startMs: 14000,
          endMs: 16000,
        ),
      ];
      final List<PlayerSubtitleLine> asr = <PlayerSubtitleLine>[
        const PlayerSubtitleLine(
          startTime: '00:10',
          english: 'One, two, three.',
          chinese: '',
          startMs: 10000,
          endMs: 12000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:12',
          english: 'Look at the leaves.',
          chinese: '',
          startMs: 12000,
          endMs: 14000,
        ),
        const PlayerSubtitleLine(
          startTime: '00:14',
          english: 'Very tasty.',
          chinese: '',
          startMs: 14000,
          endMs: 16000,
        ),
      ];
      expect(
        workingEnglishMismatchesAsr(working: working, asrLines: asr),
        isTrue,
      );
    });

    test('rebuildBilingualFromAsrLines 以 ASR 为时钟并保留中文', () {
      final List<PlayerSubtitleLine> rebuilt = rebuildBilingualFromAsrLines(
        working: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:10',
            english: 'Wrong',
            chinese: '一二三',
            startMs: 10000,
            endMs: 13000,
          ),
        ],
        asrLines: const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:10',
            english: 'One, two, three.',
            chinese: '',
            startMs: 10000,
            endMs: 12000,
          ),
        ],
      );
      expect(rebuilt.single.english, 'One, two, three.');
      expect(rebuilt.single.chinese, '一二三');
      expect(rebuilt.single.endMs, 12000);
    });

    test('时长串台守卫能发现超长字幕', () {
      expect(
        subtitleTimelineExceedsMedia(
          subtitleEndMs: 30 * 60 * 1000,
          mediaDurationMs: 22 * 60 * 1000,
        ),
        isTrue,
      );
    });
  });

  group('F04 口语陪练管线客户端契约', () {
    test('OralCoachVideoContext / difficulty 字段可序列化语义', () {
      const OralCoachVideoContext ctx = OralCoachVideoContext(
        courseTitle: '资料库',
        episodeTitle: '08',
        currentEnglish: 'But look at that view.',
        currentChinese: '但看看这景色',
      );
      expect(ctx.currentEnglish, contains('view'));
      expect(ctx.currentChinese, isNotEmpty);
    });
  });

  group('F05 缺失侧检测', () {
    test('detectMissingSubtitleSide 中文轨缺英文', () {
      expect(
        detectMissingSubtitleSide(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: '',
            chinese: '你好',
            startMs: 0,
            endMs: 1000,
          ),
        ]),
        MissingSubtitleSide.english,
      );
    });

    test('双语齐全 → none', () {
      expect(
        detectMissingSubtitleSide(const <PlayerSubtitleLine>[
          PlayerSubtitleLine(
            startTime: '00:01',
            english: 'Hello there friend',
            chinese: '你好朋友',
            startMs: 0,
            endMs: 1000,
          ),
        ]),
        MissingSubtitleSide.none,
      );
    });
  });
}
