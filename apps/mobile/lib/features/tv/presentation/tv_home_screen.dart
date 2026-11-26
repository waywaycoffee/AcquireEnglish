import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../player/presentation/learning_resume_provider.dart';
import '../../shared/presentation/app_orientation.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import 'tv_focus_button.dart';

/// 10-foot / TV launcher: continue learning + course grid, D-pad friendly.
class TvHomeScreen extends ConsumerStatefulWidget {
  const TvHomeScreen({super.key});

  static const String route = '/tv';

  @override
  ConsumerState<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends ConsumerState<TvHomeScreen> {
  @override
  void initState() {
    super.initState();
    unawaitedOrientation();
  }

  Future<void> unawaitedOrientation() async {
    await unlockFullscreenLandscapeOrientation();
  }

  @override
  void dispose() {
    // Portrait restore happens when leaving TV routes via router redirect /
    // next screen; still try here for safety.
    ensureDefaultPortraitOrientation();
    super.dispose();
  }

  void _openEpisode(String episodeId) {
    context.go('/episodes/$episodeId?tv=1');
  }

  @override
  Widget build(BuildContext context) {
    final ContinueLearningTarget? resume = ref.watch(
      continueLearningTargetProvider,
    );
    final List<LibraryCourseData> courses = ref.watch(libraryCatalogProvider);
    final List<LibraryCourseData> withEpisodes = courses
        .where((LibraryCourseData c) => c.episodes.isNotEmpty)
        .take(12)
        .toList(growable: false);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _TvBackIntent(),
        const SingleActivator(LogicalKeyboardKey.goBack): const _TvBackIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _TvBackIntent: CallbackAction<_TvBackIntent>(
            onInvoke: (_TvBackIntent intent) {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF101923),
          body: SafeArea(
            child: FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(36, 24, 36, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        TvFocusButton(
                          label: '返回手机版',
                          icon: Icons.arrow_back_rounded,
                          onPressed: () {
                            ensureDefaultPortraitOrientation();
                            context.go('/home');
                          },
                        ),
                        const SizedBox(width: 20),
                        const Expanded(
                          child: Text(
                            '电视横屏学习',
                            style: TextStyle(
                              color: Color(0xFFECF0F0),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          '方向键移动 · 确认键进入',
                          style: TextStyle(
                            color: AppDesignTokens.textSecondary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    if (resume != null)
                      TvFocusCard(
                        autofocus: true,
                        onPressed: () => _openEpisode(resume.episode.id),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: const Color(0xFF15202B),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 120,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E323B),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: Color(0xFFA8F1C8),
                                  size: 40,
                                ),
                              ),
                              const SizedBox(width: 22),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Text(
                                      '继续学习',
                                      style: TextStyle(
                                        color: Color(0xFFA8F1C8),
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${resume.course.title}  ·  第 ${resume.episode.numberStr} 集',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFFECF0F0),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      resume.episode.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AppDesignTokens.textSecondary,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TvFocusButton(
                                label: '开始精听',
                                primary: true,
                                icon: Icons.play_arrow_rounded,
                                onPressed: () =>
                                    _openEpisode(resume.episode.id),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 28),
                    Text(
                      '课程库',
                      style: TextStyle(
                        color: AppDesignTokens.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: withEpisodes.isEmpty
                          ? Center(
                              child: Text(
                                '暂无课程。请先在手机版导入或同步片库。',
                                style: TextStyle(
                                  color: AppDesignTokens.textSecondary,
                                  fontSize: 18,
                                ),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 18,
                                    crossAxisSpacing: 18,
                                    childAspectRatio: 1.55,
                                  ),
                              itemCount: withEpisodes.length,
                              itemBuilder: (BuildContext context, int index) {
                                final LibraryCourseData course =
                                    withEpisodes[index];
                                final LibraryEpisodeItem episode =
                                    course.episodes.first;
                                return TvFocusCard(
                                  autofocus: resume == null && index == 0,
                                  onPressed: () => _openEpisode(episode.id),
                                  child: Container(
                                    padding: const EdgeInsets.all(18),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF15202B),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          course.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Color(0xFFECF0F0),
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          '${course.episodes.length} 集',
                                          style: TextStyle(
                                            color:
                                                AppDesignTokens.textSecondary,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvBackIntent extends Intent {
  const _TvBackIntent();
}
