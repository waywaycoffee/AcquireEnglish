import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
import '../domain/cafe_adventure.dart';
import 'adventure_ui.dart';
import 'cafe_progress_provider.dart';
import 'community_provider.dart';
import 'exploration_map_screen.dart';

class CommunityFeedTab extends ConsumerWidget {
  const CommunityFeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CommunityPostDto>> async = ref.watch(
      communityFeedProvider,
    );

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          onRefresh: () => ref.read(communityFeedProvider.notifier).refresh(),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object e, StackTrace st) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: <Widget>[Text('加载失败：$e')],
            ),
            data: (List<CommunityPostDto> posts) {
              final List<CommunityPostDto> ordered = _orderQuestFirst(posts);
              if (ordered.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    QuestFeedCard(
                      title: '试玩 · 街角咖啡店「看懂菜单」',
                      meta: '通关后可发成果卡，邀人练同一关',
                      badge: '推荐任务',
                      accent: AdventurePalette.pathAmber,
                      onPlay: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => const ExplorationMapScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '任务流优先展示可开练的成果卡。也可分享 B 站视频、组队或提问。',
                    ),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: ordered.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) {
                  if (index == ordered.length)
                    return TextButton(
                      onPressed:
                          ref.read(communityFeedProvider.notifier).hasMore
                          ? () async {
                              try {
                                await ref
                                    .read(communityFeedProvider.notifier)
                                    .loadMore();
                              } catch (_) {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('加载更多失败，请重试')),
                                  );
                              }
                            }
                          : null,
                      child: Text(
                        ref.read(communityFeedProvider.notifier).hasMore
                            ? '加载更多'
                            : '已显示全部内容',
                      ),
                    );
                  return CommunityPostCard(post: ordered[index]);
                },
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: QuestComposerBar(
            onTap: () => unawaited(_showComposer(context, ref)),
          ),
        ),
      ],
    );
  }

  static bool _hasChallenge(CommunityPostDto post) =>
      cafeLevelFromPath(post.linkUrl) != null &&
      (post.kind == 'learning_result' ||
          post.kind == 'method' ||
          post.kind == 'question');

  static List<CommunityPostDto> _orderQuestFirst(List<CommunityPostDto> posts) {
    final List<CommunityPostDto> quests = <CommunityPostDto>[];
    final List<CommunityPostDto> rest = <CommunityPostDto>[];
    for (final CommunityPostDto post in posts) {
      if (_hasChallenge(post)) {
        quests.add(post);
      } else {
        rest.add(post);
      }
    }
    return <CommunityPostDto>[...quests, ...rest];
  }

  Future<void> _showComposer(BuildContext context, WidgetRef ref) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFFF7F1E8),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AdventurePalette.pathAmber,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '分享今天的闯关收获',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
              const SizedBox(height: 12),
              for (final (String id, String title, String meta, Color accent)
                  in <(String, String, String, Color)>[
                (
                  'learning_result',
                  '分享学习成果',
                  '通关后邀人练同一关',
                  AdventurePalette.pathAmber,
                ),
                (
                  'share_bilibili',
                  '分享 B 站视频',
                  '推荐精听片子',
                  AppDesignTokens.brandGreen,
                ),
                (
                  'method',
                  '分享学习方法',
                  '把有效练法写成任务卡',
                  const Color(0xFF5B8DEF),
                ),
                (
                  'question',
                  '学习问答',
                  '卡住的地方喊人一起想',
                  const Color(0xFFE67E22),
                ),
                (
                  'team_invite',
                  '组队邀请',
                  '找搭子一起练',
                  AppDesignTokens.brandGreen,
                ),
                (
                  'feedback',
                  '吐槽软件功能',
                  '反馈缺陷与体验',
                  AppDesignTokens.orange,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: QuestFeedCard(
                    title: title,
                    meta: meta,
                    badge: '发帖',
                    accent: accent,
                    onPlay: () => Navigator.pop(ctx, id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _ComposeSheet(kind: choice),
    );
  }
}

class CommunityPostCard extends ConsumerWidget {
  const CommunityPostCard({required this.post});

  final CommunityPostDto post;

  String get _kindLabel {
    switch (post.kind) {
      case 'team_invite':
        return '组队';
      case 'share_bilibili':
        return '分享';
      case 'feedback':
        return '反馈';
      case 'learning_result':
        return '学习成果';
      case 'method':
        return '学习方法';
      case 'question':
        return '学习问答';
      default:
        return post.kind;
    }
  }

  String get _metaLine {
    final String level = post.authorLevel ?? post.englishLevel ?? '';
    final String when = _relative(post.createdAt);
    if (level.isEmpty) return when;
    return '$when · $level';
  }

  String _relative(DateTime time) {
    final Duration d = DateTime.now().difference(time.toLocal());
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    if (d.inDays < 7) return '${d.inDays} 天前';
    return '${time.month}/${time.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CommunityPostDto post =
        ref.watch(communityPostUpdatesProvider)[this.post.id] ?? this.post;

    final int? challengeLevel = CommunityFeedTab._hasChallenge(post)
        ? cafeLevelFromPath(post.linkUrl)
        : null;
    if (challengeLevel != null) {
      final CafeLevel level = kCafeLevels[challengeLevel];
      final String body = (post.body.trim().isEmpty ? post.title : post.body)
          .replaceAll('\n', ' ');
      final String playMeta = post.challengeCompletes > 0
          ? '$_metaLine · ${level.ability} · ${post.challengeCompletes}人完成 · $body'
          : '$_metaLine · ${level.ability} · $body';
      return QuestFeedCard(
        title: '${post.authorName} · ${level.title}',
        meta: playMeta,
        badge: '可开练',
        accent: AdventurePalette.pathAmber,
        onPlay: () {
          ref.read(pendingChallengePostIdProvider.notifier).set(post.id);
          unawaited(() async {
            try {
              await ref
                  .read(acquireApiClientProvider)
                  .reportChallengeEvent(postId: post.id, event: 'open');
            } catch (_) {}
          }());
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ExplorationMapScreen(sharedLevel: challengeLevel),
            ),
          );
        },
      );
    }
    final String bodyPreview = post.body.trim().isEmpty ? post.title : post.body;
    final String compact = bodyPreview.replaceAll('\n', ' ');
    if (post.isShareBilibili) {
      final String title = post.linkTitle?.trim().isNotEmpty == true
          ? post.linkTitle!.trim()
          : (post.title.isNotEmpty ? post.title : 'B 站视频任务');
      return QuestFeedCard(
        title: '${post.authorName} · $title',
        meta:
            '$_metaLine · ♥${post.likeCount} · 💬${post.commentCount}'
            '${compact.isEmpty ? '' : ' · $compact'}',
        badge: '视频任务',
        accent: const Color(0xFFE67E22),
        onPlay: () => unawaited(_openLink(context, ref)),
      );
    }
    return QuestFeedCard(
      title: '${post.authorName} · ${_kindLabel}',
      meta: '$_metaLine · ♥${post.likeCount} · 💬${post.commentCount} · $compact',
      badge: _kindLabel,
      accent: post.kind == 'method'
          ? const Color(0xFF5B8DEF)
          : post.kind == 'question'
              ? const Color(0xFFE67E22)
              : post.kind == 'feedback'
                  ? AppDesignTokens.orange
                  : AppDesignTokens.brandGreen,
      onPlay: () => unawaited(_openComments(context, ref)),
    );
  }

  Future<void> _openLink(BuildContext context, WidgetRef ref) async {
    final String? url = post.linkUrl?.trim();
    if (url == null || url.isEmpty) return;
    final String? episodeId = await showBilibiliImportSheet(
      context,
      ref,
      initialUrl: url,
      startImmediately: true,
    );
    if (!context.mounted || episodeId == null) return;
    await context.pushNamed<void>(
      SGRoute.player.name,
      pathParameters: <String, String>{'episodeId': episodeId},
      queryParameters: const <String, String>{'autoplay': '1'},
    );
  }

  Future<void> _openComments(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _CommentsSheet(post: post),
    );
    await ref.read(communityFeedProvider.notifier).refresh();
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  const _CommentsSheet({required this.post});

  final CommunityPostDto post;

  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final TextEditingController _body = TextEditingController();
  List<CommunityCommentDto> _comments = <CommunityCommentDto>[];
  bool _loading = true;
  bool _busy = false;
  bool _mirror = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<CommunityCommentDto> rows = await ref
          .read(acquireApiClientProvider)
          .communityComments(widget.post.id);
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('评论加载失败：$e')));
    }
  }

  Future<void> _submit() async {
    final String text = _body.text.trim();
    if (text.isEmpty || _busy) return;
    final bool hasCookie = ref
        .read(learningPreferencesProvider)
        .hasBilibiliCookie;
    if (_mirror && !hasCookie) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中授权 B 站 Cookie，再同步评论')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final CommunityCommentDto created = await ref
          .read(acquireApiClientProvider)
          .createCommunityComment(
            postId: widget.post.id,
            body: text,
            mirrorToBilibili: _mirror,
          );
      if (!mounted) return;
      _body.clear();
      setState(() {
        _comments = <CommunityCommentDto>[..._comments, created];
        _busy = false;
      });
      if (created.mirroredToBilibili) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已同步到 B 站视频评论区')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发送失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets inset = MediaQuery.viewInsetsOf(context);
    final bool canMirror = widget.post.isShareBilibili;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + inset.bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.post.title.isEmpty ? '评论' : widget.post.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                  ? const Center(child: Text('还没有评论，来说两句吧'))
                  : ListView.separated(
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final CommunityCommentDto c = _comments[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.authorName),
                          subtitle: Text(c.body),
                          trailing: c.mirroredToBilibili
                              ? const Icon(Icons.sync, size: 18)
                              : null,
                        );
                      },
                    ),
            ),
            if (canMirror)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('一键同步到 B 站评论区'),
                subtitle: const Text('需已授权 B 站登录 Cookie'),
                value: _mirror,
                onChanged: (bool v) => setState(() => _mirror = v),
              ),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _body,
                    decoration: const InputDecoration(
                      hintText: '写评论…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? '…' : '发送'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposeSheet extends ConsumerStatefulWidget {
  const _ComposeSheet({required this.kind});

  final String kind;

  @override
  ConsumerState<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends ConsumerState<_ComposeSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _link = TextEditingController();
  bool _busy = false;
  int? _challengeLevel;

  bool get _canAttachChallenge =>
      widget.kind == 'learning_result' ||
      widget.kind == 'method' ||
      widget.kind == 'question';

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _link.dispose();
    super.dispose();
  }

  String get _heading {
    switch (widget.kind) {
      case 'team_invite':
        return '组队邀请';
      case 'share_bilibili':
        return '分享你喜欢的 B 站视频';
      default:
        return widget.kind == 'learning_result'
            ? '分享学习成果'
            : widget.kind == 'method'
            ? '分享学习方法'
            : widget.kind == 'question'
            ? '提出学习问题'
            : '反馈软件功能';
    }
  }

  bool _isYoutubeUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String host = uri.host.toLowerCase().replaceFirst('www.', '');
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host.endsWith('.youtube.com');
  }

  bool _isBilibiliUrl(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String host = uri.host.toLowerCase().replaceFirst('www.', '');
    return host == 'bilibili.com' ||
        host.endsWith('.bilibili.com') ||
        host == 'b23.tv';
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (widget.kind == 'share_bilibili') {
      final String link = _link.text.trim();
      if (link.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请粘贴 B 站视频链接')));
        return;
      }
      if (_isYoutubeUrl(link)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('因政策原因，暂时不支持分享 YouTube 视频，请改用 B 站链接')),
        );
        return;
      }
      if (!_isBilibiliUrl(link)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目前仅支持 bilibili.com / b23.tv 链接')),
        );
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final String? challengePath = _canAttachChallenge && _challengeLevel != null
          ? cafeChallengePath(_challengeLevel!)
          : null;
      await ref
          .read(communityFeedProvider.notifier)
          .createPost(
            kind: widget.kind,
            title: _title.text.trim(),
            body: _body.text.trim(),
            linkUrl: widget.kind == 'share_bilibili'
                ? _link.text.trim()
                : challengePath,
            linkTitle: widget.kind == 'share_bilibili'
                ? _title.text.trim()
                : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已发布')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('发布失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + pad.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '内容',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.kind == 'share_bilibili') ...<Widget>[
              const SizedBox(height: 10),
              Text(
                '后台会自动归类兴趣领域与英语难度；若不准，其他同学可申请纠错。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                  labelText: 'B 站视频链接',
                  hintText: 'https://www.bilibili.com/video/… 或 b23.tv/…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_canAttachChallenge) ...<Widget>[
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                value: _challengeLevel,
                decoration: const InputDecoration(
                  labelText: '关联关卡（可选）',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('不关联关卡'),
                  ),
                  for (int i = 0; i < kCafeLevels.length; i++)
                    DropdownMenuItem<int?>(
                      value: i,
                      child: Text('街角咖啡店 · ${kCafeLevels[i].title}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (int? value) => setState(() => _challengeLevel = value),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? '发布中…' : '发布'),
            ),
          ],
        ),
      ),
    );
  }
}
