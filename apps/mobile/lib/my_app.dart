import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config/theme/theme_logic.dart';
import 'config/theme/theme_ui_model.dart';
import 'features/authentication/presentation/auth_session.dart';
import 'features/settings/presentation/bilibili_login_sheet.dart';
import 'features/shared/presentation/app_orientation.dart';
import 'features/shared/presentation/pad/app_design_tokens.dart';
import 'features/library/presentation/library_catalog_provider.dart';
import 'features/library/presentation/library_mock_data.dart';
import 'features/settings/presentation/settings_provider.dart';
import 'features/subtitle_completion/subtitle_completion_scheduler.dart';
import 'features/sync/presentation/daily_feed_lifecycle.dart';
import 'flavors/app_flavor.dart';
import 'router/app_router.dart';

export 'features/shared/presentation/app_orientation.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Re-assert portrait after first frame — Xiaomi can ignore early boot calls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ensureDefaultPortraitOrientation();
      SubtitleCompletionScheduler.instance.attach(
        settingsReader: () => ref.read(learningSettingsProvider),
        catalogReader: () => ref.read(libraryCatalogProvider),
        onPersisted:
            ({
              required String episodeId,
              required String englishPath,
              required String chinesePath,
            }) async {
              final List<LibraryCourseData> courses = ref.read(
                libraryCatalogProvider,
              );
              for (final LibraryCourseData course in courses) {
                for (final LibraryEpisodeItem episode in course.episodes) {
                  if (episode.id != episodeId) {
                    continue;
                  }
                  await ref
                      .read(libraryCatalogProvider.notifier)
                      .updateEpisodeLocalMedia(
                        courseId: course.id,
                        episodeId: episodeId,
                        enSubtitlePath: englishPath,
                        zhSubtitlePath: chinesePath,
                      );
                  return;
                }
              }
            },
      );
    });
  }

  @override
  void dispose() {
    SubtitleCompletionScheduler.instance.detach();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Keep non-fullscreen routes portrait after returning from background.
      ensureDefaultPortraitOrientation();
      // Re-scan + drain unfinished ASR subtitle jobs while the app is open.
      SubtitleCompletionScheduler.instance.kick(delay: Duration.zero);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Restore JWT into Dio as early as possible.
    ref.watch(authSessionProvider);
    final ThemeUiModel currentTheme = ref.watch(themeLogicProvider);
    final GoRouter router = ref.watch(goRouterProvider);
    final bool isDark =
        currentTheme.themeMode == ThemeMode.dark ||
        (currentTheme.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    AppDesignTokens.brightness = isDark ? Brightness.dark : Brightness.light;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: isDark
            ? const Color(0xFF12141A)
            : const Color(0xFFF3F4F7),
        systemNavigationBarIconBrightness: isDark
            ? Brightness.light
            : Brightness.dark,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarContrastEnforced: false,
      ),
      child: MaterialApp.router(
        routerConfig: router,

        /// Localization is not available for the title.
        title: FlavorConfig.appName,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),

        themeMode: currentTheme.themeMode,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        builder: (BuildContext context, Widget? child) {
          final MediaQueryData mediaQuery = MediaQuery.of(context);
          return DailyFeedLifecycleHost(
            child: MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(
                  _textScaleForWidth(mediaQuery.size.width),
                ),
              ),
              child: BilibiliLoginGate(
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }
}

double _textScaleForWidth(double width) {
  if (width <= 430) {
    return 0.82;
  }
  if (width <= 768) {
    return 0.86;
  }
  if (width <= 1280) {
    return 0.91;
  }
  return 0.95;
}

ThemeData _buildTheme(Brightness brightness) {
  final bool isDark = brightness == Brightness.dark;
  final ColorScheme colorScheme = ColorScheme.fromSeed(
    brightness: brightness,
    seedColor: const Color(0xFF0875D8),
    primary: const Color(0xFF0875D8),
    surface: isDark ? const Color(0xFF17181D) : Colors.white,
  ).copyWith(
    primary: const Color(0xFF0875D8),
    onPrimary: Colors.white,
    secondary: const Color(0xFFD9D8DE),
    onSecondary: const Color(0xFF222226),
    surface: isDark ? const Color(0xFF17181D) : Colors.white,
    onSurface: isDark ? Colors.white : const Color(0xFF050505),
  );

  final TextTheme textTheme = GoogleFonts.nunitoTextTheme().apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    textTheme: textTheme,
    visualDensity: const VisualDensity(horizontal: -0.5, vertical: -0.5),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF101115)
        : const Color(0xFFEFEFF2),
    cardColor: colorScheme.surface,
    dividerColor: isDark ? const Color(0xFF2C2D33) : const Color(0xFFD8D8DD),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF0875D8),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      margin: EdgeInsets.zero,
    ),
  );
}

Future<void> setPreferredOrientations() {
  return lockPortraitOrientation();
}
