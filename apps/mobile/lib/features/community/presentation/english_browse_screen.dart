import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../import_course/data/bilibili_open_or_import.dart';
import '../../shared/presentation/media/cover_image.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';

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
  late Future<List<AcquireDailyFeedItemDto>> _future;

  @override
  void initState() {
    super.initState();
    _level = EnglishBrowseScreen.cefrLevels.contains(widget.initialLevel)
        ? widget.initialLevel
        : 'A2';
    _future = _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<List<AcquireDailyFeedItemDto>> _load({String? q, String? level}) {
    return ref.read(acquireApiClientProvider).englishBrowseFeed(
          query: q,
          level: level ?? _level,
        );
  }

  void _reload({String? q, String? level}) {
    setState(() => _future = _load(q: q, level: level));
  }

  String _formatDuration(double? sec) {
    if (sec == null || sec <= 0) return '';
    final int total = sec.round();
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
                '优先展示抽样确认为英语原声的 B 站视频；点封面试看并导入学习。'
                ' 可按 CEFR 难度筛选。',
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
                            setState(() => _level = level);
                            _reload(q: _query.text, level: level);
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
                  suffixIcon: IconButton(
                    onPressed: () => _reload(q: _query.text),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  isDense: true,
                ),
                onSubmitted: (String value) => _reload(q: value),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<AcquireDailyFeedItemDto>>(
            future: _future,
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
                          onPressed: () => _reload(q: _query.text),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final List<AcquireDailyFeedItemDto> items =
                  snapshot.data ?? const <AcquireDailyFeedItemDto>[];
              if (items.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂时没有可逛的英语原声片，稍后再试或换个关键词 / 难度。'),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(q: _query.text),
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
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => unawaited(
                          openBilibiliLearningOrImport(
                            context,
                            ref,
                            watchUrl: item.watchUrl,
                            startImportImmediately: true,
                          ),
                        ),
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
                    );
                  },
                ),
              );
            },
          ),
        ),
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
            tooltip: '刷新',
            onPressed: () => _reload(q: _query.text),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}
