import 'dart:io';

import 'package:common_learn_english/features/library/presentation/library_mock_data.dart';
import 'package:common_learn_english/features/onboarding/domain/onboarding_profile.dart';
import 'package:common_learn_english/features/onboarding/presentation/focus_recommendation.dart';
import 'package:common_learn_english/features/reading/domain/reading_doc.dart';
import 'package:common_learn_english/features/sync/data/acquire_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('four focuses deep-link to their modules', () {
    expect(focusById('video')?.route, '/library');
    expect(focusById('reading')?.route, '/reading');
    expect(focusById('oral')?.route, '/learn/dialogue');
    expect(focusById('vocab')?.route, '/words/syllabus');
  });

  test('resolvedLevel maps ability ids', () {
    expect(const OnboardingProfile(abilityId: 'beginner').resolvedLevel, '零基础');
    expect(const OnboardingProfile(abilityId: 'words').resolvedLevel, 'A2');
    expect(const OnboardingProfile(abilityId: 'daily').resolvedLevel, 'B1');
    expect(const OnboardingProfile().resolvedLevel, 'A2');
  });

  test('syllable and phonics flags drive skippable hints', () {
    const OnboardingProfile profile = OnboardingProfile(
      focusId: 'oral',
      canSyllableSplit: false,
      learnedPhonics: false,
    );
    expect(profile.showSyllableHints, isTrue);
    expect(profile.showPhonicsHints, isTrue);
    expect(profile.warmUpRoutes, <String>['/learn/ipa', '/learn/phonics']);
  });

  test('json round-trip keeps focusId and legacy keys', () {
    const OnboardingProfile original = OnboardingProfile(
      interestIds: <String>['tech', 'travel'],
      ageBandId: 'college',
      focusId: 'reading',
      abilityId: 'words',
      canSyllableSplit: true,
      learnedPhonics: false,
      completed: true,
    );
    final OnboardingProfile restored = OnboardingProfile.fromJson(
      original.toJson(),
    );
    expect(restored.focusId, 'reading');
    expect(restored.primaryModeId, 'reading');
    expect(restored.interestIds, <String>['tech', 'travel']);
    expect(restored.learnedPhonics, isFalse);
  });

  test('reading + tech + simple sentences recommends reading route', () {
    final FocusRecommendation rec = buildFocusRecommendation(
      profile: const OnboardingProfile(
        interestIds: <String>['tech'],
        focusId: 'reading',
        abilityId: 'words',
      ),
      prefs: const AcquirePreferencesDto(level: 'A2'),
      courses: const <LibraryCourseData>[],
      readingDocs: const <ReadingDoc>[
        ReadingDoc(
          id: 'builtin_a2_lost_key',
          title: 'The Lost Key',
          sourceType: ReadingSourceType.builtin,
          plainText: 'Tom could not find his house key.',
          level: 'A2',
          builtin: true,
        ),
        ReadingDoc(
          id: 'builtin_a2_tech_robot',
          title: 'A Robot in the School Library',
          sourceType: ReadingSourceType.builtin,
          plainText: 'A robot carries books.',
          level: 'A2',
          builtin: true,
        ),
      ],
      activeBook: null,
    );
    expect(rec.focus.id, 'reading');
    expect(rec.route, '/reading/builtin_a2_tech_robot');
    expect(rec.title, contains('Robot'));
  });

  test('video recommendation prefers episode with English softsub', () {
    final Directory tmp = Directory.systemTemp.createTempSync('onboard_rec_');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final File enSrt = File('${tmp.path}/en.srt')
      ..writeAsStringSync(
        '1\n00:00:00,000 --> 00:00:01,000\nHello from Minecraft English.\n',
      );
    LibraryEpisodeItem ep({
      required String id,
      required String title,
      String? enPath,
    }) => LibraryEpisodeItem(
      id: id,
      numberStr: '1',
      title: title,
      durationMinutes: 10,
      hasChineseSubtitles: true,
      hasEnglishSubtitles: enPath != null,
      completed: false,
      progressPercent: 0,
      coverImage: '',
      videoAsset: '${tmp.path}/$id.mp4',
      enSubtitleAsset: enPath,
    );
    final FocusRecommendation rec = buildFocusRecommendation(
      profile: const OnboardingProfile(
        interestIds: <String>['games'],
        focusId: 'video',
        abilityId: 'words',
      ),
      prefs: const AcquirePreferencesDto(level: 'A2'),
      courses: <LibraryCourseData>[
        LibraryCourseData(
          id: 'game-zh-only',
          title: '游戏实况中文解说',
          description: '',
          sourceLabel: 'bilibili',
          coverImage: '',
          level: 'A2',
          category: '游戏',
          progressPercent: 0,
          totalWords: 0,
          completedEpisodes: 0,
          totalEpisodes: 1,
          lastStudiedStr: '',
          rating: 0,
          episodes: <LibraryEpisodeItem>[
            ep(id: 'game-zh-only-01', title: '纯中文游戏实况'),
          ],
        ),
        LibraryCourseData(
          id: 'game-en',
          title: 'Minecraft English',
          description: '',
          sourceLabel: 'bilibili',
          coverImage: '',
          level: 'A2',
          category: '游戏',
          progressPercent: 0,
          totalWords: 0,
          completedEpisodes: 0,
          totalEpisodes: 1,
          lastStudiedStr: '',
          rating: 0,
          episodes: <LibraryEpisodeItem>[
            ep(
              id: 'game-en-01',
              title: 'Learn English with Minecraft',
              enPath: enSrt.path,
            ),
          ],
        ),
      ],
      readingDocs: const <ReadingDoc>[],
      activeBook: null,
    );
    expect(rec.focus.id, 'video');
    expect(rec.route, '/episodes/game-en-01');
    expect(rec.title, contains('Minecraft'));
  });

  test(
    'oral opens the travel lesson and vocabulary opens the unified word book',
    () {
      FocusRecommendation recommend(String focus) => buildFocusRecommendation(
        profile: OnboardingProfile(
          focusId: focus,
          interestIds: const <String>['travel'],
        ),
        prefs: const AcquirePreferencesDto(),
        courses: const <LibraryCourseData>[],
        readingDocs: const <ReadingDoc>[],
        activeBook: null,
      );
      expect(recommend('oral').route, '/learn/dialogue?lesson=1');
      expect(recommend('vocab').route, '/words');
      expect(recommend('video').title, '选择一段视频');
    },
  );

  test('prefs tags encode focus without gating community', () {
    final List<String> tags = prefsTagsForProfile(
      interestIds: <String>['tech'],
      ageBandId: 'college',
      focusId: 'oral',
      keepTags: <String>['slow', 'mode_video'],
    );
    expect(tags.contains('mode_oral'), isTrue);
    expect(tags.contains('mode_video'), isFalse);
    expect(tags.contains('tech'), isTrue);
    expect(focusIdFromTags(tags), 'oral');
  });
}
