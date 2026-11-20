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
import '../features/home/presentation/pad_home_screen.dart';
import '../features/import_course/presentation/import_course_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/phrases/presentation/phrases_screen.dart';
import '../features/player/presentation/player_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/learning/presentation/learning_review_screen.dart';
import '../features/words/presentation/sm2_daily_session_screen.dart';
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
          const PadHomeScreen(),
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
          const DailyReviewScreen(),
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
        return DailyReviewScreen(
          session: true,
          practice: state.uri.queryParameters['practice'] == '1',
          expressions: kindName == 'expressions',
          recommended: state.uri.queryParameters['deck'] == 'recommended',
          missedOnly: state.uri.queryParameters['deck'] == 'missed',
          focusWord: state.uri.queryParameters['focus'],
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
