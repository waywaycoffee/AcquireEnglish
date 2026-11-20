import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../router/app_router.dart';
import '../../import_course/presentation/bilibili_import_sheet.dart';
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
                    Text('还没有动态。点右下角发帖吐槽、分享方法或视频链接。'),
                  ],
                );
              }
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                itemCount: posts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final CommunityPostDto post = posts[index];
                  return _PostCard(post: post);
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
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('吐槽缺陷'),
              onTap: () => Navigator.pop(ctx, 'feedback'),
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('分享学习方法'),
              onTap: () => Navigator.pop(ctx, 'method'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('分享视频链接'),
              onTap: () => Navigator.pop(ctx, 'share_link'),
            ),
            ListTile(
              leading: const Icon(Icons.mic_none_rounded),
              title: const Text('录制英语播客'),
              subtitle: const Text('即将开放'),
              onTap: () => Navigator.pop(ctx, 'podcast'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    if (choice == 'podcast') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('播客上传即将开放，敬请期待。')),
      );
      return;
    }
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
      case 'feedback':
        return '吐槽';
      case 'share_link':
        return '分享';
      case 'method':
        return '方法';
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
            if (post.isShareLink && (post.linkUrl?.isNotEmpty ?? false)) ...<
                Widget>[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => unawaited(_openLink(context, ref, post)),
                icon: const Icon(Icons.play_circle_outline),
                label: Text(post.linkTitle?.isNotEmpty == true
                    ? '我也想学 · ${post.linkTitle}'
                    : '我也想学'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openLink(
    BuildContext context,
    WidgetRef ref,
    CommunityPostDto post,
  ) async {
    final String url = post.linkUrl!.trim();
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
      case 'feedback':
        return '吐槽缺陷';
      case 'share_link':
        return '分享视频链接';
      default:
        return '分享学习方法';
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(communityFeedProvider.notifier).createPost(
            kind: widget.kind,
            title: _title.text.trim(),
            body: _body.text.trim(),
            linkUrl: widget.kind == 'share_link' ? _link.text.trim() : null,
            linkTitle: widget.kind == 'share_link' ? _title.text.trim() : null,
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
            Text(
              _heading,
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
            if (widget.kind == 'share_link') ...<Widget>[
              const SizedBox(height: 10),
              TextField(
                controller: _link,
                decoration: const InputDecoration(
                  labelText: '视频链接',
                  hintText: 'https://www.bilibili.com/video/…',
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
