import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../import_course/data/youtube_education_discovery.dart';
import '../../import_course/data/youtube_import_actions.dart';
import '../../import_course/presentation/youtube_import_sheet.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/widgets/youtube_brand_icon.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import 'youtube_browse_provider.dart';

/// YouTube English-education browse (Library 「YouTube」 shelf).
class YoutubeBrowseScreen extends ConsumerStatefulWidget {
  const YoutubeBrowseScreen({
    this.embedded = false,
    this.initialLevel,
    super.key,
  });

  final bool embedded;
  final String? initialLevel;

  static const List<String> cefrLevels = <String>[
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];

  @override
  ConsumerState<YoutubeBrowseScreen> createState() =>
      _YoutubeBrowseScreenState();
}

class _YoutubeBrowseScreenState extends ConsumerState<YoutubeBrowseScreen> {
  String? _openingVideoId;

  Future<void> _openVideo(AcquireDailyFeedItemDto item) async {
    if (_openingVideoId != null) return;
    setState(() => _openingVideoId = item.bvid);
    try {
      await importYoutubeVideoById(context, ref, videoId: item.bvid, level: _level);
    } finally {
      if (mounted) setState(() => _openingVideoId = null);
    }
  }

  final TextEditingController _query = TextEditingController();
  late String _level;
  bool _discovering = false;
  String? _discoverHint;
  Future<List<AcquireDailyFeedItemDto>>? _searchFuture;

  @override
  void initState() {
    super.initState();
    final String pref = ref.read(learningPreferencesProvider).level.trim();
    final String fromWidget = (widget.initialLevel ?? '').trim();
    final String pick = fromWidget.isNotEmpty ? fromWidget : pref;
    _level = YoutubeBrowseScreen.cefrLevels.contains(pick.toUpperCase())
        ? pick.toUpperCase()
        : 'A2';
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _hasQuery => _query.text.trim().isNotEmpty;

  Future<void> _runLocalSearch(String raw) async {
    final String q = raw.trim();
    if (q.isEmpty) {
      setState(() => _searchFuture = null);
      return;
    }
    setState(() {
      _searchFuture = const YoutubeEducationDiscovery().searchEducation(
        queries: <String>['$q english learning -news -politics'],
        perQuery: 20,
        maxTotal: 36,
      );
    });
  }

  Future<void> _discoverWithVpn({bool replace = false}) async {
    if (_discovering) return;
    setState(() {
      _discovering = true;
      _discoverHint = '正在用本机网络检索英语教育视频…';
    });
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      List<String> queries = const <String>[];
      try {
        queries = await api.youtubeBrowseQueries(level: _level);
      } catch (_) {}
      if (queries.isEmpty) {
        queries = <String>[
          '$_level english conversation practice -news -politics',
          '$_level english listening lesson -news',
        ];
      }
      final List<AcquireDailyFeedItemDto> hits =
          await const YoutubeEducationDiscovery().searchEducation(
        queries: queries,
        perQuery: 10,
        maxTotal: 36,
      );
      if (!mounted) return;
      if (hits.isEmpty) {
        setState(() {
          _discoverHint = '未搜到可用结果。请确认梯子已开启且能打开 YouTube。';
        });
        return;
      }
      final bool loggedIn = ref.read(authSessionProvider).isLoggedIn;
      if (loggedIn) {
        try {
          await api.contributeYoutubeBrowse(
            level: _level,
            items: hits,
            replace: replace,
          );
        } catch (_) {
          // Still show local hits if contribute fails.
        }
      }
      ref.invalidate(youtubeBrowseDailyProvider(_level));
      setState(() {
        _searchFuture = null;
        _discoverHint = loggedIn
            ? '已更新今日全站列表（${hits.length} 条教育向视频）。'
            : '本机发现 ${hits.length} 条；登录后可同步给全站用户。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _discoverHint = '发现失败（通常是未开梯子）：$e';
      });
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _onPullRefresh() async {
    if (_hasQuery) {
      await _runLocalSearch(_query.text);
      return;
    }
    ref.invalidate(youtubeBrowseDailyProvider(_level));
    await ref.read(youtubeBrowseDailyProvider(_level).future);
  }

  String _formatDuration(double? sec) {
    if (sec == null || sec <= 0) return '';
    final int total = sec.round();
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _listFor(List<AcquireDailyFeedItemDto> items) {
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            '今日列表为空。点下方「用梯子刷新今日发现」生成英语教育类片单'
            '（自动排除时政/新闻与中文博主）。',
            style: TextStyle(
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _discovering ? null : () => unawaited(_discoverWithVpn()),
            icon: const Icon(Icons.travel_explore_rounded),
            label: const Text('用梯子刷新今日发现'),
          ),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) {
          final AcquireDailyFeedItemDto item = items[index];
          final String duration = _formatDuration(item.durationSec);
          return Material(
            color: AppDesignTokens.appWhite,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openingVideoId == null
                  ? () => unawaited(_openVideo(item))
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 118,
                        height: 74,
                        child: CoverImage(
                          path: item.coverUrl ?? '',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.25,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            <String>[
                              if (item.author.isNotEmpty) item.author,
                              if (duration.isNotEmpty) duration,
                              _openingVideoId == item.bvid ? '正在打开…' : '英语教育',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildListPane() {
    if (_searchFuture != null) {
      return FutureBuilder<List<AcquireDailyFeedItemDto>>(
        future: _searchFuture,
        builder: (
          BuildContext context,
          AsyncSnapshot<List<AcquireDailyFeedItemDto>> snapshot,
        ) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '搜索失败（需梯子）：${snapshot.error}',
                  style: TextStyle(color: AppDesignTokens.textSecondary),
                ),
              ),
            );
          }
          return _listFor(
            snapshot.data ?? const <AcquireDailyFeedItemDto>[],
          );
        },
      );
    }

    final AsyncValue<List<AcquireDailyFeedItemDto>> async =
        ref.watch(youtubeBrowseDailyProvider(_level));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object err, StackTrace _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('加载失败：$err'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  ref.invalidate(youtubeBrowseDailyProvider(_level));
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: _listFor,
    );
  }

  Widget _buildBody() {
    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.embedded ? 8 : 12,
            16,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '按你的难度提供英语教育类片单：屏蔽时政/新闻与中文博主。'
                ' 播放与导入需自备梯子；有梯子时可刷新发现并同步给全站。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final String level in YoutubeBrowseScreen.cefrLevels)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(level),
                          selected: _level == level,
                          onSelected: (bool selected) {
                            if (!selected || _level == level) return;
                            setState(() {
                              _level = level;
                              _searchFuture = null;
                              _discoverHint = null;
                            });
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '本机搜索（需梯子），如 TED-Ed、pronunciation',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _hasQuery
                      ? IconButton(
                          tooltip: '回到今日列表',
                          onPressed: () {
                            _query.clear();
                            setState(() => _searchFuture = null);
                          },
                          icon: const Icon(Icons.close_rounded),
                        )
                      : IconButton(
                          onPressed: () =>
                              unawaited(_runLocalSearch(_query.text)),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (String value) =>
                    unawaited(_runLocalSearch(value)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed:
                        _discovering ? null : () => unawaited(_discoverWithVpn()),
                    icon: _discovering
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.travel_explore_rounded),
                    label: Text(_discovering ? '发现中…' : '用梯子刷新今日发现'),
                  ),
                  FilledButton.icon(
                    onPressed: () => unawaited(
                      showYoutubeImportSheet(context, ref),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: YoutubeBrandIcon.brandRed,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    icon: const YoutubeBrandIcon(size: 20),
                    label: const Text(
                      '粘贴链接导入',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              if (_discoverHint != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _discoverHint!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.brandGreen,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(child: _buildListPane()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        title: const Text('YouTube 英语教育'),
        backgroundColor: AppDesignTokens.softWhite,
      ),
      body: _buildBody(),
    );
  }
}
