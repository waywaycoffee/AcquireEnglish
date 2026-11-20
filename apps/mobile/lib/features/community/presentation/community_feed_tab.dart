import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../../utils/url_utils.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';
import '../data/community_models.dart';
import 'community_provider.dart';

class CommunityFeedTab extends ConsumerWidget {
  const CommunityFeedTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CommunityPostDto>> async =
        ref.watch(communityFeedProvider);

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
              if (posts.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  children: const <Widget>[
                    Text(
                      '社区以大家分享的 B 站视频帖为主。点右下角发帖：'
                      '分享视频、组队邀请或吐槽软件功能。',
                    ),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  return _PostCard(post: posts[index]);
                },
              );
            },
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _showComposer(context, ref),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('发帖'),
          ),
        ),
      ],
    );
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

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post});

  final CommunityPostDto post;

  String get _kindLabel {
    switch (post.kind) {
      case 'team_invite':
        return '组队';
      case 'share_bilibili':
        return 'B站';
      case 'feedback':
        return '吐槽';
      default:
        return post.kind;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => unawaited(_openComments(context, ref)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Chip(
                    label: Text(_kindLabel),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${post.authorName}'
                      '${post.authorLevel == null ? '' : ' · ${post.authorLevel}'}',
                      style: Theme.of(context).textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: post.likedByMe ? '取消赞' : '点赞',
                    onPressed: () => unawaited(
                      ref
                          .read(communityFeedProvider.notifier)
                          .toggleLike(post.id),
                    ),
                    icon: Icon(
                      post.likedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: post.likedByMe ? Colors.redAccent : null,
                    ),
                  ),
                  Text('${post.likeCount}'),
                ],
              ),
              if (post.title.isNotEmpty) ...<Widget>[
                Text(
                  post.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
              ],
              if (post.body.isNotEmpty)
                Text(post.body, style: const TextStyle(height: 1.45)),
              if (post.isShareBilibili) ...<Widget>[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    if (post.interestTag != null)
                      Chip(
                        label: Text('兴趣 · ${post.interestTag}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (post.englishLevel != null)
                      Chip(
                        label: Text('难度 · ${post.englishLevel}'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ActionChip(
                      label: const Text('归类有误？'),
                      onPressed: () =>
                          unawaited(_requestReclassify(context, ref)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_openLink(context, ref)),
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(
                        post.linkTitle?.isNotEmpty == true
                            ? '我也想学 · ${post.linkTitle}'
                            : '我也想学',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_openBilibiliLike(context)),
                      icon: const Icon(Icons.thumb_up_alt_outlined),
                      label: const Text('去 B 站点赞'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Text(
                '评论 ${post.commentCount} · 点进帖子互动',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
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
                decoration: const InputDecoration(
                  labelText: '英语难度（如 A2 / B1）',
                ),
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
      await ref.read(acquireApiClientProvider).requestCommunityReclassify(
            postId: post.id,
            interestTag: tag.text.trim(),
            englishLevel: level.text.trim(),
            reason: reason.text.trim(),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交归类纠错，审核通过后会更新')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败：$e')),
      );
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
      final List<CommunityCommentDto> rows =
          await ref.read(acquireApiClientProvider).communityComments(
                widget.post.id,
              );
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('评论加载失败：$e')),
      );
    }
  }

  Future<void> _submit() async {
    final String text = _body.text.trim();
    if (text.isEmpty || _busy) return;
    final bool hasCookie =
        ref.read(learningPreferencesProvider).hasBilibiliCookie;
    if (_mirror && !hasCookie) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置中授权 B 站 Cookie，再同步评论')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final CommunityCommentDto created =
          await ref.read(acquireApiClientProvider).createCommunityComment(
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已同步到 B 站视频评论区')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败：$e')),
      );
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
        return '吐槽软件功能';
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请粘贴 B 站视频链接')),
        );
        return;
      }
      if (_isYoutubeUrl(link)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('因政策原因，暂时不支持分享 YouTube 视频，请改用 B 站链接'),
          ),
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
      await ref.read(communityFeedProvider.notifier).createPost(
            kind: widget.kind,
            title: _title.text.trim(),
            body: _body.text.trim(),
            linkUrl:
                widget.kind == 'share_bilibili' ? _link.text.trim() : null,
            linkTitle:
                widget.kind == 'share_bilibili' ? _title.text.trim() : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已发布')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发布失败：$e')),
      );
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
