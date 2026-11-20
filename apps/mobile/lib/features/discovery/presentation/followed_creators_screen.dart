import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';

/// Manage followed Bilibili creators for Home recommendations.
class FollowedCreatorsScreen extends ConsumerStatefulWidget {
  const FollowedCreatorsScreen({super.key});

  @override
  ConsumerState<FollowedCreatorsScreen> createState() =>
      _FollowedCreatorsScreenState();
}

class _FollowedCreatorsScreenState extends ConsumerState<FollowedCreatorsScreen> {
  final TextEditingController _urlController = TextEditingController();
  List<FollowedCreatorDto> _creators = const <FollowedCreatorDto>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reload());
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<FollowedCreatorDto> list =
          await ref.read(acquireApiClientProvider).listFollowedCreators();
      if (!mounted) {
        return;
      }
      setState(() {
        _creators = list;
        _loading = false;
      });
      await ref.read(learningPreferencesProvider.notifier).pullRemote();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  bool _looksLikeYoutube(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    final String host = uri.host.toLowerCase().replaceFirst('www.', '');
    return host == 'youtu.be' ||
        host == 'youtube.com' ||
        host == 'm.youtube.com' ||
        host.endsWith('.youtube.com');
  }

  Future<void> _followFromUrl() async {
    final String url = _urlController.text.trim();
    if (url.isEmpty || _busy) {
      return;
    }
    if (_looksLikeYoutube(url)) {
      setState(() {
        _error = '因政策原因，暂时不支持关注 YouTube 博主，请粘贴 B 站空间链接。';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final List<FollowedCreatorDto> list =
          await ref.read(acquireApiClientProvider).followCreator(url: url);
      if (!mounted) {
        return;
      }
      _urlController.clear();
      setState(() {
        _creators = list;
        _busy = false;
      });
      await ref.read(learningPreferencesProvider.notifier).pullRemote();
      await ref.read(dailyFeedProvider.notifier).refresh(force: true);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已关注。首页会推荐其视频，导入仍需手动确认。')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '关注失败：$e';
      });
    }
  }

  Future<void> _unfollow(FollowedCreatorDto creator) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final List<FollowedCreatorDto> list = await ref
          .read(acquireApiClientProvider)
          .unfollowCreator(
            source: creator.source,
            creatorId: creator.creatorId,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _creators = list;
        _busy = false;
      });
      await ref.read(learningPreferencesProvider.notifier).pullRemote();
      await ref.read(dailyFeedProvider.notifier).refresh(force: true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _error = '取消关注失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StudyShellTokens.background,
      appBar: AppBar(
        backgroundColor: StudyShellTokens.background,
        foregroundColor: StudyShellTokens.textPrimary,
        title: const Text('关注博主'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            '粘贴你喜欢的 B 站 UP 主空间链接。关注后其视频会出现在首页推荐，'
            '点开后仍需自行导入。因政策原因，YouTube 博主暂时不支持关注。',
            style: TextStyle(color: StudyShellTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'B 站空间链接',
              hintText: 'https://space.bilibili.com/…',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _followFromUrl(),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _followFromUrl,
            child: Text(_busy ? '处理中…' : '关注'),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ],
          const SizedBox(height: 20),
          Text(
            '已关注 · ${_creators.length}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: StudyShellTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const LinearProgressIndicator()
          else if (_creators.isEmpty)
            const ListTile(
              title: Text('还没有关注博主'),
              subtitle: Text('把喜欢的 B 站博主加进来，首页会优先推他们的新片。'),
            )
          else
            for (final FollowedCreatorDto c in _creators)
              ListTile(
                leading: c.avatarUrl == null
                    ? Icon(
                        c.source == 'youtube'
                            ? Icons.play_circle_outline
                            : Icons.person_outline,
                      )
                    : CircleAvatar(
                        backgroundImage: NetworkImage(c.avatarUrl!),
                      ),
                title: Text(
                  c.displayName.isEmpty ? c.creatorId : c.displayName,
                ),
                subtitle: Text(
                  c.source == 'youtube' ? 'YouTube' : 'B站',
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _unfollow(c),
                  child: const Text('取消关注'),
                ),
              ),
        ],
      ),
    );
  }
}
