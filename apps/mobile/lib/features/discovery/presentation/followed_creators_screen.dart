import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/presentation/widgets/study_shell_tokens.dart';
import '../../sync/data/acquire_api_client.dart';
import '../../sync/presentation/daily_feed_provider.dart';

/// Manage followed Bilibili / YouTube creators for Discover recommendations.
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

  Future<void> _followFromUrl() async {
    final String url = _urlController.text.trim();
    if (url.isEmpty || _busy) {
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
        const SnackBar(content: Text('已关注。发现页会推荐其视频，导入仍需手动确认。')),
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
            '粘贴 B 站空间或 YouTube 频道链接。关注后其视频会出现在发现推荐，'
            '点开后仍需自行导入到本地。',
            style: TextStyle(color: StudyShellTokens.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: '博主主页链接',
              hintText: 'https://space.bilibili.com/… 或 YouTube 频道',
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
              subtitle: Text('关注后，对方新视频会出现在发现页推荐。'),
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
