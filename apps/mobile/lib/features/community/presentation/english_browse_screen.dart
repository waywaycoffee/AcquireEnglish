import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import_course/data/bilibili_open_or_import.dart';
import '../../import_course/presentation/bilibili_collection_reservation.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import 'english_browse_provider.dart';

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
    });
  }

  void _clearSearchToDaily() {
    _query.clear();
    setState(() => _searchFuture = null);
  }

  Future<void> _onPullRefresh() async {
    if (_hasQuery) {
      final Future<List<AcquireDailyFeedItemDto>> next = _search(q: _query.text);
      setState(() => _searchFuture = next);
      await next;
      return;
    }
    // Re-fetch shared daily list from server (same day → same items, fast).
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

  Widget _listFor(List<AcquireDailyFeedItemDto> items) {
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
        itemBuilder: (BuildContext context, int index) {
          final AcquireDailyFeedItemDto item = items[index];
          final String duration = _formatDuration(item.durationSec);
          final bool verified = item.tags.contains('抽样英语原声');
          final String badge = verified ? '英语原声' : '原声待确认';
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
                      onTap: () => unawaited(
                        openBilibiliLearningOrImport(
                          context,
                          ref,
                          watchUrl: item.watchUrl,
                          startImportImmediately: true,
                        ),
                      ),
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
                                  ].join(' · '),
                                  maxLines: 1,
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
                  BilibiliCollectionReservation(
                    key: ValueKey<String>('reserve-${item.watchUrl}'),
                    source: item.watchUrl,
                  ),
                ],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('加载失败：${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => _runSearch(),
                      child: const Text('重试'),
                    ),
                  ],
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
        ref.watch(englishBrowseDailyProvider(_level));
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
                  ref.invalidate(englishBrowseDailyProvider(_level));
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
                '今日全站同一份英语原声精选（按难度每天只生成一次）；点封面试看并导入学习。'
                ' 搜关键词会临时实时检索。',
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
                    for (final String level in EnglishBrowseScreen.cefrLevels)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(level),
                          selected: _level == level,
                          onSelected: (bool selected) {
                            if (!selected || _level == level) return;
                            setState(() {
                              _level = level;
                              if (_hasQuery) {
                                _searchFuture = _search(
                                  q: _query.text,
                                  level: level,
                                );
                              } else {
                                _searchFuture = null;
                              }
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
                  hintText: '可选关键词，如 TED、vlog、podcast',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _hasQuery
                      ? IconButton(
                          tooltip: '回到今日列表',
                          onPressed: _clearSearchToDaily,
                          icon: const Icon(Icons.close_rounded),
                        )
                      : IconButton(
                          onPressed: () => _runSearch(),
                          icon: const Icon(Icons.arrow_forward_rounded),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (String value) => _runSearch(q: value),
              ),
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
      appBar: AppBar(
        title: const Text('全英可逛'),
        actions: <Widget>[
          IconButton(
            tooltip: _hasQuery ? '重新搜索' : '重新拉取今日列表',
            onPressed: () => unawaited(_onPullRefresh()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
