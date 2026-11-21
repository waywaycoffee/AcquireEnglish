import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../../utils/url_utils.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
import '../../shared/presentation/pad/app_design_tokens.dart';
import '../../shared/presentation/pad/hub_ui.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
import '../domain/cafe_adventure.dart';
import 'adventure_ui.dart';
import 'cafe_progress_provider.dart';
import 'community_provider.dart';
import 'community_post_actions.dart';
import 'exploration_map_screen.dart';
import '../../avatar/presentation/avatar_preview.dart';

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
          right: 16,
          bottom: 16,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              boxShadow: AppDesignTokens.toyButtonShadow,
              shape: BoxShape.circle,
            ),
            child: FloatingActionButton(
              onPressed: () => _showComposer(context, ref),
              backgroundColor: AppDesignTokens.brandGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              child: const Icon(Icons.add_rounded, size: 28),
            ),
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
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择帖子类型',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('分享 B 站视频'),
              subtitle: const Text('推荐你喜欢的精听片子（主打）'),
              onTap: () => Navigator.pop(ctx, 'share_bilibili'),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('组队邀请'),
              subtitle: const Text('找英语学习搭子一起练'),
              onTap: () => Navigator.pop(ctx, 'team_invite'),
            ),
            ListTile(
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('分享学习成果'),
              onTap: () => Navigator.pop(ctx, 'learning_result'),
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('分享学习方法'),
              onTap: () => Navigator.pop(ctx, 'method'),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('学习问答'),
              onTap: () => Navigator.pop(ctx, 'question'),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('吐槽软件功能'),
              subtitle: const Text('反馈缺陷与体验问题'),
              onTap: () => Navigator.pop(ctx, 'feedback'),
            ),
          ],
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

  Color get _kindTint {
    switch (post.kind) {
      case 'team_invite':
        return const Color(0xFFE8F8D8);
      case 'feedback':
        return AppDesignTokens.pinkLight;
      default:
        return AppDesignTokens.skyLight;
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
    final String? cover = post.linkCover?.trim();
    if (challengeLevel != null) {
      final CafeLevel level = kCafeLevels[challengeLevel];
      final String playMeta = post.challengeCompletes > 0
          ? '${_metaLine} · ${level.ability} · ${post.challengeCompletes}人完成'
          : '${_metaLine} · ${level.ability}';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          QuestFeedCard(
            title: '${post.authorName} · ${level.title}',
            meta: playMeta,
            badge: '可开练',
            accent: AdventurePalette.pathAmber,
            onPlay: () {
              ref.read(pendingChallengePostIdProvider.notifier).state = post.id;
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
          ),
          const SizedBox(height: 8),
          HubSurface(
            onTap: () => unawaited(_openComments(context, ref)),
            child: Text(
              post.body.trim().isEmpty ? post.title : post.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return HubSurface(
      onTap: () => unawaited(_openComments(context, ref)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AvatarPreview(loadout: post.authorAvatar, height: 52),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      post.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.textPrimary,
                      ),
                    ),
                    Text(
                      _metaLine,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              HubPill(label: _kindLabel, background: _kindTint),
            ],
          ),
          if (post.isShareBilibili) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (cover != null && cover.isNotEmpty)
                      Image.network(
                        cover,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _coverFallback(),
                      )
                    else
                      _coverFallback(),
                    Center(
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (post.title.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              post.title,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textPrimary,
              ),
            ),
          ],
          if (post.body.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              post.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ],
          if (post.isShareBilibili) ...<Widget>[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                if (post.interestTag != null)
                  HubPill(label: '兴趣 · ${post.interestTag}'),
                if (post.englishLevel != null)
                  HubPill(
                    label: '难度 · ${post.englishLevel}',
                    background: const Color(0xFFFFF1D6),
                    foreground: AppDesignTokens.orange,
                  ),
                HubPill(
                  label: '归类有误？',
                  onTap: () => unawaited(_requestReclassify(context, ref)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              InkWell(
                onTap: () => unawaited(
                  ref
                      .read(communityFeedProvider.notifier)
                      .toggleLike(post.id, enabled: !post.likedByMe),
                ),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: <Widget>[
                    Icon(
                      post.likedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 18,
                      color: post.likedByMe
                          ? Colors.redAccent
                          : AppDesignTokens.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${post.likeCount}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 18,
                color: AppDesignTokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${post.commentCount}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textSecondary,
                ),
              ),
              const Spacer(),
              if (challengeLevel != null)
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => ExplorationMapScreen(sharedLevel: challengeLevel),
                    ),
                  ),
                  child: const Text('练同一关'),
                ),
              if (post.isShareBilibili)
                TextButton.icon(
                  onPressed: () => unawaited(_openLink(context, ref)),
                  icon: Icon(
                    Icons.play_circle_outline,
                    size: 18,
                    color: AppDesignTokens.primaryBlueDark,
                  ),
                  label: Text(
                    '我也想学',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.primaryBlueDark,
                    ),
                  ),
                ),
              if (post.isShareBilibili)
                TextButton(
                  onPressed: () => unawaited(_openBilibiliLike(context)),
                  child: Text(
                    'B 站',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppDesignTokens.primaryBlueDark,
                    ),
                  ),
                ),
            ],
          ),
          CommunityPostActions(post: post),
        ],
      ),
    );
  }

  Widget _coverFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppDesignTokens.primaryBlue,
            AppDesignTokens.brandGreen,
          ],
        ),
      ),
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

  Future<void> _openBilibiliLike(BuildContext context) async {
    final String? open = post.bilibiliOpenUrl ?? post.linkUrl;
    if (open == null || open.isEmpty) return;
    final Uri web = Uri.parse(open);
    final String? bvid = post.bvid;
    if (bvid != null && bvid.isNotEmpty) {
      final Uri app = Uri.parse('bilibili://video/$bvid');
      try {
        if (await openUrl(app)) return;
      } catch (_) {}
    }
    await openUrl(web);
  }

  Future<void> _openComments(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _CommentsSheet(post: post),
    );
    await ref.read(communityFeedProvider.notifier).refresh();
  }

  Future<void> _requestReclassify(BuildContext context, WidgetRef ref) async {
    final TextEditingController tag = TextEditingController(
      text: post.interestTag ?? 'daily',
    );
    final TextEditingController level = TextEditingController(
      text: post.englishLevel ?? 'B1',
    );
    final TextEditingController reason = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('申请重新归类'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: tag,
                decoration: const InputDecoration(
                  labelText: '兴趣标签（如 news / daily）',
                ),
              ),
              TextField(
                controller: level,
                decoration: const InputDecoration(labelText: '英语难度（如 A2 / B1）'),
              ),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: '原因说明'),
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
            child: const Text('提交'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(acquireApiClientProvider)
          .requestCommunityReclassify(
            postId: post.id,
            interestTag: tag.text.trim(),
            englishLevel: level.text.trim(),
            reason: reason.text.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已提交归类纠错，审核通过后会更新')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提交失败：$e')));
    }
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
