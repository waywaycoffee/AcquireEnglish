import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_session.dart';
import '../../sync/data/acquire_api_client.dart';
import '../domain/cafe_adventure.dart';
import 'community_provider.dart';

class PublishLearningResultScreen extends ConsumerStatefulWidget {
  const PublishLearningResultScreen({
    super.key,
    required this.initialText,
    this.challengePath,
  });

  final String? challengePath;
  final String initialText;

  @override
  ConsumerState<PublishLearningResultScreen> createState() =>
      _PublishLearningResultScreenState();
}

class _PublishLearningResultScreenState
    extends ConsumerState<PublishLearningResultScreen> {
  late final TextEditingController _body;
  final TextEditingController _title = TextEditingController(text: '今天的学习收获');
  bool _public = false;
  bool _busy = false;

  int? get _challengeLevel => cafeLevelFromPath(widget.challengePath);

  String? get _publicWebUrl {
    final int? level = _challengeLevel;
    if (level == null) return null;
    return 'https://acquireenglish.curlhairai.com/api/public/challenges/cafe/${level + 1}';
  }

  String? get _appDeepLink {
    final int? level = _challengeLevel;
    if (level == null) return null;
    return 'acquireenglish://app/explore/cafe/${level + 1}';
  }

  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _body.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _copyWeChatLink() async {
    final String? url = _publicWebUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制微信可打开的关卡链接')),
      );
    }
  }

  Future<void> _submit() async {
    if (_busy || _body.text.trim().isEmpty) return;
    if (!_public) {
      await Clipboard.setData(ClipboardData(text: _body.text.trim()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制个人文案，没有公开发布')),
        );
      }
      return;
    }
    if (!ref.read(authSessionProvider).isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后发布社区内容')),
      );
      return;
    }
    final String token = ref.read(authSessionProvider).accessToken;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认公开发布'),
        content: Text(
          '${_title.text}\n\n${_body.text}\n\n以上文字将对社区用户公开，请确认没有私人信息。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认发布'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        token != ref.read(authSessionProvider).accessToken) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(acquireApiClientProvider).createCommunityPost(
            kind: 'learning_result',
            title: _title.text.trim(),
            body: _body.text.trim(),
            linkUrl: widget.challengePath,
          );
      if (!mounted || token != ref.read(authSessionProvider).accessToken) {
        return;
      }
      ref.invalidate(communityFeedProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学习成果已发布到社区')),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('发布未完成，编辑内容已保留，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authSessionProvider.select((AuthSessionState s) => s.accessToken),
      (String? old, String next) {
        if (old != next) {
          setState(() {
            _body.clear();
            _public = false;
            _busy = false;
          });
        }
      },
    );
    final int? level = _challengeLevel;
    return Scaffold(
      appBar: AppBar(title: const Text('编辑学习成果')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text('默认仅保留给自己。不会自动附带录音、具体词条或个人视频。'),
          if (level != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                title: Text('关卡 · ${kCafeLevels[level].title}'),
                subtitle: Text(
                  '微信打开：${_publicWebUrl}\n已安装深链：${_appDeepLink}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: '复制微信链接',
                  onPressed: _copyWeChatLink,
                  icon: const Icon(Icons.copy_rounded),
                ),
              ),
            ),
          ],
          TextField(
            controller: _title,
            maxLength: 200,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          TextField(
            controller: _body,
            maxLength: 4000,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '分享文案'),
          ),
          SwitchListTile(
            value: _public,
            onChanged: _busy
                ? null
                : (bool value) => setState(() => _public = value),
            title: const Text('公开到社区'),
            subtitle: const Text('关闭时仅复制文案，不提交到服务器。'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? '发布中…'
                  : _public
                      ? '预览并确认发布'
                      : '复制我的文案',
            ),
          ),
          if (level != null) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _copyWeChatLink,
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('复制关卡链接（未安装也可打开看题）'),
            ),
          ],
        ],
      ),
    );
  }
}
