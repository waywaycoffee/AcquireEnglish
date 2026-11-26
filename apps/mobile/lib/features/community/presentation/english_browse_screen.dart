import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../import_course/data/bilibili_open_or_import.dart';
import '../../library/presentation/library_catalog_provider.dart';
import '../../library/presentation/library_mock_data.dart';
import '../../../router/app_router.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/english_browse_actions.dart';
import '../data/english_browse_store.dart';
import 'english_browse_provider.dart';

enum _BrowsePane { daily, history, study }

/// English-audio-first Bilibili browse (video module 「全英可逛」).
class EnglishBrowseScreen extends ConsumerStatefulWidget {
  const EnglishBrowseScreen({
    this.embedded = false,
    this.initialLevel = 'A2',
    super.key,
  });

  static const String route = '/community/english-browse';

  /// When true, omit Scaffold/AppBar for embedding in [LibraryScreen].
  final bool embedded;
  final String initialLevel;

  static const List<String> cefrLevels = <String>[
    'A1',
    'A2',
    'B1',
    'B2',
    'C1',
    'C2',
  ];

  @override
  ConsumerState<EnglishBrowseScreen> createState() =>
      _EnglishBrowseScreenState();
}

class _EnglishBrowseScreenState extends ConsumerState<EnglishBrowseScreen> {
  final TextEditingController _query = TextEditingController();
  late String _level;
  _BrowsePane _pane = _BrowsePane.daily;

  /// Non-null only while a keyword search is active (bypasses daily shelf).
  Future<List<AcquireDailyFeedItemDto>>? _searchFuture;

  @override
  void initState() {
    super.initState();
    _level = EnglishBrowseScreen.cefrLevels.contains(widget.initialLevel)
        ? widget.initialLevel
        : 'A2';
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _hasQuery => _query.text.trim().isNotEmpty;

  Future<List<AcquireDailyFeedItemDto>> _search({
    required String q,
    String? level,
  }) {
    return ref.read(acquireApiClientProvider).englishBrowseFeed(
          query: q,
          level: level ?? _level,
        );
  }

  void _runSearch({String? q, String? level}) {
    final String query = (q ?? _query.text).trim();
    if (query.isEmpty) {
      setState(() => _searchFuture = null);
      return;
    }
    setState(() {
      if (level != null) _level = level;
      _searchFuture = _search(q: query, level: level);
      _pane = _BrowsePane.daily;
    });
  }

  void _clearSearchToDaily() {
    _query.clear();
    setState(() => _searchFuture = null);
  }

  Future<void> _onPullRefresh() async {
    if (_pane != _BrowsePane.daily) {
      ref.invalidate(englishBrowseStoreProvider);
      return;
    }
    if (_hasQuery) {
      final Future<List<AcquireDailyFeedItemDto>> next = _search(q: _query.text);
      setState(() => _searchFuture = next);
      await next;
      return;
    }
    ref.invalidate(englishBrowseDailyProvider(_level));
    await ref.read(englishBrowseDailyProvider(_level).future);
  }

  String _formatDuration(double? sec) {
    if (sec == null || sec <= 0) return '';
    final int total = sec.round();
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _openFeedItem(AcquireDailyFeedItemDto item) async {
    await openEnglishBrowsePreview(context, ref, item: item);
  }

  Future<void> _openStored(EnglishBrowseEntry entry) async {
    final AcquireDailyFeedItemDto feedItem = AcquireDailyFeedItemDto(
      id: entry.bvid.isEmpty ? entry.watchUrl : entry.bvid,
      bvid: entry.bvid,
      title: entry.title,
      watchUrl: entry.watchUrl,
      author: entry.author,
      coverUrl: entry.coverUrl.isEmpty ? null : entry.coverUrl,
    );
    if (entry.episodeId.isNotEmpty) {
      final bool exists = ref.read(libraryCatalogProvider).any(
            (LibraryCourseData c) =>
                c.episodes.any((LibraryEpisodeItem e) => e.id == entry.episodeId),
          );
      if (exists && context.mounted) {
        await context.pushNamed<void>(
          SGRoute.player.name,
          pathParameters: <String, String>{'episodeId': entry.episodeId},
          queryParameters: <String, String>{
            if (!entry.inStudyList) 'preview': '1',
            'autoplay': '1',
          },
        );
        if (!context.mounted) return;
        // Replay from history still asks until the user likes / favorites.
        if (!entry.inStudyList) {
          await askEnglishBrowseLikeAfterPreview(
            context,
            ref,
            item: feedItem,
            episodeId: entry.episodeId,
            courseId: entry.courseId,
          );
        }
        return;
      }
    }
    await openEnglishBrowsePreview(context, ref, item: feedItem);
  }

  Widget _paneChips() {
    Widget chip(_BrowsePane pane, String label) {
      final bool selected = _pane == pane;
      return FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => setState(() => _pane = pane),
        selectedColor: AppDesignTokens.primaryBlue.withValues(alpha: 0.2),
        checkmarkColor: AppDesignTokens.primaryBlue,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected
              ? AppDesignTokens.textPrimary
              : AppDesignTokens.textSecondary,
        ),
        backgroundColor: AppDesignTokens.appWhite,
        side: BorderSide(color: AppDesignTokens.borderGray),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: <Widget>[
          chip(_BrowsePane.daily, '今日精选'),
          const SizedBox(width: 8),
          chip(_BrowsePane.history, '播放记录'),
          const SizedBox(width: 8),
          chip(_BrowsePane.study, '我的学习'),
        ],
      ),
    );
  }

  Widget _feedCard(AcquireDailyFeedItemDto item) {
    final String duration = _formatDuration(item.durationSec);
    final bool verified = item.tags.contains('抽样英语原声');
    final String badge = verified ? '英语原声' : '原声待确认';
    final bool favorited = ref
        .watch(englishBrowseStoreProvider)
        .any(
          (EnglishBrowseEntry e) =>
              e.watchUrl.trim().toLowerCase() ==
                  item.watchUrl.trim().toLowerCase() &&
              e.favorited,
        );
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => unawaited(_openFeedItem(item)),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              height: 1.25,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            <String>[
                              if (item.author.isNotEmpty) item.author,
                              if (duration.isNotEmpty) duration,
                              badge,
                              '点按在线试看',
                            ].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: verified
                                  ? AppDesignTokens.brandGreen
                                  : AppDesignTokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: favorited ? '已收藏' : '收藏到学习列表',
              onPressed: () async {
                await favoriteEnglishBrowseItem(ref, item: item);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      favorited ? '已在学习列表' : '已收藏，可在「我的学习」长期学习',
                    ),
                  ),
                );
                setState(() {});
              },
              icon: Icon(
                favorited ? Icons.favorite : Icons.favorite_border,
                color: favorited
                    ? AppDesignTokens.brandGreen
                    : AppDesignTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _storedCard(EnglishBrowseEntry entry) {
    final String badge = entry.inStudyList
        ? <String>[
            if (entry.liked) '喜欢',
            if (entry.favorited) '收藏',
            if (entry.reserved) '已预约字幕',
          ].join(' · ')
        : '播放记录';
    return Material(
      color: AppDesignTokens.appWhite,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => unawaited(_openStored(entry)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 118,
                  height: 74,
                  child: CoverImage(path: entry.coverUrl, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title.isEmpty ? entry.watchUrl : entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      <String>[
                        if (entry.author.isNotEmpty) entry.author,
                        badge,
                      ].join(' · '),
                      maxLines: 2,
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
              if (entry.inStudyList)
                IconButton(
                  tooltip: '下载合集',
                  onPressed: () => unawaited(
                    downloadBilibiliCollectionForWatchUrl(
                      context,
                      ref,
                      watchUrl: entry.watchUrl,
                    ),
                  ),
                  icon: const Icon(Icons.download_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _listForFeed(List<AcquireDailyFeedItemDto> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('暂时没有可逛的英语原声片，稍后再试或换个关键词 / 难度。'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) =>
            _feedCard(items[index]),
      ),
    );
  }

  Widget _listForStored(List<EnglishBrowseEntry> items, {required String empty}) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(empty),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onPullRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int index) =>
            _storedCard(items[index]),
      ),
    );
  }

  Widget _buildListPane() {
    if (_pane == _BrowsePane.history) {
      final List<EnglishBrowseEntry> history =
          ref.watch(englishBrowseStoreProvider);
      return _listForStored(history, empty: '还没有播放记录。去「今日精选」点开试看吧。');
    }
    if (_pane == _BrowsePane.study) {
      final List<EnglishBrowseEntry> study = ref
          .watch(englishBrowseStoreProvider)
          .where((EnglishBrowseEntry e) => e.inStudyList)
          .toList(growable: false);
      return _listForStored(
        study,
        empty: '还没有长期学习片。试看后点「喜欢」，或点爱心收藏。',
      );
    }

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
                child: Text('搜索失败：${snapshot.error}'),
              ),
            );
          }
          return _listForFeed(snapshot.data ?? const <AcquireDailyFeedItemDto>[]);
        },
      );
    }

    final AsyncValue<List<AcquireDailyFeedItemDto>> daily =
        ref.watch(englishBrowseDailyProvider(_level));
    return daily.when(
      data: _listForFeed,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('加载失败：$error'),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (String value) => _runSearch(q: value),
            decoration: InputDecoration(
              hintText: '搜索英语原声关键词',
              filled: true,
              fillColor: AppDesignTokens.appWhite,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _hasQuery
                  ? IconButton(
                      tooltip: '清除',
                      onPressed: _clearSearchToDaily,
                      icon: const Icon(Icons.close),
                    )
                  : IconButton(
                      tooltip: '搜索',
                      onPressed: () => _runSearch(),
                      icon: const Icon(Icons.arrow_forward),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: AppDesignTokens.borderGray),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              for (final String level in EnglishBrowseScreen.cefrLevels) ...<Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(level),
                    selected: _level == level,
                    onSelected: (_) {
                      setState(() => _level = level);
                      if (_hasQuery) {
                        _runSearch(level: level);
                      }
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
        _paneChips(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            switch (_pane) {
              _BrowsePane.daily => '点卡片默认在线试看；退出时询问是否喜欢，喜欢再下载并预约字幕。',
              _BrowsePane.history => '点开过的片子都会留在这里。',
              _BrowsePane.study => '收藏、喜欢或已预约字幕的片子，可长期播放学习。',
            },
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppDesignTokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: _buildListPane()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: AppDesignTokens.softWhite,
        child: _buildBody(),
      );
    }
    return Scaffold(
      backgroundColor: AppDesignTokens.softWhite,
      appBar: AppBar(
        title: const Text('全英可逛'),
        backgroundColor: AppDesignTokens.appWhite,
      ),
      body: _buildBody(),
    );
  }
}
