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
    final List<LibraryCourseData> dramas = pruneSubsumedDramaFlats(
      catalog.where(looksLikeDramaCourse).toList(growable: false),
    );
    // Curated posters own 绝望主妇 etc.; keep「我的已导入」for custom packs only.
    final List<LibraryCourseData> importedShelf =
        dramasOutsideCuratedShelf(dramas);
    if (!_syncedDue && dramas.isNotEmpty) {
      _syncedDue = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDueClipCounts(dramas);
      });
    }

    // Poster tap selects any drama (including curated/public-series).
    LibraryCourseData? selected;
    if (_selectedCourseId != null) {
      for (final LibraryCourseData c in dramas) {
        if (c.id == _selectedCourseId) {
          selected = c;
          break;
        }
      }
    }
    selected ??= importedCourseForCatalogEntry(
          kDramaCatalog.first,
          dramas,
        ) ??
        (importedShelf.isNotEmpty ? importedShelf.first : null) ??
        (dramas.isNotEmpty ? dramas.first : null);

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
            '点海报打开剧集；正版公开片单全员可学，也可从网盘导入自有授权资源。',
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
                  '精选片单 · 点海报打开剧集',
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
          height: 176,
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
                selected: selected?.id == owned?.id && owned != null,
                episodeCount: owned?.episodes.length ?? 0,
                onTap: () => _onCatalogTap(entry, owned),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        const EpisodeStageLegend(),
        if (selected != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '${libraryCourseDisplayTitle(selected)}  ·  '
            '${selected.episodes.length} 集',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
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
          const SizedBox(height: 8),
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
        const SizedBox(height: 16),
        Text(
          '其它已导入  ·  完全掌握 $masteredEps / $totalEps 集'
          '${totalEps == 0 ? '' : ' (${(masteredEps * 100 / totalEps).round()}%)'}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
        ),
        const SizedBox(height: 12),
        if (importedShelf.isEmpty)
          Card(
            color: AppDesignTokens.appWhite,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  Text(
                    dramas.isEmpty
                        ? '还没有可学剧集。等待公开片单同步，或从网盘导入整季文件夹（含字幕）。'
                        : '精选片单点海报即可选集；这里只列未收录进精选的自建导入。',
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
            value: importedShelf.any(
              (LibraryCourseData c) => c.id == selected?.id,
            )
                ? selected!.id
                : importedShelf.first.id,
            decoration: InputDecoration(
              labelText: '自建导入',
              border: const OutlineInputBorder(),
              labelStyle: TextStyle(color: AppDesignTokens.textSecondary),
            ),
            dropdownColor: AppDesignTokens.appWhite,
            items: <DropdownMenuItem<String>>[
              for (final LibraryCourseData c in importedShelf)
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
    if (owned != null && owned.episodes.isNotEmpty) {
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
                  '当前账号还没有这套剧。可下拉刷新同步公开片单，或从网盘导入自有授权资源。',
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
    required this.selected,
    required this.episodeCount,
    required this.onTap,
  });

  final DramaCatalogEntry entry;
  final bool owned;
  final bool selected;
  final int episodeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(entry.accent);
    final String? cover = entry.coverUrl?.trim();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 118,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppDesignTokens.primaryBlueDark
                  : AppDesignTokens.borderGray,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (cover != null && cover.isNotEmpty)
                  Image.network(
                    cover,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => ColoredBox(color: accent),
                    loadingBuilder: (
                      BuildContext context,
                      Widget child,
                      ImageChunkEvent? progress,
                    ) {
                      if (progress == null) return child;
                      return ColoredBox(
                        color: accent,
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    },
                  )
                else
                  ColoredBox(color: accent),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.05),
                        Colors.black.withValues(alpha: 0.78),
                      ],
                    ),
                  ),
                ),
                Padding(
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
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          owned ? '可学 · $episodeCount 集' : '未开通',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
