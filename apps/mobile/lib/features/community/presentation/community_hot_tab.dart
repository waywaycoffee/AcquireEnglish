import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../authentication/presentation/auth_session.dart';
import '../../daily_review/presentation/daily_review_provider.dart';
import '../../import_course/data/bilibili_open_or_import.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
import 'adventure_ui.dart';
import 'community_provider.dart';
import 'community_social_screen.dart';

class CommunityHotTab extends ConsumerStatefulWidget {
  const CommunityHotTab({super.key});

  @override
  ConsumerState<CommunityHotTab> createState() => _CommunityHotTabState();
}

class _CommunityHotTabState extends ConsumerState<CommunityHotTab> {
  List<Map<String, dynamic>> _packs = const <Map<String, dynamic>>[];
  List<CommunityPostDto> _followingPosts = const <CommunityPostDto>[];
  bool _packsLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadExtras());
    });
  }

  Future<void> _loadExtras() async {
    setState(() => _packsLoading = true);
    try {
      final AcquireApiClient api = ref.read(acquireApiClientProvider);
      final String learnerCefr =
          ref.read(learningPreferencesProvider).level.trim();
      final List<Map<String, dynamic>> packs = await api.listCommunityPacks(
        recommend: true,
        learnerCefr: learnerCefr.isEmpty ? null : learnerCefr,
      );
      List<CommunityPostDto> following = const <CommunityPostDto>[];
      if (ref.read(authSessionProvider).isLoggedIn) {
        try {
          following = await api.communityFeed(following: true, limit: 8);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _followingPosts = following;
        _packsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _packsLoading = false);
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait(<Future<void>>[
      ref.read(communityHotProvider.notifier).refresh(),
      _loadExtras(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<CommunityHotBundle> async =
        ref.watch(communityHotProvider);
    final bool loggedIn = ref.watch(authSessionProvider).isLoggedIn;

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace st) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: <Widget>[Text('加载失败：$e')],
        ),
        data: (CommunityHotBundle data) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              const Text(
                '素材包',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                '社区不存视频本体，只存链接 / 字幕元信息 / 词表说明；可 fork 到自己的库',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (loggedIn)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonal(
                    onPressed: () => unawaited(_createPack(context)),
                    child: const Text('发布素材包'),
                  ),
                ),
              const SizedBox(height: 10),
              if (_packsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_packs.isEmpty)
                QuestFeedCard(
                  title: '还没有公开素材包',
                  meta: '发布含 CEFR / 题材 / 词表的包，或先分享 B 站链接',
                  badge: '等你来发',
                  accent: AppDesignTokens.brandGreen,
                  onPlay: loggedIn
                      ? () => unawaited(_createPack(context))
                      : () {},
                )
              else
                for (final Map<String, dynamic> pack in _packs) ...<Widget>[
                  QuestFeedCard(
                    title: (pack['title'] as String?)?.trim().isNotEmpty == true
                        ? pack['title'] as String
                        : '未命名素材包',
                    meta: <String>[
                      'i+1 推荐',
                      if ((pack['cefr'] as String?)?.isNotEmpty == true)
                        pack['cefr'] as String,
                      if ((pack['topic'] as String?)?.isNotEmpty == true)
                        pack['topic'] as String,
                      'fork ${pack['fork_count'] ?? 0}',
                      if (pack['has_subtitles'] == true) '字幕',
                      if (pack['has_vocab'] == true) '词表',
                    ].join(' · '),
                    badge: pack['has_vocab'] == true ? '词表可导入' : '可 fork',
                    accent: AppDesignTokens.brandGreen,
                    onPlay: () => unawaited(_openPack(context, pack)),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '关注的人',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const CommunitySocialScreen(),
                      ),
                    ),
                    child: const Text('消息与管理'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                loggedIn
                    ? '关注流只看你关心的人的练习与素材'
                    : '登录后可看关注流',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              if (!loggedIn)
                const Text('登录后显示关注流')
              else if (_followingPosts.isEmpty)
                const Text('还没有关注动态；可在帖子操作里关注作者')
              else
                for (final CommunityPostDto post in _followingPosts) ...<Widget>[
                  QuestFeedCard(
                    title: '${post.authorName} · ${post.title.isEmpty ? post.kind : post.title}',
                    meta: post.body.replaceAll('\n', ' '),
                    badge: '关注',
                    accent: AppDesignTokens.brandGreen,
                    authorAvatar: post.authorAvatar,
                    onPlay: () {},
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 16),
              const Text(
                '热门分享链接',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                '社区只存链接与学习笔记，视频请自行准备',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (data.shares.isEmpty)
                QuestFeedCard(
                  title: '还没有人分享学习素材',
                  meta: '去「练习」发一条 B 站链接，或上方发布素材包',
                  badge: '等你来发',
                  accent: AppDesignTokens.brandGreen,
                  onPlay: () {},
                )
              else
                for (final HotShareDto share in data.shares) ...<Widget>[
                  QuestFeedCard(
                    title: share.linkTitle?.isNotEmpty == true
                        ? share.linkTitle!
                        : 'B 站视频任务',
                    meta: share.latestBody?.isNotEmpty == true
                        ? '分享 ${share.shareCount} 次 · ${share.latestBody}'
                        : '分享 ${share.shareCount} 次',
                    badge: '热门',
                    accent: const Color(0xFFE67E22),
                    onPlay: () =>
                        unawaited(_openShare(context, ref, share.linkUrl)),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 12),
              const Text(
                '热门 · 关注的 UP',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                '关注后新视频会出现在首页推荐；导入仍需你确认',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (data.creators.isEmpty)
                Text(
                  '暂无聚合数据。去「关注博主」添加你喜欢的 B 站 UP 主吧。',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.textSecondary,
                  ),
                )
              else
                for (final HotCreatorDto creator in data.creators) ...<Widget>[
                  QuestFeedCard(
                    title: creator.displayName.isEmpty
                        ? creator.creatorId
                        : creator.displayName,
                    meta: 'B站 · ${creator.followerCount} 人关注',
                    badge: '关注',
                    accent: AppDesignTokens.brandGreen,
                    onPlay: () =>
                        unawaited(_followCreator(context, ref, creator)),
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _parseVocabLines(String raw) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    final Set<String> seen = <String>{};
    for (final String line in raw.split(RegExp(r'[\n,;]+'))) {
      final String text = line.trim();
      if (text.isEmpty) continue;
      String word = text;
      String gloss = '';
      for (final String sep in <String>['\t', '|', '：', ':']) {
        final int idx = text.indexOf(sep);
        if (idx > 0) {
          word = text.substring(0, idx).trim();
          gloss = text.substring(idx + sep.length).trim();
          break;
        }
      }
      final String key = word.toLowerCase();
      if (key.length < 2 || !seen.add(key)) continue;
      out.add(<String, dynamic>{
        'word': word,
        if (gloss.isNotEmpty) 'gloss': gloss,
      });
      if (out.length >= 200) break;
    }
    return out;
  }

  Future<void> _createPack(BuildContext context) async {
    final TextEditingController title = TextEditingController();
    final TextEditingController url = TextEditingController();
    final TextEditingController cefr = TextEditingController(text: 'B1');
    final TextEditingController topic = TextEditingController(text: 'daily');
    final TextEditingController vocab = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('发布素材包'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '不上传视频文件；只保存来源链接、学习元信息与可选词表。',
                style: TextStyle(fontSize: 12),
              ),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'B 站链接（可选）'),
              ),
              TextField(
                controller: cefr,
                decoration: const InputDecoration(labelText: 'CEFR'),
              ),
              TextField(
                controller: topic,
                decoration: const InputDecoration(labelText: '题材'),
              ),
              TextField(
                controller: vocab,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '词表（可选，一行一词）',
                  hintText: 'apple:苹果\norder|点单',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('发布'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题')),
      );
      return;
    }
    final List<Map<String, dynamic>> vocabRows =
        _parseVocabLines(vocab.text);
    try {
      await ref.read(acquireApiClientProvider).createCommunityPack(
        <String, dynamic>{
          'title': title.text.trim(),
          if (url.text.trim().isNotEmpty) 'source_url': url.text.trim(),
          if (cefr.text.trim().isNotEmpty) 'cefr': cefr.text.trim(),
          if (topic.text.trim().isNotEmpty) 'topic': topic.text.trim(),
          'has_subtitles': false,
          'has_vocab': vocabRows.isNotEmpty,
          'visibility': 'public',
          if (vocabRows.isNotEmpty)
            'meta': <String, dynamic>{'vocab': vocabRows},
        },
      );
      await _loadExtras();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('素材包已发布')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败：$e')),
      );
    }
  }

  Future<void> _openPack(
    BuildContext context,
    Map<String, dynamic> pack,
  ) async {
    final int packId = (pack['id'] as num?)?.toInt() ?? 0;
    final String? sourceUrl = pack['source_url'] as String?;
    final bool isFork = pack['forked_from_id'] != null;
    await showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                (pack['title'] as String?) ?? '素材包',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                (pack['description'] as String?)?.trim().isNotEmpty == true
                    ? pack['description'] as String
                    : '社区不存视频本体；导入播放器时请自备合法片源。',
              ),
              const SizedBox(height: 12),
              if (sourceUrl != null && sourceUrl.isNotEmpty)
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    unawaited(_openShare(context, ref, sourceUrl));
                  },
                  child: const Text('导入播放器'),
                ),
              const SizedBox(height: 8),
              if (ref.read(authSessionProvider).isLoggedIn && packId > 0) ...<
                  Widget>[
                FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await ref.read(acquireApiClientProvider).forkCommunityPack(
                            packId,
                            syncUpstream: false,
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadExtras();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已 fork 到我的库（默认不同步上游）'),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('fork 失败：$e')),
                      );
                    }
                  },
                  child: const Text('Fork 到我的库'),
                ),
                if (isFork)
                  TextButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(acquireApiClientProvider)
                            .syncCommunityPackUpstream(packId);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已同步上游元信息')),
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('同步失败：$e')),
                        );
                      }
                    },
                    child: const Text('同步上游'),
                  ),
              ],
              TextButton(
                onPressed: () async {
                  final Object? metaRaw = pack['meta'];
                  final Map<String, dynamic> meta = metaRaw is Map
                      ? Map<String, dynamic>.from(metaRaw)
                      : <String, dynamic>{};
                  final Object? vocabRaw = meta['vocab'];
                  final List<Map<String, dynamic>> vocab = vocabRaw is List
                      ? vocabRaw
                          .whereType<Map>()
                          .map(
                            (Map row) =>
                                Map<String, dynamic>.from(row),
                          )
                          .toList(growable: false)
                      : const <Map<String, dynamic>>[];
                  if (vocab.isEmpty) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('该素材包还没有词表；发布时可粘贴词表'),
                      ),
                    );
                    return;
                  }
                  try {
                    final ({int enrolled, int skipped}) result = await ref
                        .read(dailyReviewProvider.notifier)
                        .importPackVocab(
                          vocab,
                          packTitle: (pack['title'] as String?) ?? '社区素材包',
                        );
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '已导入 ${result.enrolled} 词到 FSRS'
                          '${result.skipped > 0 ? '（跳过 ${result.skipped}）' : ''}',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('导入失败：$e')),
                    );
                  }
                },
                child: const Text('导入词表到 FSRS'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openShare(
    BuildContext context,
    WidgetRef ref,
    String url,
  ) async {
    final String? episodeId = await openBilibiliLearningOrImport(
      context,
      ref,
      watchUrl: url,
      startImportImmediately: true,
      pushPlayer: false,
    );
    if (!context.mounted || episodeId == null) return;
    await context.pushNamed<void>(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: const <String, String>{'autoplay': '1'},
    );
  }

  Future<void> _followCreator(
    BuildContext context,
    WidgetRef ref,
    HotCreatorDto creator,
  ) async {
    try {
      await ref.read(acquireApiClientProvider).followCreator(
            source: creator.source,
            creatorId: creator.creatorId,
            displayName: creator.displayName,
          );
      await ref.read(learningPreferencesProvider.notifier).pullRemote();
      await ref.read(communityHotProvider.notifier).refresh();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已关注 ${creator.displayName.isEmpty ? creator.creatorId : creator.displayName}，首页会推荐其视频',
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('关注失败：$e')),
      );
    }
  }
}
