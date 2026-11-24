import '../features/learning_modules/module_screen.dart';
import '../features/community/presentation/public_learning_card_screen.dart';
import '../features/community/presentation/community_screen.dart';
import '../features/community/presentation/study_pk_screen.dart';
import '../features/exam/presentation/exam_cloze_import_screen.dart';
import '../features/exam/presentation/exam_cloze_session.dart';
import '../features/exam/presentation/exam_errorbook_screen.dart';
import '../features/exam/presentation/exam_grammar_hub_screen.dart';
import '../features/exam/domain/exam_registry.dart';
import '../features/exam/presentation/exam_home_screen.dart';
import '../features/exam/presentation/exam_listening_screen.dart';
import '../features/exam/presentation/exam_mock_screen.dart';
import '../features/exam/presentation/exam_practice_screen.dart';
import '../features/exam/domain/exam_reading_strategy.dart';
import '../features/exam/presentation/exam_reading_guided_session.dart';
import '../features/exam/presentation/exam_reading_import_screen.dart';
import '../features/exam/presentation/exam_reading_mock_session.dart';
import '../features/exam/presentation/exam_reading_paper_detail_screen.dart';
import '../features/exam/presentation/exam_reading_screen.dart';
import '../features/exam/presentation/exam_reading_skill_course_screen.dart';
import '../features/exam/presentation/exam_reading_type_drill_screen.dart';
import '../features/exam/presentation/exam_report_screen.dart';
import '../features/exam/presentation/exam_select_screen.dart';
import '../features/exam/presentation/exam_session_screen.dart';
import '../features/ear_grind/presentation/ear_grind_hub_screen.dart';
import '../features/ear_grind/presentation/ear_grind_player_screen.dart';
import '../features/writing/domain/writing_tracks.dart';
import '../features/writing/presentation/writing_editor_screen.dart';
import '../features/writing/presentation/writing_home_screen.dart';
import '../features/writing/presentation/writing_track_screen.dart';
import '../features/daily_path/presentation/course_unit_session_screen.dart';
import '../features/daily_path/presentation/oral_core_course_screen.dart';
import '../features/daily_review/domain/daily_review.dart';
import '../features/learning_modules/american_ipa_course_screen.dart';
import '../features/learning_modules/british_ipa_course_screen.dart';
import '../features/learning_modules/phonics_nessy_course_screen.dart';
// ignore_for_file: prefer_function_declarations_over_variables

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/authentication/presentation/auth_session.dart';
import '../features/authentication/presentation/legal/user_agreement_screen.dart';
import '../features/authentication/presentation/login/login_screen.dart';
import '../features/authentication/presentation/login/phone_login_screen.dart';
import '../features/authentication/presentation/login/wechat_mock_login_screen.dart';
import '../features/authentication/presentation/register/register_screen.dart';
import '../features/daily_review/presentation/daily_review_screen.dart';
import '../features/growth/presentation/growth_screen.dart';
import '../features/guide/presentation/guide_screen.dart';
import '../features/home/presentation/learning_home_screen.dart';
import '../features/import_course/presentation/import_course_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/phrases/presentation/phrases_screen.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/course_decompose/presentation/material_course_edit_screen.dart';
import '../features/course_decompose/presentation/my_material_courses_screen.dart';
import '../features/reading/presentation/reading_catalog_screen.dart';
import '../features/reading/presentation/reading_hub_screen.dart';
import '../features/reading/presentation/reading_library_provider.dart';
import '../features/reading/presentation/reading_reader_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/learning/presentation/learning_review_screen.dart';
import '../features/words/presentation/sm2_daily_session_screen.dart';
import '../features/words/presentation/lilinji_catalog_screen.dart';
import '../features/words/domain/syllabus_book.dart';
import '../features/digital_human/presentation/digital_human_coach_screen.dart';
import '../features/digital_human/presentation/peer_oral_practice_screen.dart';
import '../features/words/presentation/server_syllabus_catalog_screen.dart';
import '../features/words/presentation/syllabus_books_screen.dart';
import '../features/words/presentation/favorite_word_book_screen.dart';
import '../features/words/presentation/words_screen.dart';
import '../features/words/presentation/vocabulary_placement_screen.dart';
import 'fade_extension.dart';
import '../features/membership/presentation/membership_screen.dart';
import '../features/membership/presentation/module_gate.dart';
import '../features/membership/domain/module_access.dart';
import '../features/onboarding/presentation/auth_guide_keys.dart';
import '../features/onboarding/presentation/auth_source_guide_screen.dart';
import '../features/onboarding/presentation/auth_sources_settings_screen.dart';
import '../features/onboarding/presentation/first_open_onboarding_screen.dart';
import '../features/onboarding/presentation/onboarding_provider.dart';
import '../features/navigation/presentation/battle_hub_screen.dart';
import '../features/navigation/presentation/navigation_destination.dart';
import '../features/shared/presentation/pad/pad_scaffold.dart';
import '../features/shared/presentation/pad/pad_top_bar.dart';

part 'app_router.g.dart';

enum SGRoute {
  home,
  library,
  growth,
  review,
  discover,
  reviewSession,
  sm2Review,
  vocabularyPlacement,
  phrases,
  words,
  phraseReview,
  learningReview,
  guide,
  settings,
  membership,
  importCourse,
  login,
  loginPhone,
  loginWechat,
  player,
  register,
  userAgreement,
  forgotPassword,
  editProfile,
  changePassword;

  String get route {
    switch (this) {
      case SGRoute.reviewSession:
        return '/review/session';
      case SGRoute.sm2Review:
        return '/review/sm2';
      case SGRoute.learningReview:
        return '/review/learning';
      case SGRoute.loginPhone:
        return '/login/phone';
      case SGRoute.loginWechat:
        return '/login/wechat';
      default:
        return '/${toString().replaceAll('SGRoute.', '')}';
    }
  }

  String get name => toString().replaceAll('SGRoute.', '');
}

bool _isAuthOrLegalPath(String location) {
  return location == SGRoute.login.route ||
      location == SGRoute.loginPhone.route ||
      location == SGRoute.loginWechat.route ||
      location == SGRoute.register.route ||
      location == SGRoute.userAgreement.route;
}

@riverpod
GoRouter goRouter(Ref ref) {
  final bool signedIn = ref.watch(authSessionProvider).isLoggedIn;
  return GoRouter(
  // Cold start: one random cinematic page, once per process.
  initialLocation: !readSessionSplashDone()
      ? '/onboarding/auth-guide'
      : (!signedIn
          ? SGRoute.login.route
          : (!readOnboardingCompletedSync()
              ? '/onboarding'
              : SGRoute.home.route)),
  redirect: (BuildContext context, GoRouterState state) {
    final bool done = readOnboardingCompletedSync();
    final bool splashDone = readSessionSplashDone();
    final String loc = state.matchedLocation;
    final bool onOnboarding = loc == '/onboarding';
    final bool onAuthGuide = loc == '/onboarding/auth-guide';
    if (!splashDone && !onAuthGuide && !_isAuthOrLegalPath(loc)) {
      return '/onboarding/auth-guide';
    }
    if (!signedIn && !onAuthGuide && !_isAuthOrLegalPath(loc)) {
      return SGRoute.login.route;
    }
    if (signedIn &&
        splashDone &&
        !done &&
        !onOnboarding &&
        !onAuthGuide &&
        !_isAuthOrLegalPath(loc)) {
      return '/onboarding';
    }
    return null;
  },
  routes: <GoRoute>[
    GoRoute(
      path: '/onboarding',
      builder: (BuildContext context, GoRouterState state) =>
          const FirstOpenOnboardingScreen(),
    ).fade(),
    GoRoute(
      path: '/onboarding/auth-guide',
      builder: (BuildContext context, GoRouterState state) =>
          const AuthSourceGuideScreen(),
    ).fade(),
    GoRoute(
      path: AuthSourcesSettingsScreen.route,
      builder: (BuildContext context, GoRouterState state) =>
          const AuthSourcesSettingsScreen(),
    ).fade(),
    GoRoute(
      path: '/ear-grind',
      builder: (BuildContext context, GoRouterState state) =>
          const EarGrindHubScreen(),
    ),
    GoRoute(
      path: '/ear-grind/play',
      builder: (BuildContext context, GoRouterState state) =>
          const EarGrindPlayerScreen(),
    ),
    GoRoute(
      path: '/learn/:kind',
      builder: (context, state) {
        final String kind = moduleLessons.containsKey(state.pathParameters['kind'])
            ? state.pathParameters['kind']!
            : 'phonics';
        final Widget screen = ModuleScreen(
          key: ValueKey<String>(state.uri.toString()),
          initialLesson: int.tryParse(state.uri.queryParameters['lesson'] ?? ''),
          kind: kind,
        );
        if (kind == 'listening' || kind == 'dialogue') {
          // Browse + first N lessons free; further lessons gated in ModuleScreen.
          return ModuleGate(
            moduleCode: 'video',
            title: '视频模块',
            softBrowse: true,
            child: screen,
          );
        }
        return screen;
      },
    ),
    GoRoute(
      path: '/shared/:token',
      builder: (BuildContext context, GoRouterState state) =>
          PublicLearningCardScreen(token: state.pathParameters['token']!),
    ),
    GoRoute(
      path: '/exam',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamHomeScreen(),
    ),
    GoRoute(
      path: '/exam/select',
      builder: (BuildContext context, GoRouterState state) {
        final String? trackRaw = state.uri.queryParameters['track'];
        final String? family = state.uri.queryParameters['family'];
        return ExamSelectScreen(
          initialTrack: examTrackByName(trackRaw),
          initialFamilyId: family,
        );
      },
    ),
    GoRoute(
      path: '/exam/practice',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamPracticeScreen(),
    ),
    GoRoute(
      path: '/exam/mock',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamMockScreen(),
    ),
    GoRoute(
      path: '/exam/errorbook',
      builder: (BuildContext context, GoRouterState state) =>
          ExamErrorBookScreen(
            initialSkill: state.uri.queryParameters['skill'],
          ),
    ),
    GoRoute(
      path: '/exam/listening',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamListeningScreen(),
    ),
    GoRoute(
      path: '/exam/grammar',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamGrammarHubScreen(),
    ),
    GoRoute(
      path: '/exam/cloze',
      builder: (BuildContext context, GoRouterState state) {
        final bool tips = state.uri.queryParameters['tips'] == '1';
        final String? passageId = state.uri.queryParameters['passageId'];
        return ModuleGate(
          moduleCode: 'exam',
          title: '考试模块',
          softBrowse: true,
          child: ExamClozeSession(tipsMode: tips, passageId: passageId),
        );
      },
    ),
    GoRoute(
      path: '/exam/cloze/import',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamClozeImportScreen(),
    ),
    GoRoute(
      path: '/exam/report',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamReportScreen(),
    ),
    GoRoute(
      path: '/exam/reading',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamReadingScreen(),
    ),
    GoRoute(
      path: '/exam/reading/skill',
      builder: (BuildContext context, GoRouterState state) =>
          const ExamReadingSkillCourseScreen(),
    ),
    GoRoute(
      path: '/exam/reading/import',
      builder: (BuildContext context, GoRouterState state) {
        final String? editId = state.uri.queryParameters['editId'];
        return ExamReadingImportScreen(editId: editId);
      },
    ),
    GoRoute(
      path: '/exam/reading/paper',
      builder: (BuildContext context, GoRouterState state) {
        final String paperId = state.uri.queryParameters['paperId'] ?? '';
        return ExamReadingPaperDetailScreen(paperId: paperId);
      },
    ),
    GoRoute(
      path: '/exam/reading/guided',
      builder: (BuildContext context, GoRouterState state) {
        final String paperId = state.uri.queryParameters['paperId'] ?? '';
        return ModuleGate(
          moduleCode: 'exam',
          title: '考试模块',
          softBrowse: true,
          child: ExamReadingGuidedSession(paperId: paperId),
        );
      },
    ),
    GoRoute(
      path: '/exam/reading/mock',
      builder: (BuildContext context, GoRouterState state) {
        final String paperId = state.uri.queryParameters['paperId'] ?? '';
        return ModuleGate(
          moduleCode: 'exam',
          title: '考试模块',
          softBrowse: true,
          child: ExamReadingMockSession(paperId: paperId),
        );
      },
    ),
    GoRoute(
      path: '/exam/reading/type',
      builder: (BuildContext context, GoRouterState state) {
        final ExamRcQuestionType type = ExamRcQuestionTypeX.fromStorage(
          state.uri.queryParameters['type'],
        );
        return ExamReadingTypeDrillScreen(type: type);
      },
    ),
    GoRoute(
      path: '/exam/session',
      builder: (BuildContext context, GoRouterState state) {
        final String skill = state.uri.queryParameters['skill'] ?? 'vocab';
        final bool mock =
            state.uri.queryParameters['mock'] == '1' || skill == 'mock';
        final String? tag = state.uri.queryParameters['tag'];
        final int timed =
            int.tryParse(state.uri.queryParameters['timed'] ?? '') ?? 0;
        final bool hideScript =
            state.uri.queryParameters['hideScript'] != '0';
        final Widget session = ExamSessionScreen(
          skill: mock ? 'mock' : skill,
          mock: mock,
          grammarTag: tag,
          listeningHideScript: hideScript,
          timedListeningSeconds: timed,
        );
        if (!mock &&
            (skill == 'reading' ||
                skill == 'listening' ||
                skill == 'grammar' ||
                skill == 'cloze')) {
          // First N passages free; session truncates when not entitled.
          return ModuleGate(
            moduleCode: 'exam',
            title: '考试模块',
            softBrowse: true,
            child: session,
          );
        }
        return session;
      },
    ),
    GoRoute(
      path: '/writing',
      builder: (BuildContext context, GoRouterState state) {
        final String? prompt = state.uri.queryParameters['prompt'];
        final String? rubric = state.uri.queryParameters['rubric'];
        final String? title = state.uri.queryParameters['title'];
        final String? track = state.uri.queryParameters['track'];
        if (prompt != null && prompt.isNotEmpty) {
          final String id = 'w_${DateTime.now().millisecondsSinceEpoch}';
          return WritingEditorScreen(
            essayId: id,
            initialPrompt: prompt,
            initialRubric: rubric ?? 'generic',
            initialTitle: title ?? '考试写作',
            initialTrack: track,
          );
        }
        return const WritingHomeScreen();
      },
    ),
    GoRoute(
      path: '/writing/track/:trackId',
      builder: (BuildContext context, GoRouterState state) {
        final WritingTrackId id =
            writingTrackFromRaw(state.pathParameters['trackId']) ??
                WritingTrackId.gaokao;
        return WritingTrackScreen(trackId: id);
      },
    ),
    GoRoute(
      path: '/writing/:essayId',
      builder: (BuildContext context, GoRouterState state) => WritingEditorScreen(
        essayId: state.pathParameters['essayId']!,
        initialPrompt: state.uri.queryParameters['prompt'],
        initialRubric: state.uri.queryParameters['rubric'],
        initialTitle: state.uri.queryParameters['title'],
        initialTrack: state.uri.queryParameters['track'],
      ),
    ),
    // Legacy cafe adventure URLs → exam hub (cafe removed).
    GoRoute(
      path: '/explore',
      redirect: (BuildContext context, GoRouterState state) => '/exam',
    ),
    GoRoute(
      path: '/explore/cafe/:stage',
      redirect: (BuildContext context, GoRouterState state) => '/exam',
    ),
    GoRoute(
      path: SGRoute.membership.route,
      builder: (context, state) => const MembershipScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.login.route,
      builder: (BuildContext context, GoRouterState state) {
        return const LoginScreen();
      },
    ).fade(),
    GoRoute(
      path: SGRoute.loginPhone.route,
      builder: (BuildContext context, GoRouterState state) {
        return const PhoneLoginScreen();
      },
    ).fade(),
    GoRoute(
      path: SGRoute.loginWechat.route,
      builder: (BuildContext context, GoRouterState state) {
        return const WechatMockLoginScreen();
      },
    ).fade(),
    GoRoute(
      path: SGRoute.register.route,
      builder: (BuildContext context, GoRouterState state) {
        return const RegisterScreen();
      },
    ).fade(),
    GoRoute(
      path: SGRoute.userAgreement.route,
      builder: (BuildContext context, GoRouterState state) {
        return const UserAgreementScreen();
      },
    ).fade(),
    GoRoute(
      path: SGRoute.home.route,
      builder: (BuildContext context, GoRouterState state) =>
          LearningHomeScreen(
            focusVocab: state.uri.queryParameters['focus'] == 'vocab',
          ),
    ).fade(),
    GoRoute(
      path: SGRoute.library.route,
      name: SGRoute.library.name,
      builder: (BuildContext context, GoRouterState state) {
        final String initialView = state.uri.queryParameters['view'] ?? 'list';
        final String tab = (state.uri.queryParameters['tab'] ?? '').trim();
        return LibraryScreen(
          initialView: _parseLibraryView(initialView),
          initialShelfTab: switch (tab) {
            'drama' => LibraryShelfTab.drama,
            'english' || 'browse' || 'english-browse' =>
              LibraryShelfTab.englishBrowse,
            'youtube' || 'yt' => LibraryShelfTab.youtube,
            'dub' || 'dubbing' || 'shadowing' => LibraryShelfTab.dubbing,
            _ => LibraryShelfTab.bilibili,
          },
          initialCourseId: state.uri.queryParameters['courseId'],
          initialEpisodeId: state.uri.queryParameters['episodeId'],
        );
      },
    ).fade(),
    GoRoute(
      path: '/drama',
      name: 'drama',
      redirect: (BuildContext context, GoRouterState state) =>
          '/library?tab=drama',
      builder: (BuildContext context, GoRouterState state) =>
          const SizedBox.shrink(),
    ),
    GoRoute(
      path: SGRoute.growth.route,
      builder: (BuildContext context, GoRouterState state) =>
          const GrowthScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.discover.route,
      name: SGRoute.discover.name,
      builder: (BuildContext context, GoRouterState state) =>
          const CommunityScreen(),
    ).fade(),
    GoRoute(
      path: AppNavDestination.battle.route,
      builder: (BuildContext context, GoRouterState state) =>
          const BattleHubScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.review.route,
      name: SGRoute.review.name,
      redirect: (BuildContext context, GoRouterState state) =>
          '${SGRoute.home.route}?focus=vocab',
    ),
    GoRoute(
      path: SGRoute.vocabularyPlacement.route,
      builder: (BuildContext context, GoRouterState state) =>
          VocabularyPlacementScreen(
            forJourney: state.uri.queryParameters['journey'] == '1',
          ),
    ).fade(),
    GoRoute(
      path: SGRoute.reviewSession.route,
      name: SGRoute.reviewSession.name,
      builder: (BuildContext context, GoRouterState state) {
        final String? kindName = state.uri.queryParameters['kind'];
        final String? deck = state.uri.queryParameters['deck'];
        return DailyReviewScreen(
          session: true,
          practice: state.uri.queryParameters['practice'] == '1',
          learnNewOnly: state.uri.queryParameters['learn'] == '1',
          dueOnly: state.uri.queryParameters['due'] == '1',
          journeyReview: state.uri.queryParameters['journeyReview'] == '1',
          expressions: kindName == 'expressions',
          recommended: deck == 'recommended',
          missedOnly: deck == 'missed',
          syllabusOnly: deck == 'syllabus',
          syllabusBookId: state.uri.queryParameters['book'],
          focusWord: state.uri.queryParameters['focus'],
          weakOnly: state.uri.queryParameters['weak'] == '1',
          sourceLabel: state.uri.queryParameters['source'],
          sourceEpisodeId: state.uri.queryParameters['sourceEpisode'],
          todayTaskId: state.uri.queryParameters['todayTask'],
          practiceKind: ReviewKind.values
              .where((ReviewKind kind) => kind.name == kindName)
              .firstOrNull,
        );
      },
    ).fade(),
    GoRoute(
      path: '/daily-path/unit',
      builder: (BuildContext context, GoRouterState state) {
        final String courseId = state.uri.queryParameters['courseId'] ?? '';
        final String unitId = state.uri.queryParameters['unitId'] ?? '';
        final String mode = state.uri.queryParameters['mode'] ?? 'new';
        return CourseUnitSessionScreen(
          courseId: courseId,
          unitId: unitId,
          mode: mode,
        );
      },
    ).fade(),
    GoRoute(
      path: '/courses/oral-core-9000',
      builder: (BuildContext context, GoRouterState state) =>
          const OralCoreCourseScreen(),
    ).fade(),
    GoRoute(
      path: '/courses/american-ipa',
      builder: (BuildContext context, GoRouterState state) =>
          const AmericanIpaCourseScreen(),
    ).fade(),
    GoRoute(
      path: '/courses/british-ipa',
      builder: (BuildContext context, GoRouterState state) =>
          const BritishIpaCourseScreen(),
    ).fade(),
    GoRoute(
      path: '/courses/phonics',
      builder: (BuildContext context, GoRouterState state) =>
          const PhonicsNessyCourseScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.sm2Review.route,
      name: SGRoute.sm2Review.name,
      builder: (BuildContext context, GoRouterState state) =>
          const Sm2DailySessionScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.learningReview.route,
      name: SGRoute.learningReview.name,
      builder: (BuildContext context, GoRouterState state) =>
          const LearningReviewScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.phrases.route,
      builder: (BuildContext context, GoRouterState state) =>
          const PhrasesScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.words.route,
      builder: (BuildContext context, GoRouterState state) {
        final bool favoritesOnly =
            state.uri.queryParameters['favorites'] == '1' ||
            state.uri.queryParameters['favorites'] == 'true';
        if (favoritesOnly) {
          return const FavoriteWordBookScreen();
        }
        return const WordsScreen();
      },
    ).fade(),
    GoRoute(
      path: '/words/syllabus',
      builder: (BuildContext context, GoRouterState state) {
        final String tab = (state.uri.queryParameters['tab'] ?? '').trim();
        final SyllabusBookKind kind = SyllabusBookKind.fromName(
          tab.isEmpty ? 'word' : tab,
        );
        return SyllabusBooksScreen(initialKind: kind);
      },
    ).fade(),
    GoRoute(
      path: '/words/syllabus/cloud',
      builder: (BuildContext context, GoRouterState state) {
        final String tab = (state.uri.queryParameters['tab'] ?? '').trim();
        final SyllabusBookKind kind = SyllabusBookKind.fromName(
          tab.isEmpty ? 'word' : tab,
        );
        return ServerSyllabusCatalogScreen(
          initialKind: kind,
          topic: tab == 'ipa' || tab == 'phonics' ? tab : '',
        );
      },
    ).fade(),
    GoRoute(
      path: '/words/syllabus/catalog',
      builder: (BuildContext context, GoRouterState state) {
        final String path = (state.uri.queryParameters['path'] ?? '').trim();
        return LilinjiCatalogScreen(initialCategoryPath: path);
      },
    ).fade(),
    GoRoute(
      path: '/reading',
      builder: (BuildContext context, GoRouterState state) =>
          const ReadingHubScreen(),
    ).fade(),
    GoRoute(
      path: '/reading/catalog',
      builder: (BuildContext context, GoRouterState state) =>
          const ReadingCatalogScreen(),
    ).fade(),
    GoRoute(
      path: '/material-courses',
      builder: (BuildContext context, GoRouterState state) => const ModuleGate(
        moduleCode: 'course',
        title: '课程板块',
        softBrowse: true,
        child: MyMaterialCoursesScreen(),
      ),
    ).fade(),
    GoRoute(
      path: '/material-courses/:courseId',
      builder: (BuildContext context, GoRouterState state) {
        final String courseId = Uri.decodeComponent(
          state.pathParameters['courseId'] ?? '',
        );
        // Index-based free preview enforced inside the course screens.
        return ModuleGate(
          moduleCode: 'course',
          title: '课程板块',
          softBrowse: true,
          child: MaterialCourseEditScreen(courseId: courseId),
        );
      },
    ).fade(),
    GoRoute(
      path: '/reading/:docId',
      builder: (BuildContext context, GoRouterState state) {
        final String docId = Uri.decodeComponent(
          state.pathParameters['docId'] ?? '',
        );
        String sourceLabel = '';
        try {
          sourceLabel = ProviderScope.containerOf(context)
                  .read(readingLibraryProvider)
                  .docById(docId)
                  ?.sourceLabel ??
              '';
        } catch (_) {}
        final bool freePreview = isFreeReadingPreviewDocId(docId) ||
            sourceLabel.contains('免费体验') ||
            sourceLabel.contains('入门推荐');
        return ModuleGate(
          moduleCode: 'reading',
          title: '阅读模块',
          freePreviewAllowed: freePreview,
          child: ReadingReaderScreen(docId: docId),
        );
      },
    ).fade(),
    GoRoute(
      path: AppNavDestination.oralCoach.route,
      builder: (BuildContext context, GoRouterState state) {
        final String? scenario = state.uri.queryParameters['scenario']?.trim();
        return PadScaffold(
          currentDestination: AppNavDestination.oralCoach,
          showContinueLearning: false,
          body: DigitalHumanCoachScreen(
            openSceneMenu: state.uri.queryParameters['sceneMenu'] == '1',
            initialScenarioId: (scenario == null || scenario.isEmpty)
                ? null
                : scenario,
          ),
        );
      },
    ).fade(),
    GoRoute(
      path: '/peer-oral',
      builder: (BuildContext context, GoRouterState state) =>
          const PeerOralPracticeScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.phraseReview.route,
      name: SGRoute.phraseReview.name,
      builder: (BuildContext context, GoRouterState state) =>
          const DailyReviewScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.guide.route,
      builder: (BuildContext context, GoRouterState state) =>
          const GuideScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.settings.route,
      builder: (BuildContext context, GoRouterState state) =>
          const SettingsScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.importCourse.route,
      builder: (BuildContext context, GoRouterState state) =>
          const ImportCourseScreen(),
    ).fade(),
    GoRoute(
      path: '/episodes/:episodeId',
      name: SGRoute.player.name,
      builder: (BuildContext context, GoRouterState state) {
        // Default: start playback on open. Opt out with ?autoplay=0.
        final String? autoplayParam = state.uri.queryParameters['autoplay'];
        return PlayerScreen(
          episodeId: state.pathParameters['episodeId']!,
          initialStartTime: state.uri.queryParameters['startTime'],
          courseId: state.uri.queryParameters['courseId'],
          unitId: state.uri.queryParameters['unitId'],
          courseStartMs: int.tryParse(state.uri.queryParameters['courseStartMs'] ?? ''),
          courseEndMs: int.tryParse(state.uri.queryParameters['courseEndMs'] ?? ''),
          autoPlay: autoplayParam != '0',
          autoOpenFullscreen: state.uri.queryParameters['fullscreen'] == '1',
          initialLoopSentence: state.uri.queryParameters['loop'] == 'sentence',
          videoPlanActivity: state.uri.queryParameters['activity'],
          todayTaskId: state.uri.queryParameters['todayTask'],
          dramaPlan: state.uri.queryParameters['plan'] == 'drama',
          onlinePreview: state.uri.queryParameters['preview'] == '1',
        );
      },
    ).fade(),
  ],
  );
}

LibraryScreenView _parseLibraryView(String value) {
  if (value == 'import') {
    return LibraryScreenView.import;
  }
  if (value == 'detail') {
    return LibraryScreenView.detail;
  }
  return LibraryScreenView.list;
}
