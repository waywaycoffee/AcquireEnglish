import '../features/community/presentation/public_learning_card_screen.dart';
import '../features/community/presentation/community_screen.dart';
import '../features/daily_review/domain/daily_review.dart';
// ignore_for_file: prefer_function_declarations_over_variables

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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
import '../features/reading/presentation/reading_catalog_screen.dart';
import '../features/reading/presentation/reading_hub_screen.dart';
import '../features/reading/presentation/reading_reader_screen.dart';
import '../features/review_hub/presentation/review_hub_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/learning/presentation/learning_review_screen.dart';
import '../features/words/presentation/sm2_daily_session_screen.dart';
import '../features/words/presentation/lilinji_catalog_screen.dart';
import '../features/words/domain/syllabus_book.dart';
import '../features/digital_human/presentation/digital_human_coach_screen.dart';
import '../features/digital_human/presentation/peer_oral_practice_screen.dart';
import '../features/words/presentation/server_syllabus_catalog_screen.dart';
import '../features/words/presentation/syllabus_books_screen.dart';
import '../features/words/presentation/words_screen.dart';
import '../features/words/presentation/vocabulary_placement_screen.dart';
import 'fade_extension.dart';
import '../features/membership/presentation/membership_screen.dart';

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

@riverpod
GoRouter goRouter(Ref ref) => GoRouter(
  initialLocation: SGRoute.home.route,
  routes: <GoRoute>[
    GoRoute(
      path: '/shared/:token',
      builder: (BuildContext context, GoRouterState state) =>
          PublicLearningCardScreen(token: state.pathParameters['token']!),
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
          const LearningHomeScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.library.route,
      name: SGRoute.library.name,
      builder: (BuildContext context, GoRouterState state) {
        final String initialView = state.uri.queryParameters['view'] ?? 'list';
        return LibraryScreen(
          initialView: _parseLibraryView(initialView),
          initialCourseId: state.uri.queryParameters['courseId'],
          initialEpisodeId: state.uri.queryParameters['episodeId'],
        );
      },
    ).fade(),
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
      path: SGRoute.review.route,
      name: SGRoute.review.name,
      builder: (BuildContext context, GoRouterState state) =>
          const ReviewHubScreen(),
    ).fade(),
    GoRoute(
      path: SGRoute.vocabularyPlacement.route,
      builder: (BuildContext context, GoRouterState state) =>
          const VocabularyPlacementScreen(),
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
          expressions: kindName == 'expressions',
          recommended: deck == 'recommended',
          missedOnly: deck == 'missed',
          syllabusOnly: deck == 'syllabus',
          syllabusBookId: state.uri.queryParameters['book'],
          focusWord: state.uri.queryParameters['focus'],
          weakOnly: state.uri.queryParameters['weak'] == '1',
          sourceLabel: state.uri.queryParameters['source'],
          sourceEpisodeId: state.uri.queryParameters['sourceEpisode'],
          practiceKind: ReviewKind.values
              .where((ReviewKind kind) => kind.name == kindName)
              .firstOrNull,
        );
      },
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
      builder: (BuildContext context, GoRouterState state) =>
          const WordsScreen(),
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
      builder: (BuildContext context, GoRouterState state) =>
          const LilinjiCatalogScreen(),
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
      path: '/reading/:docId',
      builder: (BuildContext context, GoRouterState state) {
        final String docId = Uri.decodeComponent(
          state.pathParameters['docId'] ?? '',
        );
        return ReadingReaderScreen(docId: docId);
      },
    ).fade(),
    GoRoute(
      path: '/digital-human',
      builder: (BuildContext context, GoRouterState state) {
        final String? scenario = state.uri.queryParameters['scenario']?.trim();
        return DigitalHumanCoachScreen(
          initialScenarioId: (scenario == null || scenario.isEmpty)
              ? null
              : scenario,
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
        return PlayerScreen(
          episodeId: state.pathParameters['episodeId']!,
          initialStartTime: state.uri.queryParameters['startTime'],
          autoPlay: state.uri.queryParameters['autoplay'] == '1',
          autoOpenFullscreen: state.uri.queryParameters['fullscreen'] == '1',
        );
      },
    ).fade(),
  ],
);

LibraryScreenView _parseLibraryView(String value) {
  if (value == 'import') {
    return LibraryScreenView.import;
  }
  if (value == 'detail') {
    return LibraryScreenView.detail;
  }
  return LibraryScreenView.list;
}
