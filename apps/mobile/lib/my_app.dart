import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';

import 'config/theme/theme_logic.dart';
import 'config/theme/theme_ui_model.dart';
import 'features/authentication/presentation/auth_session.dart';
import 'features/authentication/presentation/ensure_default_account.dart';
import 'features/idle_jobs/idle_job_drain.dart';
import 'features/idle_jobs/idle_job_queue.dart';
import 'features/idle_jobs/idle_job_scheduler.dart';
import 'features/import_course/data/bilibili_multipage.dart';
import 'features/import_course/presentation/video_download_progress_host.dart';
import 'features/import_course/presentation/video_download_progress_host.dart';
import 'features/library/presentation/library_catalog_provider.dart';
import 'features/library/presentation/library_mock_data.dart';
import 'features/settings/presentation/bilibili_login_sheet.dart';
import 'features/settings/presentation/settings_provider.dart';
import 'features/shared/presentation/app_orientation.dart';
import 'features/shared/presentation/pad/app_design_tokens.dart';
import 'features/subtitle_completion/overlay_permission_host.dart';
import 'features/subtitle_completion/shared_bilibili_subtitle_sync.dart';
import 'features/subtitle_completion/subtitle_completion_runtime.dart';
import 'features/subtitle_completion/subtitle_completion_scheduler.dart';
import 'features/subtitle_completion/subtitle_completion_status_hub.dart';
import 'features/subtitle_completion/subtitle_completion_status_provider.dart';
import 'features/sync/data/acquire_api_client.dart';
import 'features/sync/data/personal_import_sync.dart';
import 'features/sync/presentation/cloud_catalog_sync.dart';
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
      // Default to weiwei so personal watch-url + subtitle assets sync.
      unawaited(() async {
        final bool signedIn = await ensureDefaultAccountSignIn(ref);
        if (!signedIn && ref.read(authSessionProvider).isLoggedIn) {
          unawaited(syncCloudCatalogAndFeed(ref));
        }
      }());
      // Touch status provider so library course UI can show fill progress.
      ref.read(subtitleCompletionStatusProvider);
      configureSharedBilibiliSubtitleApi(
        ref.read(acquireApiClientProvider),
      );
      // Shared-cache hit (no Whisper job): adopt local EN/ZH paths into catalog.
      SubtitleCompletionStatusHub.instance.bindSharedApplied(({
        required String episodeId,
        String? enPath,
        String? zhPath,
      }) {
        unawaited(() async {
          final List<LibraryCourseData> courses = ref.read(
            libraryCatalogProvider,
          );
          for (final LibraryCourseData course in courses) {
            for (final LibraryEpisodeItem episode in course.episodes) {
              if (episode.id != episodeId) {
                continue;
              }
              await ref.read(libraryCatalogProvider.notifier).updateEpisodeLocalMedia(
                    courseId: course.id,
                    episodeId: episodeId,
                    enSubtitlePath: enPath,
                    zhSubtitlePath: zhPath,
                  );
              unawaited(
                ref.read(subtitleCompletionStatusProvider.notifier).refresh(),
              );
              return;
            }
          }
        }());
      });
      unawaited(SubtitleCompletionRuntime.instance.init());
      SubtitleCompletionScheduler.instance.attach(
        settingsReader: () => ref.read(learningSettingsProvider),
        catalogReader: () => ref.read(libraryCatalogProvider),
        catalogNotifier: () => ref.read(libraryCatalogProvider.notifier),
        onProgress: (String episodeId, String label) {
          ref
              .read(subtitleCompletionStatusProvider.notifier)
              .reportProgress(episodeId, label);
        },
        onQueueChanged: () {
          unawaited(
            ref.read(subtitleCompletionStatusProvider.notifier).refresh(),
          );
        },
        onPersisted:
            ({
              required String episodeId,
              required String englishPath,
              required String chinesePath,
            }) async {
              await ref
                  .read(libraryCatalogProvider.notifier)
                  .relinkEpisodeSubtitleFiles(episodeId: episodeId);
              // Also write the exact paths the worker just persisted (covers
              // the race where files land a tick before existsSync).
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
                  unawaited(
                    ref
                        .read(subtitleCompletionStatusProvider.notifier)
                        .refresh(),
                  );
                  final AuthSessionState auth = ref.read(authSessionProvider);
                  final String? sourceKey = bilibiliEpisodeCacheKey(
                    course: course,
                    episode: episode,
                    sourceUrl: episode.sourceUrl,
                    videoAsset: episode.videoAsset,
                  );
                  final AcquireApiClient api =
                      ref.read(acquireApiClientProvider);
                  // Audit → shared (if quality OK) + always upsert personal.
                  unawaited(
                    syncEpisodeSubtitlesToCloud(
                      api: api,
                      isLoggedIn: auth.isLoggedIn,
                      sourceKey: sourceKey,
                      sourceUrl: episode.sourceUrl,
                      englishPath: englishPath,
                      chinesePath: chinesePath,
                      course: course,
                      episode: episode,
                      durationSec: episode.durationMinutes * 60,
                      sourceOrigin: 'asr',
                    ),
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
    SubtitleCompletionStatusHub.instance.bindSharedApplied(null);
    SubtitleCompletionScheduler.instance.detach();
    unawaited(SubtitleCompletionRuntime.instance.dispose());
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
      unawaited(_drainIdleOnResume());
    }
  }

  Future<void> _drainIdleOnResume() async {
    if (!idleJobsEnabled()) return;
    bool wake = false;
    try {
      wake = await consumeIdleWakeFlag();
      if (Hive.isBoxOpen('prefs')) {
        final Box<String> box = Hive.box<String>('prefs');
        if (box.get('subtitle_completion_auto_run_v1') == '1') {
          wake = true;
          await box.put('subtitle_completion_auto_run_v1', '0');
        }
      }
    } catch (_) {}
    if (wake || IdleJobQueue.shared.pending.isNotEmpty) {
      await drainIdleJobs(ref);
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
    return WithForegroundTask(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
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
                  child: OverlayPermissionHost(
                    child: VideoDownloadProgressHost(
                      child: child ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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

  final TextTheme textTheme = ThemeData(brightness: brightness).textTheme.apply(
    fontFamily: 'Nunito',
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    fontFamily: 'Nunito',
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
