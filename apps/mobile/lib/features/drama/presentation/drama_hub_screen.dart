import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../daily_review/data/memory_item_store.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../import_course/presentation/netdisk_import_sheet.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../navigation/presentation/navigation_destination.dart';
import '../../player/domain/episode_clip_due.dart';
import '../../player/domain/episode_study_progress.dart';
import '../../player/presentation/episode_study_progress_provider.dart';
import '../../player/presentation/widgets/episode_stage_dots.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/pad_scaffold.dart';
import '../../shared/presentation/pad/pad_top_bar.dart';
import '../domain/drama_course.dart';

export '../domain/drama_course.dart' show looksLikeDramaCourse;

enum _DramaFilter { all, notStarted, firstStudy, srsReview, pendingReview }

/// US-drama shelf: season/episode list + four-stage dots.
///
/// [embedded] = true when shown as a tab inside [LibraryScreen] (no outer scaffold).
class DramaHubScreen extends ConsumerStatefulWidget {
  const DramaHubScreen({
    this.embedded = false,
    this.onSwitchToVideos,
    super.key,
  });

  final bool embedded;
  final VoidCallback? onSwitchToVideos;

  @override
  ConsumerState<DramaHubScreen> createState() => _DramaHubScreenState();
}

class _DramaHubScreenState extends ConsumerState<DramaHubScreen> {
  _DramaFilter _filter = _DramaFilter.all;
  String? _selectedCourseId;
  bool _syncedDue = false;

  @override
  Widget build(BuildContext context) {
    final List<LibraryCourseData> catalog = ref.watch(libraryCatalogProvider);
    final Map<String, EpisodeStudyProgress> progressMap =
        ref.watch(episodeStudyProgressProvider);
    final List<LibraryCourseData> dramas =
        catalog.where(looksLikeDramaCourse).toList();
    if (!_syncedDue && dramas.isNotEmpty) {
      _syncedDue = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDueClipCounts(dramas);
      });
    }

    LibraryCourseData? selected;
    if (dramas.isNotEmpty) {
      selected = dramas.cast<LibraryCourseData?>().firstWhere(
            (LibraryCourseData? c) => c?.id == _selectedCourseId,
            orElse: () => dramas.first,
          );
    }

    int masteredEps = 0;
    int totalEps = 0;
    for (final LibraryCourseData c in dramas) {
      for (final LibraryEpisodeItem e in c.episodes) {
        totalEps++;
        if (episodeProgressOf(progressMap, e.id).stage ==
            EpisodeStudyStage.mastered) {
          masteredEps++;
        }
      }
    }

    final Widget body = ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        widget.embedded ? 8 : 12,
        16,
        32,
      ),
      children: <Widget>[
        if (!widget.embedded) ...<Widget>[
          Text(
            '三步走：看剧情理解 → 逐句精学 → 听写/跟读输出；未达线句子进入统一 FSRS。'
            '默认本机 GPU 补字幕，不静默打云端 Key。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppDesignTokens.textSecondary,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 10),
        ] else ...<Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '网盘季集 + SRT · 看懂 → 精读 → 输出 → FSRS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppDesignTokens.textSecondary,
                        height: 1.35,
                      ),
                ),
              ),
              TextButton.icon(
                onPressed: () => showNetdiskImportSheet(context, ref),
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('网盘导入'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        const EpisodeStageLegend(),
        const SizedBox(height: 8),
        Text(
          '完全掌握 $masteredEps / $totalEps 集'
          '${totalEps == 0 ? '' : ' (${(masteredEps * 100 / totalEps).round()}%)'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 12),
        if (dramas.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  const Text('还没有美剧课。从网盘导入整季文件夹（含 .en.srt / .zh.srt）。'),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => showNetdiskImportSheet(context, ref),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('网盘导入'),
                  ),
                  TextButton(
                    onPressed: widget.onSwitchToVideos ??
                        () => context.go('/library'),
                    child: const Text('或去「视频」Tab 看 B 站等片库'),
                  ),
                ],
              ),
            ),
          )
        else ...<Widget>[
          DropdownButtonFormField<String>(
            value: selected?.id,
            decoration: const InputDecoration(
              labelText: '剧集 / 季',
              border: OutlineInputBorder(),
            ),
            items: <DropdownMenuItem<String>>[
              for (final LibraryCourseData c in dramas)
                DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(
                    libraryCourseDisplayTitle(c),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (String? id) {
              if (id == null) return;
              setState(() => _selectedCourseId = id);
            },
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final _DramaFilter f in _DramaFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_filterLabel(f)),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (selected != null)
            ..._filteredEpisodes(selected, progressMap).map(
              (LibraryEpisodeItem ep) {
                final EpisodeStudyProgress p =
                    episodeProgressOf(progressMap, ep.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(ep.title),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: EpisodeStageDots(stage: p.stage),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      context.pushNamed(
                        'player',
                        pathParameters: <String, String>{
                          'episodeId': ep.id,
                        },
                        queryParameters: const <String, String>{
                          'plan': 'drama',
                        },
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ],
    );

    if (widget.embedded) {
      return body;
    }

    return PadScaffold(
      currentDestination: AppNavDestination.library,
      showContinueLearning: false,
      topBar: PadTopBar(
        title: '美剧精学',
        description: '网盘季集 + SRT · 看懂 → 精读 → 输出 → FSRS',
        trailing: IconButton(
          tooltip: '从网盘导入季集',
          onPressed: () => showNetdiskImportSheet(context, ref),
          icon: const Icon(Icons.cloud_download_outlined),
        ),
      ),
      body: body,
    );
  }

  String _filterLabel(_DramaFilter f) => switch (f) {
        _DramaFilter.all => '全部',
        _DramaFilter.notStarted => '未开始',
        _DramaFilter.firstStudy => '第一次学习',
        _DramaFilter.srsReview => '间隔复习',
        _DramaFilter.pendingReview => '待复习',
      };

  List<LibraryEpisodeItem> _filteredEpisodes(
    LibraryCourseData course,
    Map<String, EpisodeStudyProgress> progressMap,
  ) {
    return course.episodes.where((LibraryEpisodeItem ep) {
      final EpisodeStudyProgress p = episodeProgressOf(progressMap, ep.id);
      return switch (_filter) {
        _DramaFilter.all => true,
        _DramaFilter.notStarted => p.stage == EpisodeStudyStage.notStarted,
        _DramaFilter.firstStudy => p.stage == EpisodeStudyStage.firstStudy,
        _DramaFilter.srsReview => p.stage == EpisodeStudyStage.srsReview,
        _DramaFilter.pendingReview => p.dueClipCount > 0,
      };
    }).toList();
  }

  Future<void> _syncDueClipCounts(List<LibraryCourseData> dramas) async {
    final EpisodeStudyProgressNotifier notifier =
        ref.read(episodeStudyProgressProvider.notifier);
    final memory = ref.read(memoryItemStoreProvider);
    final records = ref.read(dailyReviewProvider).records;
    final DateTime now = DateTime.now();
    for (final LibraryCourseData course in dramas) {
      for (final LibraryEpisodeItem ep in course.episodes) {
        final int due = countDueClips(
          memoryItems: memory,
          records: records,
          now: now,
          episodeId: ep.id,
        );
        final EpisodeStudyProgress cur = notifier.of(ep.id);
        if (cur.dueClipCount != due) {
          await notifier.setDueClipCount(ep.id, due, requireOutput: true);
        }
      }
    }
  }
}
