import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sync/data/acquire_api_client.dart';
import '../data/community_models.dart';
import 'community_provider.dart';
import 'community_social_provider.dart';

class CommunityPostActions extends ConsumerWidget {
  const CommunityPostActions({super.key, required this.post});
  final CommunityPostDto post;

  Future<void> _act(BuildContext context, WidgetRef ref, String action) async {
    final Map<String, dynamic> social =
        ref.read(communitySocialProvider).asData?.value ?? <String, dynamic>{};
    final bool following = (social['following'] as List<dynamic>? ?? [])
        .contains(post.authorId);
    final bool bookmarked = (social['bookmarks'] as List<dynamic>? ?? [])
        .contains(post.id);
    final AcquireApiClient api = ref.read(acquireApiClientProvider);
    try {
      if (action == 'share') {
        final Map<String, String>? draft =
            await showDialog<Map<String, String>>(
              context: context,
              builder: (_) => const _ShareCardDialog(),
            );
        if (draft == null || !context.mounted) return;
        final Map<String, dynamic> created = await api.learningCardRequest(
          'POST',
          '',
          data: <String, dynamic>{'post_id': post.id, ...draft},
        );
        if (!context.mounted) return;
        await Clipboard.setData(
          ClipboardData(text: '${post.title}\n${created['share_url']}'),
        );
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('公开学习卡已创建，链接已复制。'),
              action: SnackBarAction(
                label: '撤回',
                onPressed: () async {
                  await api.learningCardRequest(
                    'DELETE',
                    '/${created['token']}',
                  );
                },
              ),
            ),
          );
        return;
      }
      if (action == 'report') {
        final String? reason = await showDialog<String>(
          context: context,
          builder: (_) => const _ReportDialog(),
        );
        if (reason == null) return;
        await api.socialRequest(
          'POST',
          '/posts/${post.id}/report',
          data: <String, dynamic>{'reason': reason},
        );
      } else if (action == 'follow') {
        await api.socialRequest(
          following ? 'DELETE' : 'PUT',
          '/following/${post.authorId}',
        );
      } else if (action == 'bookmark') {
        await api.socialRequest(
          bookmarked ? 'DELETE' : 'PUT',
          '/bookmarks/${post.id}',
        );
      } else {
        final bool? confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text(action == 'block' ? '屏蔽该用户' : '删除我的帖子'),
            content: Text(
              action == 'block'
                  ? '隐藏其内容，停止互动与邀请；如是同桌会解除关系，可在消息与管理中解除屏蔽。'
                  : '删除后帖子及其公开学习卡不再可访问。',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await api.socialRequest(
          action == 'block' ? 'PUT' : 'DELETE',
          action == 'block' ? '/blocks/${post.authorId}' : '/posts/${post.id}',
        );
      }
      ref.invalidate(communitySocialProvider);
      await ref.read(communityFeedProvider.notifier).refresh();
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'report' ? '举报已提交，可在消息与管理查看处理状态。' : '操作已保存',
            ),
          ),
        );
    } catch (_) {
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请检查网络或刷新后重试。')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Map<String, dynamic> social =
        ref.watch(communitySocialProvider).asData?.value ?? <String, dynamic>{};
    final bool own = social['my_id'] == post.authorId;
    final bool followed = (social['following'] as List<dynamic>? ?? [])
        .contains(post.authorId);
    final bool saved = (social['bookmarks'] as List<dynamic>? ?? []).contains(
      post.id,
    );
    return Wrap(
      spacing: 8,
      children: <Widget>[
        TextButton.icon(
          onPressed: () => _act(context, ref, 'bookmark'),
          icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
          label: Text(saved ? '已收藏' : '收藏去学'),
        ),
        if (!own)
          TextButton(
            onPressed: () => _act(context, ref, 'follow'),
            child: Text(followed ? '已关注' : '关注作者'),
          ),
        if (post.isShareBilibili)
          TextButton.icon(
            onPressed: () => _act(context, ref, 'share'),
            icon: const Icon(Icons.share_outlined),
            label: const Text('制作学习卡'),
          ),
        PopupMenuButton<String>(
          tooltip: '更多操作',
          onSelected: (String value) => _act(context, ref, value),
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            const PopupMenuItem(value: 'report', child: Text('举报内容')),
            if (!own) const PopupMenuItem(value: 'block', child: Text('屏蔽作者')),
            if (own) const PopupMenuItem(value: 'delete', child: Text('删除帖子')),
          ],
        ),
      ],
    );
  }
}

class _ShareCardDialog extends StatefulWidget {
  const _ShareCardDialog();
  @override
  State<_ShareCardDialog> createState() => _ShareCardDialogState();
}

class _ShareCardDialogState extends State<_ShareCardDialog> {
  final TextEditingController _expression = TextEditingController();
  final TextEditingController _meaning = TextEditingController();
  @override
  void dispose() {
    _expression.dispose();
    _meaning.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('制作公开学习卡'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            '你填写的这一句表达和释义将公开分享，任何持链接者可免费练一句。不要填写私人信息；不会自动附带个人词库、录音或私有视频。',
          ),
          TextField(
            controller: _expression,
            maxLength: 240,
            decoration: const InputDecoration(labelText: '英文表达'),
          ),
          TextField(
            controller: _meaning,
            maxLength: 500,
            decoration: const InputDecoration(labelText: '中文释义'),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_expression.text.trim().isNotEmpty &&
              _meaning.text.trim().isNotEmpty)
            Navigator.pop(context, <String, String>{
              'expression': _expression.text.trim(),
              'meaning': _meaning.text.trim(),
            });
        },
        child: const Text('确认公开并复制链接'),
      ),
    ],
  );
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();
  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final TextEditingController _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('举报内容'),
    content: TextField(
      controller: _reason,
      maxLength: 500,
      maxLines: 4,
      decoration: const InputDecoration(labelText: '请说明问题（至少2个字）'),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_reason.text.trim().length >= 2)
            Navigator.pop(context, _reason.text.trim());
        },
        child: const Text('提交举报'),
      ),
    ],
  );
}
