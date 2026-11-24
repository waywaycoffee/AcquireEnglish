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
import '../domain/drama_catalog.dart';
import '../domain/drama_course.dart';

export '../domain/drama_course.dart' show looksLikeDramaCourse;

enum _DramaFilter { all, notStarted, firstStudy, srsReview, pendingReview }

/// US-drama shelf: curated titles (metadata) + imported netdisk seasons.
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
            '精选片单先看到剧名；正片在你的网盘。导入含字幕的季集文件夹后即可精学。',
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
                  '精选片单 · 正片走网盘导入（不上 ECS 整季）',
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
        Text(
          '精选片单',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kDramaCatalog.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final DramaCatalogEntry entry = kDramaCatalog[index];
              final LibraryCourseData? owned =
                  importedCourseForCatalogEntry(entry, dramas);
              return _CatalogPosterCard(
                entry: entry,
                owned: owned != null,
                episodeCount: owned?.episodes.length ?? 0,
                onTap: () => _onCatalogTap(entry, owned),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        const EpisodeStageLegend(),
        const SizedBox(height: 8),
        Text(
          '我的已导入  ·  完全掌握 $masteredEps / $totalEps 集'
          '${totalEps == 0 ? '' : ' (${(masteredEps * 100 / totalEps).round()}%)'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
        ),
        const SizedBox(height: 12),
        if (dramas.isEmpty)
          Card(
            color: AppDesignTokens.appWhite,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  Text(
                    '还没有导入季集。打开上方片单，或从网盘导入整季文件夹（含 .en.srt / .zh.srt）。',
                    style: TextStyle(color: AppDesignTokens.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => showNetdiskImportSheet(context, ref),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppDesignTokens.primaryBlueDark,
                      foregroundColor: AppDesignTokens.onAccent,
                    ),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('网盘导入'),
                  ),
                ],
              ),
            ),
          )
        else ...<Widget>[
          DropdownButtonFormField<String>(
            value: selected?.id,
            decoration: InputDecoration(
              labelText: '剧集 / 季',
              border: const OutlineInputBorder(),
              labelStyle: TextStyle(color: AppDesignTokens.textSecondary),
            ),
            dropdownColor: AppDesignTokens.appWhite,
            items: <DropdownMenuItem<String>>[
              for (final LibraryCourseData c in dramas)
                DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(
                    libraryCourseDisplayTitle(c),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppDesignTokens.textPrimary),
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
                  color: AppDesignTokens.appWhite,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(
                      ep.title,
                      style: TextStyle(color: AppDesignTokens.textPrimary),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: EpisodeStageDots(stage: p.stage),
                    ),
                    trailing: Icon(
                      Icons.chevron_right,
                      color: AppDesignTokens.textSecondary,
                    ),
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
        description: '精选片单 · 正片网盘导入',
        trailing: IconButton(
          tooltip: '从网盘导入季集',
          onPressed: () => showNetdiskImportSheet(context, ref),
          icon: const Icon(Icons.cloud_download_outlined),
        ),
      ),
      body: body,
    );
  }

  Future<void> _onCatalogTap(
    DramaCatalogEntry entry,
    LibraryCourseData? owned,
  ) async {
    if (owned != null) {
      setState(() => _selectedCourseId = owned.id);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppDesignTokens.appWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  entry.titleZh,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.titleEn,
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
                const SizedBox(height: 12),
                Text(
                  '${entry.blurb}\n\n'
                  '正片不存放在服务器。请把该剧季集（含英/中字幕）放到百度网盘可见目录后导入，'
                  '导入成功会出现在下方「我的已导入」。',
                  style: TextStyle(
                    color: AppDesignTokens.textPrimary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    showNetdiskImportSheet(context, ref);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppDesignTokens.primaryBlueDark,
                    foregroundColor: AppDesignTokens.onAccent,
                  ),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('去网盘导入'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    '稍后',
                    style: TextStyle(color: AppDesignTokens.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class _CatalogPosterCard extends StatelessWidget {
  const _CatalogPosterCard({
    required this.entry,
    required this.owned,
    required this.episodeCount,
    required this.onTap,
  });

  final DramaCatalogEntry entry;
  final bool owned;
  final int episodeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(entry.accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 118,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accent,
                Color.lerp(accent, Colors.black, 0.45)!,
              ],
            ),
            border: Border.all(color: AppDesignTokens.borderGray),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.titleZh,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.titleEn,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    height: 1.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    owned ? '已导入 · $episodeCount 集' : '点此导入',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
